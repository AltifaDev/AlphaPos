import SwiftUI
import PhotosUI
import CoreImage
import SwiftData

struct StoreManagementView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Store settings stored in UserDefaults
    @AppStorage("store_name") private var storeName = "AlphaPos Restaurant"
    @AppStorage("store_phone") private var storePhone = "02-123-4567"
    @AppStorage("store_website") private var storeWebsite = "www.alphapos.restaurant"
    @AppStorage("store_address") private var storeAddress = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id") private var storeTaxId = "1234567890123"
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_tax_rate") private var storeTaxRate = 7.0
    @AppStorage("store_tax_type") private var storeTaxType = "inclusive" // "inclusive", "exclusive"
    @AppStorage("store_service_charge_rate") private var storeServiceChargeRate = 10.0
    @AppStorage("enable_tax") private var enableTax = true
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
    
    @State private var activeTab: ConfigTab = .profile
    @EnvironmentObject private var lm: LocalizationManager
    
    enum ConfigTab: String, CaseIterable {
        case profile = "General Profile"
        case taxation = "Tax & Service Charge"
        case qrCustomizer = "QR Code Customizer"
        var icon: String {
            switch self {
            case .profile: return "storefront.fill"
            case .taxation: return "percent"
            case .qrCustomizer: return "qrcode"
            }
        }
        var localizedName: String {
            switch self {
            case .profile: return L.Store.tabProfile.t
            case .taxation: return L.Store.tabTax.t
            case .qrCustomizer: return L.Store.tabQR.t
            }
        }
    }
    
    var body: some View {
        ZStack {
                Color.appBackground.ignoresSafeArea()
                
                HStack(spacing: 24) {
                    // LEFT COLUMN: Forms / Configuration
                    VStack(alignment: .leading, spacing: 20) {
                        // Segment selector for tabs
                        HStack(spacing: 12) {
                            ForEach(ConfigTab.allCases, id: \.self) { tab in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        activeTab = tab
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: tab.icon)
                                        Text(tab.localizedName)
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(activeTab == tab ? Color.appAccent : Color.appSurfaceHigh)
                                    .foregroundColor(activeTab == tab ? .white : .textSecondary)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(activeTab == tab ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if activeTab == .profile {
                                    generalProfileForm
                                } else if activeTab == .taxation {
                                    taxationForm
                                } else {
                                    qrCustomizerForm
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // RIGHT COLUMN: Live Preview Panel (Receipt or QR Card)
                    if activeTab == .qrCustomizer {
                        qrCardPreviewPanel
                    } else {
                        receiptPreviewPanel
                    }
                }
                .padding()
            }
            .navigationTitle(L.Store.title.t)
            .apNavBar(background: Color.appBackground)
            .onAppear {
                loadSavedLogo()
            }
    }
    
    // MARK: - General Profile Form
    private var generalProfileForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.Store.brandingHeader.t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
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
                                .font(.title)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoItem, matching: .images, photoLibrary: .shared()) {
                            Label(L.Store.selectLogo.t, systemImage: "photo.badge.plus")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(APGradient.accent)
                                .cornerRadius(APRadius.md)
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
                                    .font(.caption)
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
                
                // Fields
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.nameLabel.t)
                        .font(.caption)
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
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("Phone Number", text: $storePhone)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .onChange(of: storePhone) { triggerSync() }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.Store.websiteLabel.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("e.g. www.cafe.com", text: $storeWebsite)
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
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("Address Details", text: $storeAddress)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeAddress) { triggerSync() }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("promptpay_number_label".t)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("e.g. 0812345678 or 13-digit Tax ID", text: $promptPayNumber)
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
    
    // MARK: - Taxation Form
    private var taxationForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("taxation_receipts_settings".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            // ── Advanced Tax Info Banner ─────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(hex: "6366F1"))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Basic settings only — linked to Tax & Fees")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)

                    Text("VAT rate, service charge, and tax mode are shared with **Tax & Fees**. Changes here update immediately.\n\nAdvanced settings — tax profile, price basis, rounding, channel rules, and item exemptions — are managed in **Settings → Tax & Fees**.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Color(hex: "10B981"))
                        Text("VAT Rate · Service Charge · Tax Mode")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(Color(hex: "10B981"))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundColor(Color(hex: "6366F1"))
                        Text("Tax Profile · Price Basis · Rounding · Channel Rules → Tax & Fees")
                            .font(.caption2)
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
                            .font(.caption)
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
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("e.g. 00000", text: $storeBranchCode)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.md)
                            .onChange(of: storeBranchCode) { triggerSync() }
                    }
                }
                
                Toggle("เปิดใช้งานภาษีมูลค่าเพิ่ม (VAT)", isOn: $enableTax)
                    .tint(.appAccent)
                    .onChange(of: enableTax) { triggerSync() }
                
                Toggle("เปิดใช้งานเซอร์วิสชาร์จ (Service Charge)", isOn: $enableServiceCharge)
                    .tint(.appAccent)
                    .onChange(of: enableServiceCharge) { triggerSync() }
                
                Divider()
                    .background(Color.appDivider)

                if enableTax {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("tax_calculation_mode".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        Picker("Tax Calculation Mode", selection: $storeTaxType) {
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
                                    .font(.caption)
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
                                    .font(.caption)
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
                    Text("receipt_header_message".t)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("Welcome message", text: $storeReceiptHeader)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeReceiptHeader) { triggerSync() }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("receipt_footer_message".t)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("Thank you message", text: $storeReceiptFooter)
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
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                    Text("These are default messages. Individual Receipt Templates (Settings → Receipt Templates) override these values per template.")
                        .font(.caption2)
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
            showOrderType:     true
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
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Store.qrStoreNameLbl.t)
                        .font(.caption)
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
                        .font(.caption)
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
                    .tint(.appAccent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if qrCustomShowLogo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.Store.qrLogoPresetLbl.t)
                            .font(.caption)
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
                        .font(.caption)
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
            Text(L.Store.liveQRPreview.t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
            
            VStack(spacing: 12) {
                Text(qrCustomStoreName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .padding(.top, 4)
                
                Text(LocalizationManager.shared.t("pos_table_number") + " 15")
                    .font(.title2)
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
                    .font(.caption)
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
        let string = "https://alphapos.altifadev.workers.dev/?table=15&merchant=Preview"
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
