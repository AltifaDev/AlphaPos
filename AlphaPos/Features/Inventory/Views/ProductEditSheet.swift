// ProductEditSheet.swift
// AlphaPos — MenuItem, Recipe, and Modifiers Joint Editor Sheet

import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct ProductEditSheet: View {
    let menuItem: MenuItem? // Nil when creating new
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \ModifierGroup.name) private var allModifierGroups: [ModifierGroup]
    @Query(sort: \InventoryItem.name) private var allIngredients: [InventoryItem]

    @State private var viewModel = InventoryViewModel()
    @State private var activeTab = 0 // 0: Details, 1: Recipe, 2: Extras

    // Tab 1: General Details
    @State private var name = ""
    @State private var priceString = ""
    @State private var description = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var isAvailable = true
    @State private var showingDeleteAlert = false

    // Translations
    @State private var nameEn = ""
    @State private var nameZh = ""
    @State private var descEn = ""
    @State private var descZh = ""

    // New Standard POS States
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var imageDataItems: [Data] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var videoData: Data?
    @State private var isProcessingMedia = false
    @State private var mediaErrorMessage: String?
    @State private var barcode = ""
    @State private var sku = ""
    @State private var isFavorite = false
    @State private var isTaxInclusive = true
    @State private var taxRateString = "7.0"
    @State private var selectedColorHex: String? = nil

    private let colorOptions = [
        (name: "Default", hex: nil as String?, color: Color.appAccent),
        (name: "Rose", hex: "BE123C", color: Color(hex: "BE123C")),
        (name: "Lavender", hex: "701A75", color: Color(hex: "701A75")),
        (name: "Teal", hex: "0F766E", color: Color(hex: "0F766E")),
        (name: "Amber", hex: "B45309", color: Color(hex: "B45309")),
        (name: "Indigo", hex: "1D4ED8", color: Color(hex: "1D4ED8")),
        (name: "Slate", hex: "374151", color: Color(hex: "374151")),
        (name: "Emerald", hex: "047857", color: Color(hex: "047857"))
    ]

    // Tab 2: Recipe Config (Loaded from RecipeBuilderSheet implementation)
    @State private var trackingMode = "not_tracked"
    @State private var selectedIngredientId: UUID? = nil

    struct RecipeLineInput: Identifiable {
        let id = UUID()
        let ingredient: InventoryItem
        var qty: Double
        var qtyString: String
    }
    @State private var recipeLines: [RecipeLineInput] = []
    @State private var showingAddIngredient = false

    struct DeliveryPriceInput: Identifiable {
        let id: UUID
        var brandName: String
        var priceString: String
    }
    @State private var deliveryPriceInputs: [DeliveryPriceInput] = []

    // Tab 3: Modifier Groups linking
    @State private var linkedModifierGroupIds: Set<UUID> = []

    var isEditing: Bool { menuItem != nil }

    // Recipe costing calculations
    private var totalCost: Double {
        switch trackingMode {
        case "not_tracked":
            return 0.0
        case "finished_good":
            if let ingredientId = selectedIngredientId,
               let matched = allIngredients.first(where: { $0.id == ingredientId }) {
                return matched.costPrice
            }
            return 0.0
        case "recipe_based":
            return recipeLines.reduce(0.0) { sum, line in
                sum + (line.ingredient.costPrice * line.qty)
            }
        default:
            return 0.0
        }
    }

    private var menuPrice: Double {
        Double(priceString) ?? 0.0
    }

    private var foodCostPercent: Double {
        guard menuPrice > 0 else { return 0.0 }
        return (totalCost / menuPrice) * 100.0
    }

    private var grossMarginPercent: Double {
        return max(0.0, 100.0 - foodCostPercent)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header tabs (Visible only if editing)
                    if isEditing {
                        Picker("Editor Segment", selection: $activeTab) {
                            Text("product_tab_details".t).tag(0)
                            Text("product_tab_recipe".t).tag(1)
                            Text("product_tab_extras".t).tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.sm)
                        .background(Color.appSurface)

                        Divider().background(Color.appDivider)
                    }

                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            switch activeTab {
                            case 0:
                                detailsTabContent
                            case 1:
                                recipeTabContent
                            case 2:
                                extrasTabContent
                            default:
                                EmptyView()
                            }
                        }
                        .padding(APSpacing.md)
                    }

                    bottomActionPanel
                }
            }
            .navigationTitle(isEditing ? "Edit Product" : "Add New Product")
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .onAppear {
                viewModel.modelContext = modelContext
                loadProductData()
            }
            .sheet(isPresented: $showingAddIngredient) {
                ingredientSelectionSheet
            }
            .alert("Delete Product", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let item = menuItem {
                        viewModel.deleteProduct(menuItem: item)
                    }
                    onDismiss()
                }
            } message: {
                Text("delete_product_confirm_msg".t)
            }
            .alert("ไม่สามารถเพิ่มสื่อ", isPresented: Binding(
                get: { mediaErrorMessage != nil },
                set: { if !$0 { mediaErrorMessage = nil } }
            )) {
                Button("ตกลง", role: .cancel) { mediaErrorMessage = nil }
            } message: {
                Text(mediaErrorMessage ?? "")
            }
        }
        .apColorScheme()
    }

    // MARK: - Tab 1: Details View

    private var detailsTabContent: some View {
        VStack(spacing: APSpacing.md) {
            // 1. Product media
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("สื่อสินค้า")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("รูปภาพ · สูงสุด 3 รูป")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)

                            HStack(spacing: APSpacing.sm) {
                                ForEach(Array(imageDataItems.enumerated()), id: \.offset) { index, data in
                                    mediaImageTile(data: data) {
                                        imageDataItems.remove(at: index)
                                    }
                                }

                                if imageDataItems.count < 3 {
                                    PhotosPicker(
                                        selection: $selectedPhotoItems,
                                        maxSelectionCount: 3 - imageDataItems.count,
                                        matching: .images,
                                        photoLibrary: .shared()
                                    ) {
                                        addMediaTile(title: "เพิ่มรูป", systemImage: "photo.badge.plus")
                                    }
                                    .onChange(of: selectedPhotoItems) { _, items in
                                        Task { await loadImages(from: items) }
                                    }
                                }
                            }
                        }

                        Divider().frame(height: 106)

                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("วิดีโอ · 1 คลิป / 10 วิ · MP4 720p")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)

                            if let videoData {
                                ZStack(alignment: .topTrailing) {
                                    RoundedRectangle(cornerRadius: APRadius.sm)
                                        .fill(Color.appAccent.opacity(0.12))
                                        .frame(width: 150, height: 82)
                                        .overlay {
                                            VStack(spacing: 4) {
                                                Image(systemName: "play.rectangle.fill").font(.title2)
                                                Text(ByteCountFormatter.string(fromByteCount: Int64(videoData.count), countStyle: .file))
                                                    .font(.caption2)
                                            }
                                            .foregroundColor(.appAccent)
                                        }
                                    removeMediaButton {
                                        self.videoData = nil
                                        selectedVideoItem = nil
                                    }
                                }
                            } else {
                                PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                                    addMediaTile(title: "เพิ่มวิดีโอ", systemImage: "video.badge.plus")
                                        .frame(width: 150)
                                }
                                .onChange(of: selectedVideoItem) { _, item in
                                    guard let item else { return }
                                    Task { await loadVideo(from: item) }
                                }
                            }
                        }

                        if isProcessingMedia {
                            ProgressView().padding(.top, 44)
                        }
                    }
                }
            }
            .padding(APSpacing.md)
            .apCard()

            // 2. Product Details & Fields
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("product_details_section".t)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                inputFieldRow(label: "Product Name", placeholder: "e.g., Iced Cappuccino, Gyoza", text: $name)
                inputFieldRow(label: "Product Name (English)", placeholder: "e.g., Iced Cappuccino, Gyoza", text: $nameEn)
                inputFieldRow(label: "Product Name (Chinese)", placeholder: "e.g., 冰卡布奇诺, 饺子", text: $nameZh)

                inputFieldRow(label: "Selling Price (฿)", placeholder: "0.00", text: $priceString)
                    .keyboardType(.decimalPad)

                inputFieldRow(label: "Description (Optional)", placeholder: "e.g., Double espresso shot with textured milk over ice", text: $description)
                inputFieldRow(label: "Description (English)", placeholder: "e.g., Double espresso shot with textured milk over ice", text: $descEn)
                inputFieldRow(label: "Description (Chinese)", placeholder: "e.g., 双份浓缩咖啡配打发牛奶", text: $descZh)

                VStack(alignment: .leading, spacing: 4) {
                    Text("product_category_label".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)

                    Picker("Category Picker", selection: $selectedCategoryId) {
                        Text("uncategorized_label".t).tag(nil as UUID?)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.appAccent)
                }

                inputFieldRow(label: "SKU Code (Optional)", placeholder: "e.g., SKU-12345", text: $sku)
                inputFieldRow(label: "Barcode / UPC (Optional)", placeholder: "e.g., 8851234567890", text: $barcode)

                // Color Tag Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("card_color_fallback".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: APSpacing.sm) {
                        ForEach(colorOptions, id: \.hex) { option in
                            Button(action: { selectedColorHex = option.hex }) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColorHex == option.hex ? 2 : 0)
                                    )
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)

                Toggle("Available for Sale", isOn: $isAvailable)
                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 4)

                Toggle(isOn: $isFavorite) {
                    Label("pin_to_favorites".t, systemImage: "star.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .padding(.vertical, 4)

                Divider().background(Color.appDivider).padding(.vertical, 4)

                Toggle("Price is Tax-Inclusive", isOn: $isTaxInclusive)
                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 4)

                inputFieldRow(label: "Tax Rate (%)", placeholder: "7.0", text: $taxRateString)
                    .keyboardType(.decimalPad)
            }
            .apCard()

            // Delivery Pricing Section
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("delivery_pricing_title".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)
                        Text("delivery_pricing_desc".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()

                    let availableBrands = ["GrabFood", "LINE MAN", "ShopeeFood", "Foodpanda", "Robinhood"].filter { brand in
                        !deliveryPriceInputs.contains(where: { $0.brandName == brand })
                    }

                    if !availableBrands.isEmpty {
                        Menu {
                            ForEach(availableBrands, id: \.self) { brand in
                                Button(action: {
                                    deliveryPriceInputs.append(DeliveryPriceInput(id: UUID(), brandName: brand, priceString: ""))
                                }) {
                                    Text(brand)
                                }
                            }
                        } label: {
                            Label("add_delivery_brand_btn".t, systemImage: "plus.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.appAccent)
                        }
                    }
                }

                if deliveryPriceInputs.isEmpty {
                    Text("no_delivery_prices_desc".t)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: APSpacing.sm) {
                        ForEach($deliveryPriceInputs) { $input in
                            HStack(spacing: APSpacing.md) {
                                DeliveryBrandLogo(brandName: input.brandName)
                                    .frame(width: 80, alignment: .leading)

                                Spacer()

                                HStack(spacing: 4) {
                                    Text("฿")
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                    TextField("0.00", text: $input.priceString)
                                        .keyboardType(.decimalPad)
                                        .font(.subheadline)
                                        .foregroundColor(.textPrimary)
                                        .padding(8)
                                        .background(Color.appSurfaceHigh)
                                        .cornerRadius(APRadius.sm)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: APRadius.sm)
                                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                                        )
                                        .frame(width: 90)
                                }

                                Button(action: {
                                    deliveryPriceInputs.removeAll(where: { $0.id == input.id })
                                }) {
                                    Image(systemName: "trash.fill")
                                        .foregroundColor(.appRose)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)

                            Divider().background(Color.appDivider)
                        }
                    }
                }
            }
            .padding(APSpacing.md)
            .apCard()

            if isEditing {
                deleteSectionCard
            }
        }
    }

    private var deleteSectionCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("danger_zone_title".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appRose)
                .textCase(.uppercase)

            Text("delete_product_danger_desc".t)
                .font(.caption2)
                .foregroundColor(.textSecondary)

            Button(action: { showingDeleteAlert = true }) {
                Text("prod_delete_btn".t)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.appRose)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .apCard()
    }

    // MARK: - Tab 2: Recipe View

    private var recipeTabContent: some View {
        VStack(spacing: APSpacing.md) {
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("stock_tracking_mode".t)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                Picker("Tracking Mode", selection: $trackingMode) {
                    Text("stock_mode_not_tracked".t).tag("not_tracked")
                    Text("stock_mode_finished_good".t).tag("finished_good")
                    Text("stock_mode_recipe_based".t).tag("recipe_based")
                }
                .pickerStyle(.segmented)
            }
            .padding(APSpacing.md)
            .apCard()

            if trackingMode == "finished_good" {
                VStack(alignment: .leading, spacing: APSpacing.md) {
                    Text("finished_good_settings".t)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)

                    Text("finished_good_settings_desc".t)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)

                    Picker("Linked Inventory Item", selection: $selectedIngredientId) {
                        Text("auto_create_matching_item".t).tag(nil as UUID?)
                        ForEach(allIngredients) { ingredient in
                            Text("\(ingredient.name) (SKU: \(ingredient.sku ?? "N/A"))").tag(ingredient.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.appAccent)
                }
                .padding(APSpacing.md)
                .apCard()
            } else if trackingMode == "recipe_based" {
                VStack(alignment: .leading, spacing: APSpacing.md) {
                    HStack {
                        Text("recipe_parts_section".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)
                        Spacer()
                        Button(action: { showingAddIngredient = true }) {
                            Label("add_raw_material_btn".t, systemImage: "plus.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    if recipeLines.isEmpty {
                        Text("no_ingredients_linked".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                    } else {
                        VStack(spacing: APSpacing.sm) {
                            ForEach($recipeLines) { $line in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.ingredient.name)
                                            .font(.subheadline)
                                            .foregroundColor(.textPrimary)
                                        Text("Cost: ฿\(String(format: "%.2f", line.ingredient.costPrice))/\(line.ingredient.unit)")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    HStack {
                                        TextField("0.0", text: $line.qtyString)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .font(.subheadline)
                                            .frame(width: 60)
                                            .padding(4)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                            .onChange(of: line.qtyString) { _, val in
                                                line.qty = Double(val) ?? 0.0
                                            }
                                        Text(line.ingredient.unit)
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                            .frame(width: 40, alignment: .leading)
                                    }
                                    Button(action: { recipeLines.removeAll(where: { $0.id == line.id }) }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.appRose)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Divider().background(Color.appDivider)
                            }
                        }
                    }
                }
                .padding(APSpacing.md)
                .apCard()
            }

            if trackingMode != "not_tracked" {
                costingAnalysisCard
            }
        }
    }

    private var costingAnalysisCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Text("margins_analysis_title".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)

            HStack(spacing: APSpacing.md) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(Color.appSurfaceHigh, lineWidth: 5).frame(width: 54, height: 54)
                        Circle().trim(from: 0, to: CGFloat(min(1.0, foodCostPercent / 100)))
                            .stroke(foodCostPercent > 40 ? Color.appRose : Color.appTeal, lineWidth: 5)
                            .frame(width: 54, height: 54).rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f%%", foodCostPercent)).font(.caption).bold()
                    }
                    Text("food_cost_pct".t).font(.system(size: 8)).foregroundColor(.textSecondary)
                }
                VStack(spacing: 4) {
                    ZStack {
                        Circle().stroke(Color.appSurfaceHigh, lineWidth: 5).frame(width: 54, height: 54)
                        Circle().trim(from: 0, to: CGFloat(min(1.0, grossMarginPercent / 100)))
                            .stroke(grossMarginPercent >= 60 ? Color.appTeal : Color.appRose, lineWidth: 5)
                            .frame(width: 54, height: 54).rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f%%", grossMarginPercent)).font(.caption).bold()
                    }
                    Text("margin_pct".t).font(.system(size: 8)).foregroundColor(.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    costRow(label: "Selling Price", val: "฿\(String(format: "%.2f", menuPrice))")
                    costRow(label: "Ingredient Cost", val: "฿\(String(format: "%.2f", totalCost))")
                    costRow(label: "Gross Profit", val: "฿\(String(format: "%.2f", max(0.0, menuPrice - totalCost)))")
                }
                .padding(.leading, 8)
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }

    private func costRow(label: String, val: String) -> some View {
        HStack {
            Text(label).font(.system(size: 9)).foregroundColor(.textSecondary)
            Spacer()
            Text(val).font(.system(size: 10)).bold().foregroundColor(.textPrimary)
        }
    }

    private var ingredientSelectionSheet: some View {
        NavigationStack {
            List(allIngredients) { ingredient in
                Button(action: {
                    if !recipeLines.contains(where: { $0.ingredient.id == ingredient.id }) {
                        recipeLines.append(RecipeLineInput(
                            ingredient: ingredient,
                            qty: 1.0,
                            qtyString: "1.0"
                        ))
                    }
                    showingAddIngredient = false
                }) {
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundColor(.appAccent)
                    }
                }
            }
            .navigationTitle("add_ingredient_title".t)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { showingAddIngredient = false }
                }
            }
        }
        .apColorScheme()
    }

    // MARK: - Tab 3: Extras (Modifiers)

    private var extrasTabContent: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Text("link_customization_options".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)

            Text("link_customization_desc".t)
                .font(.caption2)
                .foregroundColor(.textSecondary)

            if allModifierGroups.isEmpty {
                Text("no_custom_options_desc".t)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach(allModifierGroups) { group in
                        Toggle(isOn: Binding(
                            get: { linkedModifierGroupIds.contains(group.id) },
                            set: { isLinked in
                                if isLinked {
                                    linkedModifierGroupIds.insert(group.id)
                                } else {
                                    linkedModifierGroupIds.remove(group.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.textPrimary)
                                Text("Min: \(group.minSelection) · Max: \(group.maxSelection) · Options: \(group.modifiers.count)")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                        .padding(.vertical, 4)

                        Divider().background(Color.appDivider)
                    }
                }
                .padding(APSpacing.md)
                .apCard()
            }
        }
    }

    // MARK: - Save Logic

    private var bottomActionPanel: some View {
        HStack(spacing: APSpacing.md) {
            Button(action: onDismiss) {
                Text("cancel_btn_label".t)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)

            Button(action: saveProduct) {
                Text(isEditing ? "Save Changes" : "Create Product")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(name.isEmpty || priceString.isEmpty ? .textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(name.isEmpty || priceString.isEmpty ? nil : APGradient.accent)
                    .backgroundColor(name.isEmpty || priceString.isEmpty ? Color.appSurfaceHigh : .clear)
                    .cornerRadius(APRadius.md)
            }
            .disabled(name.isEmpty || priceString.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }

    private func inputFieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .tint(.appAccent)
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
    }

    private func addMediaTile(title: String, systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: APRadius.sm)
            .fill(Color.appAccent.opacity(0.10))
            .frame(width: 92, height: 82)
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: systemImage).font(.title3)
                    Text(title).font(.caption2).fontWeight(.semibold)
                }
                .foregroundColor(.appAccent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: APRadius.sm)
                    .stroke(Color.appAccent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
    }

    private func mediaImageTile(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.appSurfaceHigh.overlay { Image(systemName: "photo") }
                }
            }
            .frame(width: 92, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))

            removeMediaButton(action: onRemove)
        }
    }

    private func removeMediaButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.65))
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    @MainActor
    private func loadImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isProcessingMedia = true
        defer {
            isProcessingMedia = false
            selectedPhotoItems = []
        }

        for item in items.prefix(3 - imageDataItems.count) {
            guard let original = try? await item.loadTransferable(type: Data.self),
                  let compressed = compressedImageData(from: original) else {
                mediaErrorMessage = "อ่านไฟล์รูปภาพไม่สำเร็จ กรุณาเลือกรูปอื่น"
                continue
            }
            imageDataItems.append(compressed)
        }
    }

    @MainActor
    private func loadVideo(from item: PhotosPickerItem) async {
        isProcessingMedia = true
        defer { isProcessingMedia = false }

        do {
            guard let movie = try await item.loadTransferable(type: ProductMovie.self) else {
                throw ProductMediaError.unreadableVideo
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }

            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite, duration.seconds <= 10.05 else {
                throw ProductMediaError.videoTooLong
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("product-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
                throw ProductMediaError.exportFailed
            }
            try await exporter.export(to: outputURL, as: .mp4)
            let compressed = try Data(contentsOf: outputURL, options: .mappedIfSafe)
            guard compressed.count <= 15 * 1_024 * 1_024 else {
                throw ProductMediaError.videoTooLarge
            }
            videoData = compressed
        } catch let error as ProductMediaError {
            selectedVideoItem = nil
            mediaErrorMessage = error.localizedDescription
        } catch {
            selectedVideoItem = nil
            mediaErrorMessage = "ไม่สามารถประมวลผลวิดีโอนี้ได้ กรุณาลองไฟล์อื่น"
        }
    }

    private func compressedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 1_600 / longestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    private func loadProductData() {
        if let item = menuItem {
            name = item.name
            priceString = String(format: "%.2f", item.price)
            description = item.itemDescription ?? ""
            selectedCategoryId = item.category?.id
            isAvailable = item.isAvailable

            // Load new fields
            barcode = item.barcode ?? ""
            sku = item.sku ?? ""
            isTaxInclusive = item.isTaxInclusive ?? true
            isFavorite = item.isFavorite ?? false
            selectedColorHex = item.colorHex
            imageDataItems = [item.imageData, item.imageData2, item.imageData3].compactMap { $0 }
            videoData = item.videoData
            taxRateString = String(format: "%.1f", item.taxRate)

            // Load translations
            let nameTrans = item.nameTranslations
            let descTrans = item.descriptionTranslations
            nameEn = nameTrans["en"] ?? ""
            nameZh = nameTrans["zh"] ?? ""
            descEn = descTrans["en"] ?? ""
            descZh = descTrans["zh"] ?? ""

            // Load delivery prices
            deliveryPriceInputs = item.deliveryPrices.map { dp in
                DeliveryPriceInput(
                    id: dp.id,
                    brandName: dp.brandName,
                    priceString: String(format: "%.2f", dp.price)
                )
            }

            // Load recipe
            let recipes = item.recipes
            if recipes.isEmpty {
                trackingMode = "not_tracked"
            } else if recipes.count == 1 && recipes.first?.quantityRequired == 1.0 {
                trackingMode = "finished_good"
                selectedIngredientId = recipes.first?.inventoryItem?.id
            } else {
                trackingMode = "recipe_based"
                recipeLines = recipes.map { rec in
                    let ing = rec.inventoryItem!
                    return RecipeLineInput(
                        ingredient: ing,
                        qty: rec.quantityRequired,
                        qtyString: String(format: "%.1f", rec.quantityRequired)
                    )
                }
            }

            // Load linked modifiers
            linkedModifierGroupIds = Set(item.modifierGroupsRelations.compactMap { $0.modifierGroup?.id })
        }
    }

    private func saveProduct() {
        let price = Double(priceString) ?? 0.0
        let taxRate = Double(taxRateString) ?? 7.0
        let barcodeVal = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let skuVal = sku.trimmingCharacters(in: .whitespacesAndNewlines)

        let deliveryPricesList = deliveryPriceInputs.compactMap { input -> (brandName: String, price: Double)? in
            guard let pr = Double(input.priceString) else { return nil }
            return (brandName: input.brandName, price: pr)
        }

        var nameTrans: [String: String] = [:]
        var descTrans: [String: String] = [:]

        let nEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let nZh = nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let dEn = descEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let dZh = descZh.trimmingCharacters(in: .whitespacesAndNewlines)

        if !nEn.isEmpty { nameTrans["en"] = nEn }
        if !nZh.isEmpty { nameTrans["zh"] = nZh }
        if !dEn.isEmpty { descTrans["en"] = dEn }
        if !dZh.isEmpty { descTrans["zh"] = dZh }

        // Snapshot images to upload after the local save completes.
        let imagesToUpload = imageDataItems

        // Resolve the MenuItem instance that was saved so we can upload its media.
        var savedItem: MenuItem?

        if let item = menuItem {
            // Update details
            viewModel.updateProduct(
                menuItem: item,
                name: name,
                price: price,
                description: description.isEmpty ? nil : description,
                categoryId: selectedCategoryId,
                isAvailable: isAvailable,
                barcode: barcodeVal.isEmpty ? nil : barcodeVal,
                sku: skuVal.isEmpty ? nil : skuVal,
                isTaxInclusive: isTaxInclusive,
                isFavorite: isFavorite,
                colorHex: selectedColorHex,
                imageData: imageDataItems.indices.contains(0) ? imageDataItems[0] : nil,
                imageData2: imageDataItems.indices.contains(1) ? imageDataItems[1] : nil,
                imageData3: imageDataItems.indices.contains(2) ? imageDataItems[2] : nil,
                videoData: videoData,
                taxRate: taxRate,
                deliveryPrices: deliveryPricesList,
                nameTranslations: nameTrans,
                descriptionTranslations: descTrans
            )

            // Update recipes
            let linesData = recipeLines.map { (ingredientId: $0.ingredient.id, qty: $0.qty) }
            viewModel.saveRecipe(
                for: item,
                trackingMode: trackingMode,
                selectedIngredientId: selectedIngredientId,
                recipeLines: linesData
            )

            // Update modifiers linkage
            viewModel.updateProductModifierGroups(menuItem: item, selectedGroupIds: Array(linkedModifierGroupIds))

            savedItem = item

        } else {
            // Add new product
            viewModel.addProduct(
                name: name,
                price: price,
                description: description.isEmpty ? nil : description,
                categoryId: selectedCategoryId,
                isAvailable: isAvailable,
                barcode: barcodeVal.isEmpty ? nil : barcodeVal,
                sku: skuVal.isEmpty ? nil : skuVal,
                isTaxInclusive: isTaxInclusive,
                isFavorite: isFavorite,
                colorHex: selectedColorHex,
                imageData: imageDataItems.indices.contains(0) ? imageDataItems[0] : nil,
                imageData2: imageDataItems.indices.contains(1) ? imageDataItems[1] : nil,
                imageData3: imageDataItems.indices.contains(2) ? imageDataItems[2] : nil,
                videoData: videoData,
                taxRate: taxRate,
                deliveryPrices: deliveryPricesList,
                nameTranslations: nameTrans,
                descriptionTranslations: descTrans
            )

            // Fetch the freshly created item so its media can be uploaded.
            let newName = name
            let descriptor = FetchDescriptor<MenuItem>(
                predicate: #Predicate { $0.name == newName },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            savedItem = try? modelContext.fetch(descriptor).first
        }

        // Upload product images to Supabase Storage, then persist the returned URLs.
        if !imagesToUpload.isEmpty, let uploadItem = savedItem {
            let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
            let itemId = uploadItem.id
            let context = modelContext

            Task { @MainActor in
                for (index, data) in imagesToUpload.enumerated() {
                    let fileName = "image_\(index + 1).jpg"
                    do {
                        let url = try await NetworkManager.shared.uploadProductMedia(
                            data,
                            merchantId: merchantId,
                            itemId: itemId,
                            fileName: fileName,
                            contentType: "image/jpeg"
                        )
                        switch index {
                        case 0: uploadItem.imageUrl = url
                        case 1: uploadItem.imageUrl2 = url
                        case 2: uploadItem.imageUrl3 = url
                        default: break
                        }
                    } catch {
                        #if DEBUG
                        print("ProductEditSheet: uploadProductMedia failed for \(fileName): \(error.localizedDescription)")
                        #endif
                    }
                }
                context.saveWithLogging(label: "ProductEditSheet.uploadProductMedia")
            }
        }

        onDismiss()
    }
}

private struct ProductMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("selected-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return ProductMovie(url: copyURL)
        }
    }
}

