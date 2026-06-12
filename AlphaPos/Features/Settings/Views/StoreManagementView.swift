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
    @AppStorage("store_receipt_header") private var storeReceiptHeader = "Welcome to AlphaPos!"
    @AppStorage("store_receipt_footer") private var storeReceiptFooter = "Thank you for dining with us!\nVAT Included."
    @AppStorage("store_logo_path") private var storeLogoPath = ""
    @AppStorage("promptpay_number") private var promptPayNumber = ""
    
    @State private var logoItem: PhotosPickerItem? = nil
    @State private var logoImage: UIImage? = nil
    
    @State private var activeTab: ConfigTab = .profile
    
    enum ConfigTab: String, CaseIterable {
        case profile = "General Profile"
        case taxation = "Tax & Service Charge"
        var icon: String {
            switch self {
            case .profile: return "storefront.fill"
            case .taxation: return "percent"
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
                                        Text(tab.rawValue)
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
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if activeTab == .profile {
                                    generalProfileForm
                                } else {
                                    taxationForm
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // RIGHT COLUMN: Live Receipt Preview (Monospaced, clean paper receipt style)
                    receiptPreviewPanel
                }
                .padding()
            }
            .navigationTitle("Store Management")
            .apNavBar(background: Color.appBackground)
            .onAppear {
                loadSavedLogo()
            }
    }
    
    // MARK: - General Profile Form
    private var generalProfileForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("STORE BRANDING & INFORMATION")
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
                            Label("Select Logo", systemImage: "photo.badge.plus")
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
                                Text("Remove Logo")
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
                    Text("Store Name")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    TextField("Enter Store Name", text: $storeName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(APRadius.md)
                        .onChange(of: storeName) { triggerSync() }
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Store Phone")
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
                        Text("Website")
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
                    Text("Store Address")
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
                    Text("PromptPay Number (for QR Code Payment)")
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
            Text("TAXATION & RECEIPTS SETTINGS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tax ID / VAT Registration")
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
                        Text("Branch Code")
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax Calculation Mode")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    Picker("Tax Calculation Mode", selection: $storeTaxType) {
                        Text("Tax-Inclusive (VAT In)").tag("inclusive")
                        Text("Tax-Exclusive (VAT Add)").tag("exclusive")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: storeTaxType) { triggerSync() }
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Default Tax Rate (%)")
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
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Service Charge (%)")
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
                
                Divider()
                    .background(Color.appDivider)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Receipt Header Message")
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
                    Text("Receipt Footer Message")
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
            }
            .apCard()
        }
    }
    
    // MARK: - Receipt Preview Panel
    private var receiptPreviewPanel: some View {
        VStack(spacing: 12) {
            Text("LIVE TAX INVOICE PREVIEW")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
            
            // Receipt Paper Container
            VStack(spacing: 8) {
                // Logo Placeholder/Render
                if let logo = logoImage {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "storefront.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                
                // Store Profile Headers
                Text(storeName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(storeAddress)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 2) {
                    Text("Phone: \(storePhone)")
                    Text("Web: \(storeWebsite)")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                
                Text("TAX INVOICE (ABB.) / ใบกำกับภาษีอย่างย่อ")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .padding(.vertical, 4)
                
                HStack {
                    Text("TAX ID: \(storeTaxId)")
                    Spacer()
                    Text("BRANCH: \(storeBranchCode)")
                }
                .font(.system(size: 9, design: .monospaced))
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Mock Order Items
                VStack(spacing: 4) {
                    HStack {
                        Text("1 x Classic Pad Thai")
                        Spacer()
                        Text("120.00")
                    }
                    HStack {
                        Text("1 x Traditional Thai Iced Tea")
                        Spacer()
                        Text("85.00")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Calculations based on Inclusive vs Exclusive
                let rawSubtotal = 205.0
                let serviceCharge = rawSubtotal * (storeServiceChargeRate / 100.0)
                let pricingBase = rawSubtotal + serviceCharge
                
                let taxAmount: Double = {
                    let isInclusive = storeTaxType == "inclusive"
                    if isInclusive {
                        return pricingBase * (storeTaxRate / (100.0 + storeTaxRate))
                    } else {
                        return pricingBase * (storeTaxRate / 100.0)
                    }
                }()
                
                let grandTotal: Double = {
                    let isInclusive = storeTaxType == "inclusive"
                    if isInclusive {
                        return pricingBase
                    } else {
                        return pricingBase + taxAmount
                    }
                }()
                
                VStack(spacing: 4) {
                    HStack {
                        Text("SUBTOTAL")
                        Spacer()
                        Text(String(format: "%.2f", rawSubtotal))
                    }
                    
                    if serviceCharge > 0 {
                        HStack {
                            Text(String(format: "SERVICE CHARGE (%.0f%%)", storeServiceChargeRate))
                            Spacer()
                            Text(String(format: "%.2f", serviceCharge))
                        }
                    }
                    
                    HStack {
                        Text(String(format: "VAT (%.1f%%) - %@", storeTaxRate, storeTaxType == "inclusive" ? "INCL" : "ADD"))
                        Spacer()
                        Text(String(format: "%.2f", taxAmount))
                    }
                    
                    HStack {
                        Text("TOTAL")
                            .fontWeight(.bold)
                        Spacer()
                        Text(String(format: "฿%.2f", grandTotal))
                            .fontWeight(.bold)
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Custom Messages
                Text(storeReceiptHeader)
                    .font(.system(size: 9, design: .monospaced))
                    .multilineTextAlignment(.center)
                
                Text(storeReceiptFooter)
                    .font(.system(size: 9, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                
                // Mock Barcode
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: CGFloat([1, 2, 3, 1].randomElement() ?? 1), height: 32)
                        }
                    }
                    Text("AP-STORE-TAX-\(storeBranchCode)")
                        .font(.system(size: 8, design: .monospaced))
                }
                .padding(.top, 12)
            }
            .padding(16)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(APRadius.sm)
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
}
