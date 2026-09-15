// FirstProductGuideSheet.swift
// AlphaPos — Guided first sellable item (learn-by-doing; no sample catalog)

import SwiftUI
import SwiftData

enum FirstProductGuideOutcome {
    case createTable
    case openPOS
    case dismiss
}

/// Progressive first-product create: explain → name + price → success + next step.
struct FirstProductGuideSheet: View {
    let onComplete: (FirstProductGuideOutcome) -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(filter: #Predicate<Category> { !$0.isDeleted }, sort: \Category.name)
    private var categories: [Category]
    @Query(sort: \Branch.name) private var branches: [Branch]

    @AppStorage("inventory_profile") private var inventoryProfile = "restaurant"
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    @State private var viewModel = InventoryViewModel()
    @State private var step = 0 // 0 intro, 1 form, 2 success
    @State private var name = ""
    @State private var priceString = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var didSave = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Double(priceString) ?? -1) >= 0
    }

    private var isRetailProfile: Bool {
        inventoryProfile == "simple"
    }

    private var activeBranch: Branch? {
        guard let uuid = UUID(uuidString: activeBranchId) else { return nil }
        return branches.first(where: { $0.id == uuid })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                Group {
                    switch step {
                    case 0: introStep
                    case 1: formStep
                    default: successStep
                    }
                }
                .padding(APSpacing.md)
            }
            .navigationTitle(
                step == 2
                    ? "first_product_success_title".t
                    : "first_product_guide_title".t
            )
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        onComplete(.dismiss)
                    }
                    .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                viewModel.modelContext = modelContext
            }
        }
        .apColorScheme()
        .interactiveDismissDisabled(step == 2 && didSave)
    }

    // MARK: - Steps

    private var introStep: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Color(hex: "2D71F8").opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "menucard.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Color(hex: "2D71F8"))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("first_product_intro_headline".t)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text("first_product_intro_body".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                tipRow(icon: "textformat", text: "first_product_tip_name".t)
                tipRow(icon: "tag.fill", text: "first_product_tip_price".t)
                tipRow(icon: "square.grid.2x2", text: "first_product_tip_category".t)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
            } label: {
                Text("first_product_start_cta".t)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(APGradient.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var formStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.md) {
                Text("first_product_form_hint".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)

                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    fieldLabel("item_name_placeholder".t, tip: "first_product_field_name_tip".t)
                    TextField("item_name_placeholder".t, text: $name)
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.sm)
                        .foregroundColor(.textPrimary)

                    fieldLabel("sell_price_placeholder".t, tip: "first_product_field_price_tip".t)
                    TextField("0.00", text: $priceString)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.sm)
                        .foregroundColor(.textPrimary)

                    fieldLabel("catalog_categories".t, tip: "first_product_field_category_tip".t)
                    Picker("catalog_categories".t, selection: $selectedCategoryId) {
                        Text("no_category_option".t).tag(nil as UUID?)
                        ForEach(categories) { cat in
                            Text(cat.name).tag(cat.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.appAccent)
                }
                .padding(APSpacing.md)
                .apCard()

                if isRetailProfile {
                    Text("first_product_retail_note".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                } else {
                    Text("first_product_restaurant_note".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                Button {
                    saveProduct()
                } label: {
                    Text("first_product_save_cta".t)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(canSave ? .white : .textTertiary)
                        .background {
                            if canSave {
                                APGradient.accent
                            } else {
                                Color.appSurfaceHigh
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                Text("first_product_advanced_hint".t)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var successStep: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.appTeal)
            }

            Text("first_product_success_headline".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                String(
                    format: "first_product_success_body".t,
                    name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            .font(.subheadline)
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            Spacer(minLength: 0)

            if enableTableSystem {
                Button {
                    onComplete(.createTable)
                } label: {
                    Text("first_product_next_table".t)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(APGradient.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("first_product_next_pos".t) {
                    onComplete(.openPOS)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textSecondary)
            } else {
                Button {
                    onComplete(.openPOS)
                } label: {
                    Text("first_product_next_pos".t)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(APGradient.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button("first_product_done".t) {
                onComplete(.dismiss)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.textTertiary)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "2D71F8"))
                .frame(width: 22)
            Text(text)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ title: String, tip: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
            Text(tip)
                .font(.caption2)
                .foregroundColor(.textTertiary)
        }
    }

    private func saveProduct() {
        guard canSave else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = Double(priceString) ?? 0
        viewModel.modelContext = modelContext

        if isRetailProfile {
            _ = viewModel.createFinishedGood(
                name: trimmed,
                sellPrice: price,
                costPrice: max(0, price * 0.5),
                initialQuantity: 0,
                unit: "piece",
                barcode: nil,
                sku: nil,
                reorderLevel: 5,
                categoryId: selectedCategoryId,
                activeBranch: activeBranch
            )
        } else {
            viewModel.addProduct(
                name: trimmed,
                price: price,
                description: nil,
                categoryId: selectedCategoryId,
                isAvailable: true
            )
        }

        didSave = true
        withAnimation(.easeInOut(duration: 0.25)) {
            step = 2
        }
    }
}