private enum ProductMediaError: LocalizedError {
    case unreadableVideo
    case videoTooLong
    case videoTooLarge
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadableVideo: return "อ่านไฟล์วิดีโอไม่สำเร็จ กรุณาเลือกคลิปอื่น"
        case .videoTooLong: return "วิดีโอต้องมีความยาวไม่เกิน 10 วินาที"
        case .videoTooLarge: return "วิดีโอหลังบีบอัดต้องมีขนาดไม่เกิน 15 MB"
        case .exportFailed: return "อุปกรณ์ไม่รองรับการแปลงวิดีโอนี้"
        }
    }
}

struct DeliveryBrandLogo: View {
    let brandName: String

    var body: some View {
        let text: String
        let bgColor: Color

        switch brandName.lowercased() {
        case "grabfood", "grab":
            text = "Grab"
            bgColor = Color(hex: "00B14F")
        case "line man", "lineman":
            text = "LINE MAN"
            bgColor = Color(hex: "06C755")
        case "shopeefood", "shopee food":
            text = "Shopee"
            bgColor = Color(hex: "EE4D2D")
        case "foodpanda", "food panda":
            text = "panda"
            bgColor = Color(hex: "E21B70")
        case "robinhood":
            text = "Robin"
            bgColor = Color(hex: "5C2E91")
        default:
            text = brandName
            bgColor = Color.gray
        }

        return Text(text)
            .font(.system(size: 9, weight: .black))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
