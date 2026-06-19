// MenuImportSheet.swift
// AlphaPos — AI-Powered Menu Image Import (3-Step Flow)

import SwiftUI
import SwiftData
import PhotosUI

struct MenuImportSheet: View {
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \MenuItem.name) private var existingProducts: [MenuItem]
    
    @State private var viewModel = InventoryViewModel()
    @State private var currentStep: MenuImportStep = .upload
    
    @AppStorage("gemini_api_key") private var geminiApiKey = ""
    @State private var showApiSettings = false
    
    // Step 1: Upload
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [Data] = []
    @State private var selectedImagePreviews: [UIImage] = []
    @State private var isAnalyzing = false
    @State private var analyzeError: String? = nil
    
    // Step 2: Review
    @State private var parsedItems: [ParsedMenuItem] = []
    @State private var parseConfidence: Double = 0.0
    @State private var isImporting = false
    
    // Step 3: Complete
    @State private var importSummary = MenuImportSummary()
    
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
                    
                    // Content
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
            .navigationTitle("menu_import_title".t)
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
            ForEach(MenuImportStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 28, height: 28)
                        
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(step == currentStep ? .white : .textTertiary)
                        }
                    }
                    
                    Text(step.title)
                        .font(.caption2)
                        .fontWeight(step == currentStep ? .bold : .regular)
                        .foregroundColor(step == currentStep ? .textPrimary : .textTertiary)
                        .lineLimit(1)
                }
                
                if step.rawValue < MenuImportStep.allCases.count - 1 {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.appAccent : Color.appBorderSubtle)
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.vertical, APSpacing.xs)
    }
    
    private func stepColor(for step: MenuImportStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .appTeal
        } else if step == currentStep {
            return .appAccent
        } else {
            return .appSurfaceHigh
        }
    }
    
    // MARK: - Step 1: Upload
    
    private var uploadStepContent: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {
                // Info card
                VStack(spacing: APSpacing.sm) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.appAccent, .appTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("menu_import_upload_hint".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, APSpacing.lg)
                    
                    Text("menu_import_max_photos".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .padding(.top, APSpacing.xl)
                
                // Image previews
                if !selectedImagePreviews.isEmpty {
                    imagePreviewGrid
                }
                
                // API Key Settings (Collapsible)
                VStack(alignment: .leading, spacing: APSpacing.xs) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showApiSettings.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.appAccent)
                            Text("🔑 Gemini API Settings")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: showApiSettings ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.vertical, APSpacing.sm)
                    }
                    .buttonStyle(.plain)
                    
                    if showApiSettings {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            Text("หากไม่มี GEMINI_API_KEY ใน Supabase Secrets คุณสามารถใส่ API Key เพื่อใช้งานผ่านแอปได้โดยตรง")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            
                            HStack(spacing: APSpacing.sm) {
                                SecureField("AI Studio API Key", text: $geminiApiKey)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(APSpacing.sm)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .foregroundColor(.textPrimary)
                                
                                if !geminiApiKey.isEmpty {
                                    Button(action: { geminiApiKey = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            
                            Link(destination: URL(string: "https://aistudio.google.com/")!) {
                                HStack(spacing: 4) {
                                    Text("รับ API Key ฟรีที่ Google AI Studio")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(.appAccent)
                            }
                        }
                        .padding(.bottom, APSpacing.sm)
                    }
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.xs)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, APSpacing.md)
                
                // Action buttons
                VStack(spacing: APSpacing.sm) {
                    // Photo Library
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("menu_import_add_photos".t, systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(APGradient.accent)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, APSpacing.md)
                
                // Error message
                if let error = analyzeError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.appRose)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.appRose)
                    }
                    .padding(APSpacing.sm)
                    .background(Color.appRose.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    .padding(.horizontal, APSpacing.md)
                }
                
                // Analyze button
                if !selectedImages.isEmpty {
                    Button(action: analyzeMenuImages) {
                        HStack(spacing: 8) {
                            if isAnalyzing {
                                ProgressView()
                                    .tint(.white)
                                Text("menu_import_analyzing".t)
                            } else {
                                Image(systemName: "sparkles")
                                Text("menu_import_analyze_btn".t)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isAnalyzing
                            ? AnyShapeStyle(Color.appAccent.opacity(0.6))
                            : AnyShapeStyle(APGradient.accent)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnalyzing)
                    .padding(.horizontal, APSpacing.md)
                }
                
                Spacer(minLength: 40)
            }
        }
    }
    
    private var imagePreviewGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: APSpacing.sm) {
                ForEach(Array(selectedImagePreviews.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        
                        Button(action: {
                            removeImage(at: index)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, APSpacing.md)
        }
    }
    
    // MARK: - Step 2: Review
    
    private var reviewStepContent: some View {
        VStack(spacing: 0) {
            // Header with stats
            reviewHeader
            
            Divider().background(Color.appDivider)
            
            // Items list
            ScrollView {
                LazyVStack(spacing: APSpacing.xs) {
                    ForEach($parsedItems) { $item in
                        reviewItemRow(item: $item)
                    }
                }
                .padding(APSpacing.md)
            }
            
            Divider().background(Color.appDivider)
            
            // Import button
            importActionBar
        }
    }
    
    private var reviewHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.t("menu_import_found_items", parsedItems.count))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                Text(LocalizationManager.shared.t("menu_import_confidence", Int(parseConfidence * 100)))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
            
            Spacer()
            
            // Select all / deselect all
            Button(action: toggleSelectAll) {
                Text(allSelected ? "menu_import_deselect_all".t : "menu_import_select_all".t)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appAccent)
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appSurface)
    }
    
    private func reviewItemRow(item: Binding<ParsedMenuItem>) -> some View {
        HStack(spacing: APSpacing.sm) {
            // Checkbox
            Button(action: { item.wrappedValue.isSelected.toggle() }) {
                Image(systemName: item.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(item.wrappedValue.isSelected ? .appAccent : .textTertiary)
            }
            .buttonStyle(.plain)
            
            // Item info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.wrappedValue.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(item.wrappedValue.isDuplicate ? .textTertiary : .textPrimary)
                        .strikethrough(item.wrappedValue.isDuplicate)
                    
                    if item.wrappedValue.isDuplicate {
                        Text("menu_import_duplicate_badge".t)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appAmber.opacity(0.15))
                            .foregroundColor(.appAmber)
                            .clipShape(Capsule())
                    }
                    
                    if let cat = item.wrappedValue.suggestedCategory,
                       !categories.contains(where: { $0.name == cat }) {
                        Text("menu_import_new_category".t)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appTeal.opacity(0.15))
                            .foregroundColor(.appTeal)
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    if let cat = item.wrappedValue.suggestedCategory {
                        // Category picker
                        Menu {
                            Button("menu_import_no_category".t) {
                                item.wrappedValue.suggestedCategory = nil
                            }
                            ForEach(allCategoryOptions, id: \.self) { catName in
                                Button(catName) {
                                    item.wrappedValue.suggestedCategory = catName
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(cat)
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    } else {
                        Menu {
                            ForEach(allCategoryOptions, id: \.self) { catName in
                                Button(catName) {
                                    item.wrappedValue.suggestedCategory = catName
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("menu_import_no_category".t)
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Price (editable)
            HStack(spacing: 2) {
                Text("฿")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(String(format: "%.0f", item.wrappedValue.price))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(APSpacing.sm)
        .apCard()
        .opacity(item.wrappedValue.isSelected ? 1.0 : 0.5)
    }
    
    private var importActionBar: some View {
        VStack(spacing: APSpacing.sm) {
            Button(action: performImport) {
                HStack(spacing: 8) {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                        Text("menu_import_importing".t)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("menu_import_confirm_btn".t)
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    selectedCount > 0 && !isImporting
                    ? AnyShapeStyle(APGradient.accent)
                    : AnyShapeStyle(Color.appSurfaceHigh)
                )
                .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0 || isImporting)
            
            // Back button
            if !isImporting {
                Button(action: {
                    withAnimation(.spring(response: 0.35)) {
                        currentStep = .upload
                    }
                }) {
                    Text("← " + "menu_import_step_upload".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }
    
    // MARK: - Step 3: Complete
    
    private var completeStepContent: some View {
        VStack(spacing: APSpacing.xl) {
            Spacer()
            
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.appTeal, .appAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("menu_import_success_title".t)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            // Summary stats
            VStack(spacing: APSpacing.sm) {
                summaryRow(
                    icon: "checkmark.circle.fill",
                    color: .appTeal,
                    text: LocalizationManager.shared.t("menu_import_imported_count", importSummary.imported)
                )
                
                if importSummary.skipped > 0 {
                    summaryRow(
                        icon: "arrow.right.circle.fill",
                        color: .appAmber,
                        text: LocalizationManager.shared.t("menu_import_skipped_count", importSummary.skipped)
                    )
                }
                
                if importSummary.duplicatesSkipped > 0 {
                    summaryRow(
                        icon: "doc.on.doc.fill",
                        color: .textTertiary,
                        text: LocalizationManager.shared.t("menu_import_skipped_count", importSummary.duplicatesSkipped) + " (" + "menu_import_duplicate_badge".t + ")"
                    )
                }
                
                if importSummary.categoriesCreated > 0 {
                    summaryRow(
                        icon: "folder.badge.plus",
                        color: .appAccent,
                        text: LocalizationManager.shared.t("menu_import_categories_created", importSummary.categoriesCreated)
                    )
                }
            }
            .padding(.horizontal, APSpacing.xl)
            
            Spacer()
            
            // Done button
            Button(action: onDismiss) {
                Text("menu_import_done_btn".t)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(APGradient.accent)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.lg)
        }
    }
    
    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            Spacer()
        }
        .padding(APSpacing.sm)
        .apCard()
    }
    
    // MARK: - Computed Properties
    
    private var allSelected: Bool {
        parsedItems.allSatisfy { $0.isSelected }
    }
    
    private var selectedCount: Int {
        parsedItems.filter { $0.isSelected }.count
    }
    
    private var allCategoryOptions: [String] {
        var options = categories.map { $0.name }
        // Add AI-suggested categories that don't exist yet
        let suggestedNew = Set(parsedItems.compactMap { $0.suggestedCategory })
            .subtracting(Set(options))
        options.append(contentsOf: suggestedNew.sorted())
        return options
    }
    
    // MARK: - Actions
    
    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        var newImages: [Data] = []
        var newPreviews: [UIImage] = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                // Compress for API sending (keep reasonable size)
                if let compressed = compressForAPI(uiImage) {
                    newImages.append(compressed)
                    newPreviews.append(uiImage)
                }
            }
        }
        
        await MainActor.run {
            selectedImages = newImages
            selectedImagePreviews = newPreviews
            analyzeError = nil
        }
    }
    
    private func compressForAPI(_ image: UIImage) -> Data? {
        // Resize to max 2048px longest side for API efficiency
        let maxDimension: CGFloat = 2048
        let size = image.size
        let scale: CGFloat
        if max(size.width, size.height) > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resized.jpegData(compressionQuality: 0.85)
    }
    
    private func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        selectedImagePreviews.remove(at: index)
        // Also update PhotosPicker selection
        if index < selectedPhotoItems.count {
            selectedPhotoItems.remove(at: index)
        }
    }
    
    private func analyzeMenuImages() {
        guard !selectedImages.isEmpty else { return }
        isAnalyzing = true
        analyzeError = nil
        
        Task {
            do {
                let result = try await callParseMenuEdgeFunction(images: selectedImages)
                
                await MainActor.run {
                    // Mark duplicates
                    let existingNames = Set(existingProducts.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
                    
                    parsedItems = result.items.map { item in
                        var mutable = item
                        let normalizedName = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if existingNames.contains(normalizedName) {
                            mutable.isDuplicate = true
                            mutable.isSelected = false // Auto-deselect duplicates
                        }
                        return mutable
                    }
                    
                    parseConfidence = result.confidence
                    isAnalyzing = false
                    
                    if parsedItems.isEmpty {
                        analyzeError = "menu_import_no_items".t
                    } else {
                        withAnimation(.spring(response: 0.35)) {
                            currentStep = .review
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    analyzeError = "menu_import_error".t + ": " + error.localizedDescription
                }
            }
        }
    }
    
    private func toggleSelectAll() {
        let newValue = !allSelected
        for i in parsedItems.indices {
            parsedItems[i].isSelected = newValue
        }
    }
    
    private func performImport() {
        isImporting = true
        
        Task {
            let selectedItems = parsedItems.filter { $0.isSelected }
            var summary = MenuImportSummary()
            summary.totalFound = parsedItems.count
            
            // Map existing categories (lowercase name -> actual category name and ID)
            var categoryMap: [String: UUID] = [:]
            var existingCategoriesLower: [String: Category] = [:]
            for cat in categories {
                let normalized = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                existingCategoriesLower[normalized] = cat
                categoryMap[cat.name] = cat.id
            }
            
            // Resolve categories: case-insensitively map or prepare to create new ones
            var newCategoriesToSave: [Category] = []
            
            for item in selectedItems {
                if let suggestedCat = item.suggestedCategory {
                    let trimmed = suggestedCat.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let lower = trimmed.lowercased()
                        if let existingCat = existingCategoriesLower[lower] {
                            // Use existing category
                            categoryMap[trimmed] = existingCat.id
                        } else {
                            // Category doesn't exist yet, create it
                            if categoryMap[trimmed] == nil {
                                let newCat = Category(name: trimmed)
                                modelContext.insert(newCat)
                                categoryMap[trimmed] = newCat.id
                                existingCategoriesLower[lower] = newCat
                                newCategoriesToSave.append(newCat)
                                summary.categoriesCreated += 1
                            }
                        }
                    }
                }
            }
            
            if !newCategoriesToSave.isEmpty {
                try? modelContext.save()
            }
            
            // 2. Create products
            for item in selectedItems {
                let categoryId = item.suggestedCategory.flatMap { categoryMap[$0.trimmingCharacters(in: .whitespacesAndNewlines)] }
                
                viewModel.addProduct(
                    name: item.name,
                    price: item.price,
                    description: item.description,
                    categoryId: categoryId,
                    isAvailable: true
                )
                
                summary.imported += 1
            }
            
            // Count skipped
            summary.skipped = parsedItems.filter { !$0.isSelected && !$0.isDuplicate }.count
            summary.duplicatesSkipped = parsedItems.filter { $0.isDuplicate }.count
            
            await MainActor.run {
                importSummary = summary
                isImporting = false
                
                withAnimation(.spring(response: 0.35)) {
                    currentStep = .complete
                }
            }
        }
    }
    
    // MARK: - Edge Function Call
    
    private func callParseMenuEdgeFunction(images: [Data]) async throws -> MenuParseResult {
        let config = AppConfig.shared
        let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/parse-menu-image")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        if !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-gemini-api-key")
        }
        request.timeoutInterval = 60
        
        // Convert image data to base64 strings
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
        return try decoder.decode(MenuParseResult.self, from: data)
    }
}

// MARK: - Error Types

enum MenuImportError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)
    case noItems
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .noItems:
            return "No menu items found in the image"
        }
    }
}
