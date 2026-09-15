// FinishedGoodQuickCreateSheet.swift
// AlphaPos — One-step create for retail finished goods (sell 1 = cut 1)

import SwiftUI
import SwiftData
import UIKit

struct FinishedGoodQuickCreateSheet: View {
    let activeBranch: Branch?
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(filter: #Predicate<Category> { !$0.isDeleted }, sort: \Category.name)
    private var categories: [Category]

    @State private var viewModel = InventoryViewModel()
    @State private var name = ""
    @State private var sellPriceString = ""
    @State private var costPriceString = ""
    @State private var initialQtyString = "0"
    @State private var reorderString = "5"
    @State private var unit = "piece"
    @State private var barcode = ""
    @State private var sku = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var salesRole: MenuItemSalesRole = .main
    @State private var salesRoleWasManuallySelected = false

    private struct UnitPreset: Identifiable, Hashable {
        let id: String
        let code: String
        let thaiName: String
        let englishName: String
        let icon: String

        func displayName(isThai: Bool) -> String {
            isThai ? thaiName : englishName
        }
    }

    private let standardUnitPresets: [UnitPreset] = [
        UnitPreset(id: "piece", code: "piece", thaiName: "ชิ้น", englishName: "Piece", icon: "shippingbox"),
        UnitPreset(id: "bottle", code: "bottle", thaiName: "ขวด", englishName: "Bottle", icon: "waterbottle"),
        UnitPreset(id: "can", code: "can", thaiName: "กระป๋อง", englishName: "Can", icon: "cylinder.split.1x2"),
        UnitPreset(id: "cup", code: "cup", thaiName: "แก้ว", englishName: "Cup", icon: "cup.and.saucer"),
        UnitPreset(id: "pack", code: "pack", thaiName: "แพ็ก", englishName: "Pack", icon: "square.grid.2x2"),
        UnitPreset(id: "box", code: "box", thaiName: "กล่อง", englishName: "Box", icon: "archivebox"),
        UnitPreset(id: "dish", code: "dish", thaiName: "จาน", englishName: "Dish", icon: "fork.knife"),
        UnitPreset(id: "bag", code: "bag", thaiName: "ถุง", englishName: "Bag", icon: "bag"),
        UnitPreset(id: "kg", code: "kg", thaiName: "กก.", englishName: "kg", icon: "scalemass"),
        UnitPreset(id: "g", code: "g", thaiName: "กรัม", englishName: "g", icon: "scalemass.fill"),
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Double(sellPriceString) ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        infoBanner

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("fg_quick_product_section".t)

                            // Row 1: Name & Price
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("item_name_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("item_name_placeholder".t, text: $name)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "banknote.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("sell_price_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("0.00", text: $sellPriceString, keyboard: .decimalPad, prefix: "฿")
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Row 2: Category & Sales Role
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("catalog_categories".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    Picker("catalog_categories".t, selection: $selectedCategoryId) {
                                        Text("no_category_option".t).tag(nil as UUID?)
                                        ForEach(categories) { cat in
                                            Text(cat.name).tag(cat.id as UUID?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    .onChange(of: selectedCategoryId) { _, categoryId in
                                        guard !salesRoleWasManuallySelected else { return }
                                        salesRole = MenuItemSalesRole.inferred(
                                            from: categories.first(where: { $0.id == categoryId })?.name
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.grid.2x2.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("ประเภทการขาย")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    Picker("ประเภทการขาย", selection: Binding(
                                        get: { salesRole },
                                        set: {
                                            salesRole = $0
                                            salesRoleWasManuallySelected = true
                                        }
                                    )) {
                                        Text("เมนูหลัก").tag(MenuItemSalesRole.main)
                                        Text("รายการเสริม").tag(MenuItemSalesRole.addOn)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(minHeight: 38)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(APSpacing.md)
                        .apCard()

                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("fg_quick_stock_section".t)

                            // Unit of Measure (Presets + Custom Input)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "scalemass.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.appAccent)
                                    Text("unit_placeholder".t)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                    Spacer()
                                    Text(lm.currentLanguage == .thai ? "แตะเพื่อเลือกหรือพิมพ์เอง" : "Tap preset or type custom")
                                        .font(.system(size: 10))
                                        .foregroundColor(.textTertiary)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(standardUnitPresets) { preset in
                                            let isSelected = unit.lowercased() == preset.code.lowercased()
                                                || unit == preset.thaiName
                                                || unit.lowercased() == preset.englishName.lowercased()
                                            Button {
                                                APHaptic.selection()
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                                    unit = lm.currentLanguage == .thai ? preset.thaiName : preset.code
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: preset.icon)
                                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                                    Text(preset.displayName(isThai: lm.currentLanguage == .thai))
                                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .foregroundColor(isSelected ? .white : .textPrimary)
                                                .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            .hoverEffect(.lift)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }

                                field(lm.currentLanguage == .thai ? "ระบุหน่วยนับ เช่น ชิ้น, ขวด, แก้ว, kg..." : "Unit name e.g. piece, bottle, cup, kg...", text: $unit)
                            }

                            // Row 1: Initial Qty & Cost Price
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shippingbox.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("fg_opening_qty_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("0", text: $initialQtyString, keyboard: .decimalPad, suffix: unit)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "banknote.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("unit_cost_price_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("0.00", text: $costPriceString, keyboard: .decimalPad, prefix: "฿", suffix: "/\(unit)")
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Row 2: Reorder Level & Barcode
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("reorder_trigger_level_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("5", text: $reorderString, keyboard: .decimalPad, suffix: unit)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "barcode")
                                            .font(.system(size: 11))
                                            .foregroundColor(.appAccent)
                                        Text("barcode_placeholder".t)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    field("barcode_placeholder".t, text: $barcode)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Row 3: SKU
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 4) {
                                    Image(systemName: "number")
                                        .font(.system(size: 11))
                                        .foregroundColor(.appAccent)
                                    Text("sku_code_placeholder".t)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textSecondary)
                                }
                                field("sku_code_placeholder".t, text: $sku)
                            }
                        }
                        .padding(APSpacing.md)
                        .apCard()

                        Text("fg_quick_help".t)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("fg_quick_create_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                        .foregroundStyle(APGradient.accent)
                }
            }
            .onAppear {
                viewModel.modelContext = modelContext
            }
        }
        .apColorScheme()
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: APSpacing.sm) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.appTeal)
            VStack(alignment: .leading, spacing: 4) {
                Text("fg_quick_banner_title".t)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Text("fg_quick_banner_desc".t)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(APSpacing.md)
        .background(Color.appTeal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(Color.appTeal.opacity(0.25), lineWidth: 1)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.textSecondary)
            .textCase(.uppercase)
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        prefix: String? = nil,
        suffix: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            if let prefix {
                Text(prefix)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
            if let suffix, !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func save() {
        let sell = Double(sellPriceString) ?? 0
        let cost = Double(costPriceString) ?? max(0, sell * 0.5)
        let qty = Double(initialQtyString) ?? 0
        let reorder = Double(reorderString) ?? 5

        _ = viewModel.createFinishedGood(
            name: name,
            sellPrice: sell,
            costPrice: cost,
            initialQuantity: qty,
            unit: unit,
            barcode: barcode.isEmpty ? nil : barcode,
            sku: sku.isEmpty ? nil : sku,
            reorderLevel: reorder,
            categoryId: selectedCategoryId,
            salesRole: salesRole,
            activeBranch: activeBranch
        )
        onComplete()
    }
}
