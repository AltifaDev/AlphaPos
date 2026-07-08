import SwiftUI
import SwiftData
import PhotosUI

enum StockScanStep: Int, CaseIterable {
    case upload = 0
    case review = 1
    case complete = 2

    var stepTitle: String {
        switch self {
        case .upload: return "menu_import_step_upload".t
        case .review: return "menu_import_step_review".t
        case .complete: return "menu_import_step_complete".t
        }
    }
}

struct ParsedReceiptItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unit: String?
    var unitCost: Double
    var isSelected: Bool = true
    var matchedItemId: UUID? // ID of matched InventoryItem
    var expiryDate: Date?
    var lotNumber: String?
}

struct ReceiptExtractedItem: Codable {
    let name: String
    let quantity: Double
    let unit: String?
    let unit_cost: Double
    let expiry_date: String? // YYYY-MM-DD
    let lot_number: String?
}

struct ReceiptParseResult: Codable {
    let po_number: String?
    let supplier_name: String?
    let invoice_date: String? // YYYY-MM-DD
    let items: [ReceiptExtractedItem]
    let total_items_found: Int
    let confidence: Double
}

struct StockDocumentScanSheet: View {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    @Query(sort: \Branch.name) private var branches: [Branch]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("gemini_api_key") private var geminiApiKey = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false

    @State private var viewModel = InventoryViewModel()
    @State private var currentStep: StockScanStep = .upload
    @State private var showApiSettings = false

    // Step 1: Upload
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [Data] = []
    @State private var selectedImagePreviews: [UIImage] = []
    @State private var isAnalyzing = false
    @State private var analyzeError: String? = nil

    // Step 2: Review (Invoice Metadata & Item lists)
    @State private var scannedInvoiceNumber = ""
    @State private var selectedSupplierId: UUID? = nil
    @State private var scannedInvoiceDate = Date()

    @State private var parsedItems: [ParsedReceiptItem] = []
    @State private var parseConfidence: Double = 0.0
    @State private var isImporting = false

    // Step 3: Complete
    @State private var importedCount = 0

    private var activeBranch: Branch? {
        branches.first(where: { $0.id.uuidString == activeBranchId })
    }

    private var branchInventory: [InventoryItem] {
        let activeItems = inventoryItems.filter { !$0.isDeleted }
        if let branch = activeBranch {
            return activeItems.filter { $0.branch?.id == branch.id }
        }
        return activeItems
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Step Indicator
                    stepIndicator
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.sm)
                        .background(Color.appSurface)

                    Divider().background(Color.appDivider)

