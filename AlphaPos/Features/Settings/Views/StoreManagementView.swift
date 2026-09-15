import SwiftUI
import PhotosUI
import CoreImage
import SwiftData
import AVKit
import UniformTypeIdentifiers

struct StoreManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var columnVisibility: NavigationSplitViewVisibility

    /// Enterprise teal–slate accent shared with Employee / Organization workspaces.
    private let storeAccent = Color(hex: "0F766E")
    private let storeAccentDeep = Color(hex: "334155")

    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all)) {
        _columnVisibility = columnVisibility
    }

    // Store settings stored in UserDefaults
    @AppStorage("store_name") private var storeName = "AlphaPos Restaurant"
    @AppStorage("store_phone") private var storePhone = "02-123-4567"
    @AppStorage("store_website") private var storeWebsite = "www.alphapos.restaurant"
    @AppStorage("store_address") private var storeAddress = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id") private var storeTaxId = ""
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_tax_rate") private var storeTaxRate = 7.0
    @AppStorage("store_tax_type") private var storeTaxType = "inclusive" // "inclusive", "exclusive"
    @AppStorage("store_service_charge_rate") private var storeServiceChargeRate = 10.0
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("escpos_thai_code_page") private var escposThaiCodePage = 20
    @AppStorage("enable_service_charge") private var enableServiceCharge = true
    @AppStorage("store_receipt_header") private var storeReceiptHeader = "Welcome to AlphaPos!"
    @AppStorage("store_receipt_footer") private var storeReceiptFooter = "Thank you for dining with us!\nVAT Included."
    @AppStorage("store_logo_path") private var storeLogoPath = ""
    @AppStorage("promptpay_number") private var promptPayNumber = ""

    // QR Code Customizer settings
    @AppStorage("qr_custom_store_name") private var qrCustomStoreName = "AlphaPos Restaurant"
    @AppStorage("qr_custom_header") private var qrCustomHeader = "Scan to Order"
    @AppStorage("qr_custom_show_logo") private var qrCustomShowLogo = true
    @AppStorage("qr_custom_logo_preset") private var qrCustomLogoPreset = "bolt.fill"
    @AppStorage("qr_custom_color") private var qrCustomColor = "#111115"

    @State private var logoItem: PhotosPickerItem? = nil
    @State private var logoImage: UIImage? = nil
    @State private var webCoverItem: PhotosPickerItem? = nil
    @State private var webCoverURL = ""
    @State private var webCoverMediaType = "image"
    @State private var isUploadingWebCover = false
    @State private var webCoverError: String? = nil
    @State private var webCoverPlayer: AVPlayer? = nil

    @State private var activeTab: ConfigTab = .profile
    @EnvironmentObject private var lm: LocalizationManager
    // L-6: Multi-Branch
    @Query(sort: \Branch.name) private var branches: [Branch]
    @State private var showingAddBranch = false
    @State private var branchToEdit: Branch? = nil

    enum ConfigTab: String, CaseIterable {
        case profile = "General Profile"
        case taxation = "Tax & Service Charge"
        case qrCustomizer = "QR Code Customizer"
        case branches = "Branches"              // L-6
        var icon: String {
            switch self {
            case .profile: return "storefront.fill"
            case .taxation: return "percent"
            case .qrCustomizer: return "qrcode"
            case .branches:     return "building.2.fill"
            }
        }
        var localizedName: String {
            switch self {
            case .profile: return L.Store.tabProfile.t
            case .taxation: return L.Store.tabTax.t
            case .qrCustomizer: return L.Store.tabQR.t
            case .branches:     return "store_branches_tab".t
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                // LEFT COLUMN: Forms / Configuration
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if activeTab == .profile {
                            generalProfileForm
                        } else if activeTab == .taxation {
                            taxationForm
                        } else if activeTab == .qrCustomizer {
                            qrCustomizerForm
                        } else {
                            branchesTab
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, APSpacing.md)
                }
                .frame(maxWidth: .infinity)

                // RIGHT COLUMN: Live Preview Panel (Receipt or QR Card)
                Group {
                    if activeTab == .qrCustomizer {
                        qrCardPreviewPanel
                    } else if activeTab == .branches {
                        branchSummaryPanel
                    } else {
                        receiptPreviewPanel
                    }
                }
                .padding(.trailing, APSpacing.md)
                .padding(.vertical, APSpacing.md)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(L.Store.title.t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                workspaceHeader
            }
        }
        .onAppear {
            loadSavedLogo()
            loadMerchantWebCover()
        }
        // L-6: Branch sheets
        .sheet(isPresented: $showingAddBranch) {
            BranchEditSheet(branch: nil) { name, loc, phone, cutoff, timeZone in
                let b = Branch(name: name, location: loc.isEmpty ? nil : loc, phone: phone.isEmpty ? nil : phone, businessDayCutoffHour: cutoff, timeZoneID: timeZone)
                modelContext.insert(b)
                modelContext.saveWithLogging(label: "StoreManagementView.addBranch")
                // Auto-activate when no valid branch is selected yet, so features that
                // depend on active_branch_id (device pairing, POS, inventory) work
                // immediately without an extra "Select Store" tap.
                let selectedID = UUID(uuidString: activeBranchId)
                let hasValidActive = branches.contains { !$0.isDeleted && $0.id == selectedID }
                if !hasValidActive {
                    BranchContext.shared.select(b)
                }
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        }
        .sheet(item: $branchToEdit) { branch in
            BranchEditSheet(branch: branch) { name, loc, phone, cutoff, timeZone in
                branch.name = name
                branch.location = loc.isEmpty ? nil : loc
                branch.phone = phone.isEmpty ? nil : phone
                branch.businessDayCutoffHour = cutoff
                branch.timeZoneID = timeZone
                branch.isSynced = false; branch.updatedAt = Date()
                modelContext.saveWithLogging(label: "StoreManagementView.editBranch")
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        }
    }

    // MARK: - Workspace Header (matches Employee Management)

    private var workspaceHeader: some View {
        HStack(spacing: 3) {
            ForEach(ConfigTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { activeTab = tab }
                } label: {
                    Label(tab.localizedName, systemImage: tab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(activeTab == tab ? Color.white : Color.textSecondary)
                        .background {
                            if activeTab == tab {
                                Capsule().fill(storeAccent)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activeTab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.appSurfaceHigh, in: Capsule())
        .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // MARK: - General Profile Form
    private var generalProfileForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.Store.brandingHeader.t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(storeAccent)
                .tracking(1.0)

            VStack(spacing: 16) {
                // Logo Upload circle and buttons
                HStack(spacing: 20) {
                    if let logo = logoImage {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1.5))
                            .shadow(radius: 4)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.appSurfaceHigh)
                                .frame(width: 72, height: 72)
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoItem, matching: .images, photoLibrary: .shared()) {
                            Label(L.Store.selectLogo.t, systemImage: "photo.badge.plus")
                                .font(.system(size: 12))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [storeAccent, Color(hex: "14B8A6")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(APRadius.md)
                                .shadow(color: storeAccent.opacity(0.28), radius: 8, x: 0, y: 3)
                        }
                        .onChange(of: logoItem) { _, newItem in
                            if let newItem {
                                loadSelectedLogo(from: newItem)
                            }
                        }

                        if logoImage != nil {
                            Button(action: {
                                logoImage = nil
                                storeLogoPath = ""
                                APHaptic.trigger()
                            }) {
                                Text("remove_logo".t)
                                    .font(.system(size: 12))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.appRose)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                Divider()
                    .background(Color.appDivider)

                merchantWebCoverEditor

                Divider()
                    .background(Color.appDivider)

                // Fields
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.nameLabel.t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField(L.Store.nameLabel.t, text: $storeName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeName) { triggerSync() }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("store_phone".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("phone_number_label".t, text: $storePhone)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .onChange(of: storePhone) { triggerSync() }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.Store.websiteLabel.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("store_website".t, text: $storeWebsite)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .onChange(of: storeWebsite) { triggerSync() }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("store_address".t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("full_address_placeholder".t, text: $storeAddress)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeAddress) { triggerSync() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("promptpay_number_label".t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("promptpay_number_label".t, text: $promptPayNumber)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: promptPayNumber) { triggerSync() }
                }
            }
            .apCard()

        }
    }

    private var merchantWebCoverEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("หน้าปกเว็บไซต์สั่งอาหาร")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("ภาพจะครอปเป็น 1200 × 500 px (2.4:1) · เว้นข้อความจากขอบซ้าย–ขวาอย่างน้อย 10%")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                    Text("รองรับ JPG, PNG หรือ MP4 · ภาพไม่เกิน 10 MB · วิดีโอไม่เกิน 50 MB")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                if isUploadingWebCover { ProgressView().tint(storeAccent) }
            }

            Group {
                if webCoverMediaType == "video", let player = webCoverPlayer {
                    VideoPlayer(player: player)
                        .onAppear { player.isMuted = true; player.play() }
                        .onDisappear { player.pause() }
                } else if !webCoverURL.isEmpty, let url = URL(string: webCoverURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { coverPlaceholder }
                    }
                } else {
                    coverPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $webCoverItem,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Label(webCoverURL.isEmpty ? "เลือกภาพหรือวิดีโอ" : "เปลี่ยนหน้าปก", systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(storeAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isUploadingWebCover)
                .onChange(of: webCoverItem) { _, item in
                    if let item { uploadMerchantWebCover(from: item) }
                }

                if !webCoverURL.isEmpty {
                    Button(role: .destructive) { removeMerchantWebCover() } label: {
                        Label("ลบหน้าปก", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .disabled(isUploadingWebCover)
                }
                Spacer()
            }

            if let webCoverError {
                Text(webCoverError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.appRose)
            }
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "11120F"), storeAccent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 28)).foregroundColor(.white.opacity(0.85))
                Text("ยังไม่ได้ตั้งค่าหน้าปก").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Taxation Form
    private var taxationForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("taxation_receipts_settings".t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(storeAccent)
                .tracking(1.0)

            // ── Advanced Tax Info Banner ─────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "6366F1"))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("store_tax_basic_title".t)
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "10B981"))
                        Text("store_tax_shared_fields".t)
                            .font(.system(size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(Color(hex: "10B981"))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "6366F1"))
                        Text("store_tax_advanced_fields".t)
                            .font(.system(size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(Color(hex: "6366F1"))
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "6366F1").opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "6366F1").opacity(0.2), lineWidth: 1)
            )

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("tax_id_vat_registration".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("13-digit ID", text: $storeTaxId)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .keyboardType(.numberPad)
                            .onChange(of: storeTaxId) { triggerSync() }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.Store.branchLabel.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField(L.Store.branchLabel.t, text: $storeBranchCode)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .onChange(of: storeBranchCode) { triggerSync() }
                    }
                }

                Toggle("store_enable_vat".t, isOn: $enableTax)
                    .tint(storeAccent)
                    .onChange(of: enableTax) { triggerSync() }

                Toggle("store_enable_service_charge".t, isOn: $enableServiceCharge)
                    .tint(storeAccent)
                    .onChange(of: enableServiceCharge) { triggerSync() }

                Divider()
                    .background(Color.appDivider)

                if enableTax {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("tax_calculation_mode".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        Picker("tax_calculation_mode".t, selection: $storeTaxType) {
                            Text(L.Store.taxInclusiveOpt.t).tag("inclusive")
                            Text(L.Store.taxExclusiveOpt.t).tag("exclusive")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: storeTaxType) { triggerSync() }
                    }
                }

                if enableTax || enableServiceCharge {
                    HStack(spacing: 16) {
                        if enableTax {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("default_tax_rate".t)
                                    .font(.system(size: 12))
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                HStack {
                                    TextField("7.0", value: $storeTaxRate, format: .number)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .keyboardType(.decimalPad)
                                    Text("%").foregroundColor(.textSecondary)
                                }
                                .padding(12)
                                .background(Color.appSurfaceHigh)
                                .foregroundColor(.textPrimary)
                                .cornerRadius(APRadius.md)
                                .onChange(of: storeTaxRate) { triggerSync() }
                            }
                        }

                        if enableServiceCharge {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("service_charge_percent".t)
                                    .font(.system(size: 12))
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                HStack {
                                    TextField("10.0", value: $storeServiceChargeRate, format: .number)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .keyboardType(.decimalPad)
                                    Text("%").foregroundColor(.textSecondary)
                                }
                                .padding(12)
                                .background(Color.appSurfaceHigh)
                                .foregroundColor(.textPrimary)
                                .cornerRadius(APRadius.md)
                                .onChange(of: storeServiceChargeRate) { triggerSync() }
                            }
                        }
                    }
                }

                Divider()
                    .background(Color.appDivider)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ESC/POS Thai code page")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("20", value: $escposThaiCodePage, format: .number)
                        .textFieldStyle(PlainTextFieldStyle())
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                    Text("XP-C300H ใช้ค่า 20; ปรับตามคู่มือเครื่องพิมพ์เมื่อภาษาไทยแสดงผิด")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("receipt_header_message".t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("receipt_header_message".t, text: $storeReceiptHeader)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeReceiptHeader) { triggerSync() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("receipt_footer_message".t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("receipt_footer_message".t, text: $storeReceiptFooter)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeReceiptFooter) { triggerSync() }
                }

                // ── Receipt Template override note ──────────────────────
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                    Text("store_receipt_defaults_note".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .apCard()
        }
    }

    // MARK: - Receipt Preview Panel
    private var receiptPreviewPanel: some View {
        // ใช้ ReceiptLivePreview component เดียวกันกับ Receipt Templates
        // เพื่อให้ preview ทั้งสองหน้า consistent กัน
        ReceiptLivePreview(
            storeName:         storeName,
            storeAddress:      storeAddress,
            storePhone:        storePhone,
            storeTaxId:        storeTaxId,
            storeBranchCode:   storeBranchCode,
            storeLogoPath:     storeLogoPath,
            promptPayNumber:   promptPayNumber,
            headerText:        storeReceiptHeader,
            footerText:        storeReceiptFooter,
            showTaxId:         true,
            showCustomerInfo:  true,
            paperWidth:        "80mm",
            showLogo:          true,
            showServiceCharge: true,
            showTableInfo:     true,
            showQRCode:        !promptPayNumber.isEmpty,
            showItemModifiers: true,
            showOrderType:     true,
            accentColor:       storeAccent
        )
    }

    // MARK: - Actions & Helpers
    private func triggerSync() {
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func loadSelectedLogo(from item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let resizedImage = resizeImage(uiImage, targetSize: CGSize(width: 256, height: 256))
                if let filepath = saveImageToDocuments(resizedImage) {
                    await MainActor.run {
                        self.logoImage = resizedImage
                        self.storeLogoPath = filepath
                    }
                    triggerSync()
                }
            }
        }
    }

    private func loadMerchantWebCover() {
        guard let rawId = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: rawId) else { return }
        Task {
            do {
                let settings = try await NetworkManager.shared.fetchMerchantSettings(merchantId: merchantId)
                let url = settings?["web_cover_url"] as? String ?? ""
                let type = settings?["web_cover_media_type"] as? String ?? "image"
                await MainActor.run { setWebCoverPreview(url: url, mediaType: type) }
            } catch {
                await MainActor.run { webCoverError = "ไม่สามารถโหลดข้อมูลหน้าปก: \(error.localizedDescription)" }
            }
        }
    }

    private func uploadMerchantWebCover(from item: PhotosPickerItem) {
        guard let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id"), !merchantId.isEmpty else {
            webCoverError = "ไม่พบรหัสร้านค้า กรุณาเข้าสู่ระบบใหม่"
            return
        }
        isUploadingWebCover = true
        webCoverError = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NetworkError.invalidResponse
                }
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                let isMP4 = item.supportedContentTypes.contains { $0.conforms(to: .mpeg4Movie) }
                if isVideo && !isMP4 {
                    throw NetworkError.serverError("กรุณาเลือกวิดีโอรูปแบบ MP4 เพื่อให้เล่นได้ทุกเบราว์เซอร์")
                }
                let maxBytes = isVideo ? 50 * 1_024 * 1_024 : 10 * 1_024 * 1_024
                guard data.count <= maxBytes else {
                    throw NetworkError.serverError(isVideo ? "วิดีโอต้องมีขนาดไม่เกิน 50 MB" : "รูปภาพต้องมีขนาดไม่เกิน 10 MB")
                }
                let uploadData: Data
                if isVideo {
                    uploadData = data
                } else if let image = UIImage(data: data),
                          let jpeg = cropBannerImage(image).jpegData(compressionQuality: 0.88) {
                    uploadData = jpeg
                } else {
                    throw NetworkError.serverError("ไม่สามารถประมวลผลไฟล์ภาพนี้ได้")
                }
                let type = isVideo ? "video" : "image"
                let url = try await NetworkManager.shared.uploadStoreWebCover(
                    uploadData,
                    merchantId: merchantId,
                    fileName: isVideo ? "web-cover.mp4" : "web-cover.jpg",
                    contentType: isVideo ? "video/mp4" : "image/jpeg"
                )
                try await NetworkManager.shared.updateMerchantWebCover(url: url, mediaType: type)
                await MainActor.run {
                    setWebCoverPreview(url: url, mediaType: type)
                    isUploadingWebCover = false
                    webCoverItem = nil
                    APHaptic.trigger()
                }
            } catch {
                await MainActor.run {
                    webCoverError = error.localizedDescription
                    isUploadingWebCover = false
                    webCoverItem = nil
                }
            }
        }
    }

    private func removeMerchantWebCover() {
        isUploadingWebCover = true
        webCoverError = nil
        Task {
            do {
                try await NetworkManager.shared.updateMerchantWebCover(url: nil, mediaType: "image")
                await MainActor.run {
                    setWebCoverPreview(url: "", mediaType: "image")
                    isUploadingWebCover = false
                    APHaptic.trigger()
                }
            } catch {
                await MainActor.run { webCoverError = error.localizedDescription; isUploadingWebCover = false }
            }
        }
    }

    private func setWebCoverPreview(url: String, mediaType: String) {
        webCoverURL = url
        webCoverMediaType = mediaType
        webCoverPlayer?.pause()
        webCoverPlayer = mediaType == "video" ? URL(string: url).map(AVPlayer.init(url:)) : nil
        webCoverPlayer?.isMuted = true
    }

    /// Produces the exact 2.4:1 artwork used by the customer-ordering hero.
    /// A centered aspect-fill crop prevents the website from applying a second,
    /// device-dependent crop after upload.
    private func cropBannerImage(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 1200, height: 500)
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let targetRatio = targetSize.width / targetSize.height
        let sourceRatio = sourceSize.width / sourceSize.height
        let cropSize: CGSize
        if sourceRatio > targetRatio {
            cropSize = CGSize(width: sourceSize.height * targetRatio, height: sourceSize.height)
        } else {
            cropSize = CGSize(width: sourceSize.width, height: sourceSize.width / targetRatio)
        }

        let cropOrigin = CGPoint(
            x: (sourceSize.width - cropSize.width) / 2,
            y: (sourceSize.height - cropSize.height) / 2
        )
        let drawRect = CGRect(
            x: -cropOrigin.x * targetSize.width / cropSize.width,
            y: -cropOrigin.y * targetSize.height / cropSize.height,
            width: sourceSize.width * targetSize.width / cropSize.width,
            height: sourceSize.height * targetSize.height / cropSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: drawRect)
        }
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let newSize = widthRatio > heightRatio ? CGSize(width: size.width * heightRatio, height: size.height * heightRatio) : CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        let rect = CGRect(origin: .zero, size: newSize)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? image
    }

    private func saveImageToDocuments(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let filename = "store_logo.png"
        let fileURL = documentsURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            return nil
        }
    }

    // MARK: - L-6: Branches Tab

    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    private var branchesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("store_branches_tab".t)
                    .font(.system(size: 12, weight: .bold)).foregroundColor(storeAccent).tracking(0.8)
                Spacer()
                Button(action: { showingAddBranch = true }) {
                    Label("add_branch_btn".t, systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(storeAccent).cornerRadius(10)
                        .shadow(color: storeAccent.opacity(0.28), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }

            let visibleBranches = branches.filter { !$0.isDeleted }
            if visibleBranches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.2").font(.system(size: 40)).foregroundColor(.textTertiary)
                    Text("store_no_branches_hint".t).font(.system(size: 12)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                if !visibleBranches.contains(where: { $0.id == UUID(uuidString: activeBranchId) }) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("store_no_active_branch_warning".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                }
                ForEach(visibleBranches) { branch in
                    branchRow(branch)
                }
            }
        }
    }

    private func branchRow(_ branch: Branch) -> some View {
        let isActive = UUID(uuidString: activeBranchId) == branch.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(branch.name).font(.system(size: 12, weight: .semibold)).foregroundColor(.textPrimary)
                    if isActive {
                        Text("store_active_badge".t)
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.appTeal).cornerRadius(6)
                    }
                }
                if let loc = branch.location, !loc.isEmpty {
                    Text(loc).font(.system(size: 12)).foregroundColor(.textSecondary)
                }
                if let phone = branch.phone, !phone.isEmpty {
                    Text(phone).font(.system(size: 12)).foregroundColor(.textTertiary)
                }
            }
            Spacer()
            // Set active
            if !isActive {
                Button(action: { BranchContext.shared.select(branch); APHaptic.trigger() }) {
                    Text("branch_select_store_btn".t)
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.appTeal).cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            // Edit
            Button(action: { branchToEdit = branch }) {
                Image(systemName: "pencil.circle").font(.system(size: 18)).foregroundColor(storeAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isActive ? Color.appTeal.opacity(0.06) : Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            isActive ? Color.appTeal.opacity(0.4) : Color.appBorderSubtle, lineWidth: 1))
    }

    private var branchSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("store_branch_summary_title".t)
                .font(.system(size: 12, weight: .bold)).foregroundColor(storeAccent).tracking(0.8)
            let activeBranches = branches.filter { !$0.isDeleted }
            Text("\(activeBranches.count) " + "store_branch_count_unit".t)
                .font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
            if let active = activeBranches.first(where: { $0.id == UUID(uuidString: activeBranchId) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("store_active_badge".t + ": " + active.name,
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.appTeal)
                    if let loc = active.location { Text(loc).font(.system(size: 12)).foregroundColor(.textSecondary) }
                    if let ph = active.phone  { Text(ph).font(.system(size: 12)).foregroundColor(.textTertiary) }
                }
                .padding(12).background(Color.appTeal.opacity(0.06)).cornerRadius(10)
            } else if !activeBranches.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("store_no_active_branch_warning".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08)).cornerRadius(10)
            }
            Spacer()
        }
        .padding(14).background(Color.appSurface).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func loadSavedLogo() {
        if !storeLogoPath.isEmpty {
            let fm = FileManager.default
            if let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsURL.appendingPathComponent(storeLogoPath)
                if let data = try? Data(contentsOf: fileURL) {
                    self.logoImage = UIImage(data: data)
                }
            }
        }
    }

    // MARK: - QR Code Customizer Form
    private var qrCustomizerForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.Store.qrBrandingHeader.t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(storeAccent)
                .tracking(1.0)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.qrStoreNameLbl.t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField(L.Store.nameLabel.t, text: $qrCustomStoreName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.qrHeaderLbl.t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField(L.Store.qrHeaderLbl.t, text: $qrCustomHeader)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                }

                Toggle(L.Store.qrShowLogoToggle.t, isOn: $qrCustomShowLogo)
                    .tint(storeAccent)
                    .font(.system(size: 12))
                    .fontWeight(.medium)

                if qrCustomShowLogo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.Store.qrLogoPresetLbl.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        Picker(L.Store.qrLogoPresetLbl.t, selection: $qrCustomLogoPreset) {
                            Text(L.Store.presetBolt.t).tag("bolt.fill")
                            Text(L.Store.presetForkKnife.t).tag("fork.knife")
                            Text(L.Store.presetStar.t).tag("star.fill")
                            Text(L.Store.presetHeart.t).tag("heart.fill")
                            Text(L.Store.presetCoffee.t).tag("cup.and.saucer.fill")
                            Text(L.Store.presetBeer.t).tag("mug.fill")
                        }
                        .pickerStyle(.menu)
                        .padding(4)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.qrThemeColorLbl.t)
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 12) {
                        ForEach([
                            ("#111115", "Space"),
                            ("#2D71F8", "Royal Blue"),
                            ("#1C8370", "Forest Green"),
                            ("#F59E0B", "Amber"),
                            ("#FC444A", "Rose")
                        ], id: \.0) { hex, name in
                            Button(action: {
                                qrCustomColor = hex
                                APHaptic.trigger()
                            }) {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: qrCustomColor == hex ? 3 : 0)
                                    )
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .apCard()
        }
    }

    // MARK: - QR Preview Panel
    private var qrCardPreviewPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 12))
                    .foregroundColor(storeAccent)
                Text(L.Store.liveQRPreview.t)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(storeAccent)
                    .tracking(1.0)
                Spacer()
            }

            VStack(spacing: 12) {
                Text(qrCustomStoreName)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .padding(.top, 4)

                Text(LocalizationManager.shared.t("pos_table_number") + " 15")
                    .font(.system(size: 12, weight: .bold))
                    .fontWeight(.black)
                    .foregroundColor(Color(hex: qrCustomColor))

                if let qrImg = qrPreviewImage {
                    Image(uiImage: qrImg)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 160, height: 160)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.08), radius: 3)
                } else {
                    ProgressView()
                        .frame(width: 176, height: 176)
                }

                Text(qrCustomHeader)
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(APRadius.md)
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 8)
            .frame(width: 300)
        }
        .padding()
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var qrPreviewImage: UIImage? {
        let string = "https://sync.alphaposweb.com/?table=15&merchant=Preview"
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let tintColor = UIColor(hex: qrCustomColor)

        guard let colorFilter = CIFilter(name: "CIFalseColor") else { return nil }
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(CIColor(color: tintColor), forKey: "inputColor0")
        colorFilter.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor1")

        guard let output = colorFilter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledOutput = output.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledOutput, from: scaledOutput.extent) else { return nil }

        let tintedImage = UIImage(cgImage: cgImage)

        // Logo
        if qrCustomShowLogo {
            return tintedImage.overlayLogo(systemIconName: qrCustomLogoPreset, tintColor: tintColor)
        }
        return tintedImage
    }
}

