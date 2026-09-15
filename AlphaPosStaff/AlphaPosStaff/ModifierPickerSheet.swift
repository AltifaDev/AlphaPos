// ModifierPickerSheet.swift
// AlphaPosStaff — Option / modifier picker (parity with master iPad device)
//
// Presented when a staff member adds a menu item that has modifier groups.
// Enforces each group's min/max selection rules and returns the chosen
// modifiers. Styled with iOS 26 Liquid Glass to match the rest of the app.

import SwiftUI

struct ModifierPickerSheet: View {
    let menuItem: MenuItem
    let groups: [StaffModifierGroup]
    let appLanguage: String
    // Edit mode: pre-selected options and starting quantity (defaults = fresh add).
    var preselectedModifierIds: Set<String> = []
    var initialQuantity: Int = 1
    let onConfirm: ([StaffModifier], Int) -> Void

    @Environment(\.dismiss) private var dismiss

    // groupId → selected modifier ids
    @State private var selections: [String: Set<String>] = [:]
    @State private var quantity: Int = 1

    private let royalBlue = Color.appAccent
    private let elfGreen  = Color.appTeal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
                .padding(16)
            }
            .onAppear(perform: primeSelections)
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) { confirmBar }
            .navigationTitle("customize_options".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(for: appLanguage)) { dismiss() }
                }
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Text(menuItem.emoji ?? "🍽️")
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(menuItem.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("฿\(Int(menuItem.price))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .apLiquidGlass(tint: royalBlue.opacity(0.06),
                       in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Group card
    @ViewBuilder
    private func groupCard(_ group: StaffModifierGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(group.isRequired
                     ? "required".localized(for: appLanguage)
                     : "optional".localized(for: appLanguage))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(group.isRequired ? elfGreen : .textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .apLiquidGlass(tint: (group.isRequired ? elfGreen : Color.gray).opacity(0.14),
                                   in: Capsule(style: .continuous))
            }

            if group.maxSelection > 1 {
                Text("\("choose_up_to".localized(for: appLanguage)) \(group.maxSelection)")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            ForEach(group.modifiers) { mod in
                optionRow(group: group, mod: mod)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .apLiquidGlass(tint: royalBlue.opacity(0.05),
                       in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Option row
    @ViewBuilder
    private func optionRow(group: StaffModifierGroup, mod: StaffModifier) -> some View {
        let isSelected = selections[group.id]?.contains(mod.id) ?? false
        Button {
            toggle(group: group, mod: mod)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.isSingleChoice
                      ? (isSelected ? "largecircle.fill.circle" : "circle")
                      : (isSelected ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? royalBlue : .textTertiary)

                Text(mod.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.textPrimary)

                Spacer()

                if mod.extraPrice > 0 {
                    Text("+฿\(Int(mod.extraPrice))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isSelected ? royalBlue : .textSecondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? royalBlue.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // MARK: - Confirm bar
    private var confirmBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)
            HStack(spacing: 12) {
                // Quantity stepper
                HStack(spacing: 14) {
                    Button { if quantity > 1 { quantity -= 1; APHaptic.trigger() } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableButtonStyle())
                    Text("\(quantity)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .frame(minWidth: 22)
                    Button { quantity += 1; APHaptic.trigger() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(.horizontal, 6)
                .apLiquidGlass(tint: royalBlue.opacity(0.10),
                               in: Capsule(style: .continuous))

                // Add button
                Button {
                    APHaptic.success()
                    onConfirm(chosenModifiers, quantity)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("add_to_order".localized(for: appLanguage))
                            .font(.system(size: 15, weight: .bold))
                        Text("฿\(Int(currentTotal))")
                            .font(.system(size: 15, weight: .black))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Color.clear.apLiquidGlass(
                            tint: allRequiredSatisfied ? elfGreen : Color.gray,
                            interactive: true,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!allRequiredSatisfied)
                .opacity(allRequiredSatisfied ? 1 : 0.6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appSurface)
        }
    }

    // MARK: - Logic

    /// Seed selections/quantity from edit-mode inputs (runs once on appear).
    private func primeSelections() {
        guard selections.isEmpty else { return }
        quantity = max(1, initialQuantity)
        guard !preselectedModifierIds.isEmpty else { return }
        for group in groups {
            let ids = group.modifiers.map(\.id).filter { preselectedModifierIds.contains($0) }
            if !ids.isEmpty { selections[group.id] = Set(ids) }
        }
    }

    private func toggle(group: StaffModifierGroup, mod: StaffModifier) {
        var set = selections[group.id] ?? []
        if group.isSingleChoice {
            set = set.contains(mod.id) && !group.isRequired ? [] : [mod.id]
        } else {
            if set.contains(mod.id) {
                set.remove(mod.id)
            } else if set.count < group.maxSelection {
                set.insert(mod.id)
            }
        }
        selections[group.id] = set
        APHaptic.trigger()
    }

    private var chosenModifiers: [StaffModifier] {
        groups.flatMap { group in
            (selections[group.id] ?? []).compactMap { id in
                group.modifiers.first { $0.id == id }
            }
        }
    }

    private var allRequiredSatisfied: Bool {
        groups.allSatisfy { group in
            let count = selections[group.id]?.count ?? 0
            return count >= group.minSelection
        }
    }

    private var currentTotal: Double {
        let addOns = chosenModifiers.reduce(0) { $0 + $1.extraPrice }
        return (menuItem.price + addOns) * Double(quantity)
    }
}