                    // Content Wizard
                    Group {
                        switch currentStep {
                        case .upload:
                            uploadStepContent
                        case .review:
                            reviewStepContent
                        case .complete:
                            completeStepContent
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .navigationTitle("stock_scan_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep == .upload || currentStep == .complete {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
            .onAppear {
                viewModel.modelContext = modelContext
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadSelectedPhotos(from: newItems) }
            }
        }
        .apColorScheme()
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(StockScanStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 28, height: 28)

                        if currentStep.rawValue > step.rawValue {
                            Image(systemName: "checkmark")
                                .font(.footnote).fontWeight(.bold)
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.footnote).fontWeight(.bold)
                                .foregroundColor(currentStep == step ? .white : .textSecondary)
                        }
                    }

                    Text(step.stepTitle)
                        .font(.footnote)
                        .fontWeight(currentStep == step ? .bold : .regular)
                        .foregroundColor(currentStep == step ? .textPrimary : .textSecondary)

                    if step != .complete {
                        Spacer()
                        Rectangle()
                            .fill(currentStep.rawValue > step.rawValue ? Color.appTeal : Color.appDivider)
                            .frame(height: 2)
                        Spacer()
                    }
                }
            }
        }
    }

    private func stepColor(for step: StockScanStep) -> Color {
        if currentStep == step {
            return Color.appAccent
        } else if currentStep.rawValue > step.rawValue {
            return Color.appTeal
        } else {
            return Color.appSurfaceHigh
        }
    }

    // MARK: - Step 1: Upload Content
    private var uploadStepContent: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer().frame(height: 20)

            if offlineSyncMode {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)
                        .padding(APSpacing.lg)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Circle())

                    Text("ระบบกำลังทำงานในโหมดออฟไลน์")
                        .font(.headline)
                        .foregroundColor(.textPrimary)

                    Text("ฟังก์ชันประมวลผลด้วยปัญญาประดิษฐ์ (AI) จะถูกปิดใช้งานชั่วคราวจนกว่าจะปิดโหมดออฟไลน์และเชื่อมต่ออินเทอร์เน็ตได้")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.appSurface)
                .cornerRadius(APRadius.lg)
                .padding(.horizontal, APSpacing.md)
            } else {
                // Photo Picker Dropzone
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 1,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 64))
                            .foregroundColor(.textSecondary.opacity(0.6))
                            .padding(APSpacing.lg)
                            .background(Color.appSurfaceHigh)
                            .clipShape(Circle())

                        Text("stock_scan_select_photo".t)
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        Text("Upload delivery receipt, supplier invoice, or purchase order to automatically increment stock levels.")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .stroke(Color.appDivider, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, APSpacing.md)
            }

            // Image Preview List
            if !selectedImagePreviews.isEmpty && !offlineSyncMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: APSpacing.sm) {
                        ForEach(0..<selectedImagePreviews.count, id: \.self) { idx in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImagePreviews[idx])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))

                                Button(action: { removeImage(at: idx) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.appRose)
                                        .font(.title3)
                                        .background(Color.appSurface.clipShape(Circle()))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                }
                .frame(height: 110)
            }

            Spacer()

            // Bottom Action Bar
            VStack(spacing: APSpacing.sm) {
                // API Key Settings Toggle
                if !offlineSyncMode {
                    Button(action: {
                        withAnimation { showApiSettings.toggle() }
                    }) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text(geminiApiKey.isEmpty ? "Configure Gemini API Key" : "Gemini API Configured")
                                .underline()
                        }
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)

                    if showApiSettings {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Enter Gemini API Key", text: $geminiApiKey)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                            Text("Required if Supabase secrets are not configured.")
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                        }
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                        .padding(.horizontal, APSpacing.md)
                    }
                }

                Button(action: analyzeReceiptImages) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                            Text("stock_scan_analyzing".t)
                        } else {
                            Image(systemName: "sparkles")
                            Text("stock_scan_analyze_btn".t)
                        }
                    }
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if selectedImages.isEmpty || isAnalyzing || offlineSyncMode {
                                Color.appSurfaceHigh
                            } else {
                                APGradient.accent
                            }
                        }
                    )
                    .cornerRadius(APRadius.md)
                }
                .disabled(selectedImages.isEmpty || isAnalyzing || offlineSyncMode)
                .buttonStyle(.plain)
                .padding(.horizontal, APSpacing.md)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 2: Review Content
    private var reviewStepContent: some View {
        VStack(spacing: 0) {
            // Confidence Badge & Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.appAccent)
                Text(String(format: "menu_import_confidence".t, Int(parseConfidence * 100)))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.textSecondary)

                Spacer()

                Text(String(format: "menu_import_found_items".t, parsedItems.count))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 10)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            // Invoice Level Fields
            VStack(spacing: APSpacing.md) {
                HStack(spacing: APSpacing.md) {
                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                        Text("Invoice / PO Number")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        TextField("e.g. INV-10293", text: $scannedInvoiceNumber)
                            .padding(APSpacing.sm)
                            .background(Color.appBackground)
                            .cornerRadius(APRadius.sm)
                    }

                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                        Text("Supplier")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        Picker("Select Supplier", selection: $selectedSupplierId) {
                            Text("No Supplier").tag(nil as UUID?)
                            ForEach(suppliers) { sup in
                                Text(sup.name).tag(sup.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(Color.appBackground)
                        .cornerRadius(APRadius.sm)
                    }
                }

                HStack {
                    Text("Invoice Date")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    DatePicker("", selection: $scannedInvoiceDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .padding(APSpacing.md)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)

            Divider().background(Color.appDivider)

            // Editable List of parsed items mapped to Local Inventory
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(parsedItems.indices, id: \.self) { idx in
                        VStack(spacing: APSpacing.sm) {
                            HStack(alignment: .top, spacing: APSpacing.sm) {
                                // Toggle Select
                                Toggle(isOn: $parsedItems[idx].isSelected) {
                                    EmptyView()
                                }
                                .toggleStyle(CheckboxToggleStyle())
                                .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    // Found Item Text
                                    Text("Scanned: " + parsedItems[idx].name)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(.textPrimary)

                                    // Local Stock Item Matching Picker
                                    HStack {
                                        Text("Match:")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)

                                        Picker("Match Item", selection: $parsedItems[idx].matchedItemId) {
                                            Text("stock_scan_no_match".t).tag(nil as UUID?)
                                            ForEach(branchInventory) { item in
                                                Text(item.name).tag(item.id as UUID?)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()

                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)

                                    // Lot & Expiry Batch Fields
                                    HStack(spacing: APSpacing.md) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Lot #")
                                                .font(.system(size: 10)).fontWeight(.medium)
                                                .foregroundColor(.textSecondary)
                                            TextField("None", text: Binding(
                                                get: { parsedItems[idx].lotNumber ?? "" },
                                                set: { parsedItems[idx].lotNumber = $0.isEmpty ? nil : $0 }
                                            ))
                                            .font(.footnote)
                                            .textFieldStyle(.plain)
                                            .padding(4)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Expiry Date")
                                                .font(.system(size: 10)).fontWeight(.medium)
                                                .foregroundColor(.textSecondary)
                                            DatePicker("", selection: Binding(
                                                get: { parsedItems[idx].expiryDate ?? Date() },
                                                set: { parsedItems[idx].expiryDate = $0 }
                                            ), displayedComponents: .date)
                                            .labelsHidden()
                                            .scaleEffect(0.85)
                                            .frame(height: 24)
                                        }
                                    }
                                    .padding(.top, 4)
                                }

                                Spacer()

                                // Quantities & Cost entries
                                VStack(spacing: APSpacing.xs) {
                                    HStack {
                                        Text("Qty:")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                        TextField("0.0", value: $parsedItems[idx].quantity, formatter: NumberFormatter.doubleFormatter)
                                            .font(.system(.footnote, design: .rounded)).fontWeight(.bold)
                                            .textFieldStyle(.plain)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                        Text(parsedItems[idx].unit ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }

                                    HStack {
                                        Text("Cost:")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                        TextField("0.00", value: $parsedItems[idx].unitCost, formatter: NumberFormatter.currencyFormatter)
                                            .font(.system(.footnote, design: .rounded)).fontWeight(.bold)
                                            .textFieldStyle(.plain)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                    }
                                }
                            }
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .overlay(
                            Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom
                        )
                    }
                }
            }

            Divider().background(Color.appDivider)

            // Bottom Action Bar
            HStack(spacing: APSpacing.md) {
                Button(action: {
                    withAnimation { currentStep = .upload }
                }) {
                    Text("menu_import_retry".t)
                        .font(.headline)
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                }
                .buttonStyle(.plain)
                .frame(width: 140)

                Button(action: confirmAndImportStock) {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                        }
                        Text("stock_scan_confirm_btn".t)
                    }
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        Group {
                            if isImporting {
                                Color.appSurfaceHigh
                            } else {
                                APGradient.positive
                            }
                        }
                    )
                    .cornerRadius(APRadius.md)
                }
                .disabled(isImporting || !parsedItems.contains(where: { $0.isSelected && $0.matchedItemId != nil }))
                .buttonStyle(.plain)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
        }
    }

    // MARK: - Step 3: Complete Content
    private var completeStepContent: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.appTeal)
                .padding()
                .background(Color.appTeal.opacity(0.12))
                .clipShape(Circle())

            Text("stock_scan_success_title".t)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)

            Text(String(format: "stock_scan_imported_count".t, importedCount))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: onDismiss) {
                Text("menu_import_done_btn".t)
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(APGradient.accent)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, 20)
        }
    }

    // MARK: - File Handling & Networking
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        guard let firstItem = items.first else { return }

        do {
            if let data = try await firstItem.loadTransferable(type: Data.self) {
                await MainActor.run {
                    selectedImages = [data]
                    if let uiImage = UIImage(data: data) {
                        selectedImagePreviews = [uiImage]
                    }
                    analyzeError = nil
                }
            }
        } catch {
            await MainActor.run {
                analyzeError = "Failed to load image: " + error.localizedDescription
            }
        }
    }

    private func removeImage(at index: Int) {
        selectedImages.remove(at: index)
        selectedImagePreviews.remove(at: index)
        selectedPhotoItems.removeAll()
    }

    private func analyzeReceiptImages() {
        guard !selectedImages.isEmpty else { return }
        isAnalyzing = true
        analyzeError = nil

        Task {
            do {
                let result = try await callParseReceiptEdgeFunction(images: selectedImages)

                await MainActor.run {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"

                    self.scannedInvoiceNumber = result.po_number ?? ""
                    if let dateStr = result.invoice_date, let date = dateFormatter.date(from: dateStr) {
                        self.scannedInvoiceDate = date
                    } else {
                        self.scannedInvoiceDate = Date()
                    }

                    if let supplierName = result.supplier_name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
                        let matchedSup = suppliers.first { sup in
                            let nameLower = sup.name.lowercased()
                            return nameLower.contains(supplierName) || supplierName.contains(nameLower)
                        }
                        self.selectedSupplierId = matchedSup?.id
                    } else {
                        self.selectedSupplierId = nil
                    }

                    parsedItems = result.items.map { item in
                        let matchedId = findBestMatch(for: item.name, in: branchInventory)
                        let parsedExpiry = item.expiry_date.flatMap { dateFormatter.date(from: $0) }
                        return ParsedReceiptItem(
                            name: item.name,
                            quantity: item.quantity,
                            unit: item.unit,
                            unitCost: item.unit_cost,
                            matchedItemId: matchedId,
                            expiryDate: parsedExpiry,
                            lotNumber: item.lot_number
                        )
                    }

                    parseConfidence = result.confidence
                    isAnalyzing = false

                    if parsedItems.isEmpty {
                        analyzeError = "No receipt items parsed. Ensure receipt is clear."
                    } else {
                        withAnimation(.spring(response: 0.35)) {
                            currentStep = .review
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    analyzeError = "Error parsing receipt: " + error.localizedDescription
                }
            }
        }
    }

    private func callParseReceiptEdgeFunction(images: [Data]) async throws -> ReceiptParseResult {
        let config = AppConfig.shared
        let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/parse-stock-receipt")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        if !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-gemini-api-key")
        }
        request.timeoutInterval = 60

        let base64Images = images.map { $0.base64EncodedString() }
        let payload: [String: Any] = ["images": base64Images]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MenuImportError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MenuImportError.serverError(httpResponse.statusCode, errorMsg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ReceiptParseResult.self, from: data)
    }

    @MainActor
    private func confirmAndImportStock() {
        isImporting = true

        let supplier = suppliers.first { $0.id == selectedSupplierId }
        let poNumber = scannedInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "INV-\(Int.random(in: 100000...999999))"
            : scannedInvoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        let newPO = PurchaseOrder(
            poNumber: poNumber,
            supplier: supplier,
            branch: activeBranch,
            status: "received",
            orderDate: scannedInvoiceDate,
            deliveryDate: Date(),
            notes: "AI Scanned Invoice"
        )
        modelContext.insert(newPO)

        var importCount = 0
        for item in parsedItems {
            guard item.isSelected, let matchedId = item.matchedItemId else { continue }

            if let targetItem = branchInventory.first(where: { $0.id == matchedId }) {
                let poItem = PurchaseOrderItem(
                    purchaseOrder: newPO,
                    inventoryItem: targetItem,
                    quantityOrdered: item.quantity,
                    quantityReceived: item.quantity,
                    unitCost: item.unitCost
                )
                modelContext.insert(poItem)

                viewModel.processReceiveWithExpiry(
                    item: targetItem,
                    amountString: String(format: "%.4f", item.quantity),
                    costString: String(format: "%.2f", item.unitCost),
                    notes: "Received via Invoice #\(poNumber)",
                    expiryDate: item.expiryDate,
                    lotNumber: item.lotNumber
                )
                importCount += 1
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("StockDocumentScanSheet [Save PO Error]: \(error.localizedDescription)")
        }

        importedCount = importCount
        isImporting = false
        withAnimation(.spring(response: 0.35)) {
            currentStep = .complete
        }
    }

    // MARK: - Matching Logic
    private func findBestMatch(for name: String, in items: [InventoryItem]) -> UUID? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Exact Match
        if let exact = items.first(where: { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized }) {
            return exact.id
        }

        // 2. Substring Match
        if let sub = items.first(where: { normalized.contains($0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) || $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).contains(normalized) }) {
            return sub.id
        }

        return nil
    }
}

// MARK: - Formatters
extension NumberFormatter {
    static var doubleFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        return f
    }

    static var currencyFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }
}

// MARK: - Checkbox Style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .appTeal : .textSecondary)
                    .font(.title3)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