// MARK: - L-6: Branch Edit Sheet

struct BranchEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let branch: Branch?          // nil = create new
    let onSave: (String, String, String, Int, String) -> Void

    @State private var name: String
    @State private var location: String
    @State private var phone: String
    @State private var cutoffHour: Int
    @State private var timeZoneID: String

    init(branch: Branch?, onSave: @escaping (String, String, String, Int, String) -> Void) {
        self.branch = branch
        self.onSave = onSave
        _name     = State(initialValue: branch?.name ?? "")
        _location = State(initialValue: branch?.location ?? "")
        _phone    = State(initialValue: branch?.phone ?? "")
        _cutoffHour = State(initialValue: branch?.businessDayCutoffHour ?? 4)
        _timeZoneID = State(initialValue: branch?.timeZoneID ?? "Asia/Bangkok")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("branch_name_label".t) {
                    TextField("branch_name_placeholder".t, text: $name)
                }
                Section("branch_address_label".t) {
                    TextField("branch_address_placeholder".t, text: $location)
                }
                Section("branch_phone_label".t) {
                    TextField("branch_phone_placeholder".t, text: $phone)
                        .keyboardType(.phonePad)
                }
                Section(lm.currentLanguage == .thai ? "วันทำการและกะ" : "Business day & shift") {
                    Picker(lm.currentLanguage == .thai ? "สิ้นสุดวันทำการ" : "End of business day", selection: $cutoffHour) {
                        ForEach(0..<8, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    Text(lm.currentLanguage == .thai
                         ? "รายการหลังเที่ยงคืนและก่อนเวลานี้จะรวมกับวันทำการก่อนหน้า"
                         : "Transactions after midnight and before this time belong to the preceding business date.")
                        .font(.caption).foregroundColor(.secondary)
                    Picker(lm.currentLanguage == .thai ? "เขตเวลา" : "Time zone", selection: $timeZoneID) {
                        Text("Asia/Bangkok (ICT)").tag("Asia/Bangkok")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(branch == nil ? "add_branch_btn".t : "store_edit_branch_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn_label".t) {
                        onSave(name, location, phone, cutoffHour, timeZoneID)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(name.isEmpty ? .textTertiary : Color(hex: "0F766E"))
                    .disabled(name.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
