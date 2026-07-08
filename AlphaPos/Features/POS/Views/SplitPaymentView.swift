// SplitPaymentView.swift
// AlphaPos — Split Payment Workflow

import SwiftUI
import SwiftData

// MARK: - Split Payment Data Types

struct SplitPaymentEntry: Identifiable {
    let id = UUID()
    var method: String = "Cash"
    var amount: Double = 0.0
    var amountText: String = ""
}

// MARK: - Split Payment View Model

@Observable
@MainActor
final class SplitPaymentViewModel {
    var totalAmount: Double
    var entries: [SplitPaymentEntry] = []
    var splitByGuests: Int = 2
    var showEqualSplit: Bool = false

    var paidTotal: Double {
        entries.reduce(0.0) { $0 + $1.amount }
    }

    var remainingBalance: Double {
        max(0, totalAmount - paidTotal)
    }

    var isBalanced: Bool {
        abs(paidTotal - totalAmount) < 0.01
    }

    var isOverpaid: Bool {
        paidTotal > totalAmount + 0.01
    }

    static let paymentMethods = ["Cash", "QR PromptPay", "Credit Card"]

    init(totalAmount: Double) {
        self.totalAmount = totalAmount
        // Start with one entry pre-filled with total
        entries = [SplitPaymentEntry(method: "Cash", amount: totalAmount, amountText: String(format: "%.2f", totalAmount))]
    }

    func addPaymentEntry() {
        let remaining = remainingBalance
        entries.append(SplitPaymentEntry(
            method: "Cash",
            amount: remaining,
            amountText: remaining > 0 ? String(format: "%.2f", remaining) : ""
        ))
    }

    func removeEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func splitEqually() {
        guard splitByGuests > 0 else { return }
        let totalCents = Int((totalAmount * 100).rounded())
        let baseCents = totalCents / splitByGuests
        let remainder = totalCents % splitByGuests
        entries = (0..<splitByGuests).map { i in
            let method = SplitPaymentViewModel.paymentMethods[i % SplitPaymentViewModel.paymentMethods.count]
            let amount = Double(baseCents + (i < remainder ? 1 : 0)) / 100.0
            return SplitPaymentEntry(
                method: method,
                amount: amount,
                amountText: String(format: "%.2f", amount)
            )
        }
        assert(Int((paidTotal * 100).rounded()) == totalCents)
    }

    func updateAmount(for id: UUID, text: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].amountText = text
        entries[idx].amount = Double(text) ?? 0.0
    }

    func updateMethod(for id: UUID, method: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].method = method
    }
}

// MARK: - Split Payment View

struct SplitPaymentView: View {
    let totalAmount: Double
    let onComplete: ([SplitPaymentEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SplitPaymentViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if let vm = viewModel {
                    contentView(vm: vm)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("split_payment_title".t)
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.Common.cancel.t) {
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
        }
        .apColorScheme()
        .onAppear {
            viewModel = SplitPaymentViewModel(totalAmount: totalAmount)
        }
    }

    // MARK: - Content

    private func contentView(vm: SplitPaymentViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    // Bill total card
                    billTotalCard(vm: vm)

                    // Equal split option
                    equalSplitSection(vm: vm)

                    // Payment entries
                    paymentEntriesSection(vm: vm)

                    // Add payment button
                    addPaymentButton(vm: vm)
                }
                .padding(APSpacing.md)
            }

            // Bottom bar
            bottomBar(vm: vm)
        }
    }

    // MARK: - Bill Total Card

    private func billTotalCard(vm: SplitPaymentViewModel) -> some View {
        VStack(spacing: APSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("split_bill_total".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Text("฿\(vm.totalAmount, specifier: "%.2f")")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("split_remaining".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Text("฿\(vm.remainingBalance, specifier: "%.2f")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(vm.isBalanced ? .appTeal : .appRose)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appSurfaceHigh)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            vm.isOverpaid ? AnyShapeStyle(APGradient.destructive)
                            : vm.isBalanced ? AnyShapeStyle(APGradient.positive)
                            : AnyShapeStyle(APGradient.accent)
                        )
                        .frame(width: min(geo.size.width, geo.size.width * CGFloat(vm.paidTotal / max(vm.totalAmount, 1))))
                        .animation(.spring(response: 0.4), value: vm.paidTotal)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Paid: ฿\(vm.paidTotal, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
                if vm.isBalanced {
                    Label("split_balanced".t, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.appTeal)
                } else if vm.isOverpaid {
                    Label("split_overpaid".t, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.appRose)
                }
            }
        }
        .apCard()
    }

    // MARK: - Equal Split Section

    private func equalSplitSection(vm: SplitPaymentViewModel) -> some View {
        VStack(spacing: APSpacing.sm) {
            Button(action: {
                withAnimation(.spring(response: 0.4)) {
                    vm.showEqualSplit.toggle()
                }
                APHaptic.trigger()
            }) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.appAccent)
                    Text("split_equally_by_guests".t)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: vm.showEqualSplit ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }

            if vm.showEqualSplit {
                HStack(spacing: APSpacing.md) {
                    Text("split_guests_label".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 0) {
                        Button(action: {
                            if vm.splitByGuests > 2 {
                                vm.splitByGuests -= 1
                            }
                            APHaptic.trigger()
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appAccent)
                                .frame(width: 36, height: 36)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(APRadius.sm)
                        }

                        Text("\(vm.splitByGuests)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .frame(width: 50)

                        Button(action: {
                            vm.splitByGuests += 1
                            APHaptic.trigger()
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appAccent)
                                .frame(width: 36, height: 36)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(APRadius.sm)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("split_per_person".t)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("฿\(vm.totalAmount / Double(vm.splitByGuests), specifier: "%.2f")")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.textPrimary)
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.4)) {
                            vm.splitEqually()
                        }
                        APHaptic.trigger()
                    }) {
                        Text("btn_apply".t)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, APSpacing.sm)
                            .background(Color.appAccent)
                            .cornerRadius(APRadius.sm)
                    }
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Payment Entries Section

    private func paymentEntriesSection(vm: SplitPaymentViewModel) -> some View {
        VStack(spacing: APSpacing.sm) {
            ForEach(Array(vm.entries.enumerated()), id: \.element.id) { index, entry in
                paymentEntryCard(vm: vm, entry: entry, index: index)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.4), value: vm.entries.count)
    }

    private func paymentEntryCard(vm: SplitPaymentViewModel, entry: SplitPaymentEntry, index: Int) -> some View {
        VStack(spacing: APSpacing.sm) {
            HStack {
                Text(String(format: "split_payment_index_template".t, index + 1))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                if vm.entries.count > 1 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            vm.removeEntry(id: entry.id)
                        }
                        APHaptic.trigger()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.appRose)
                    }
                }
            }

            // Payment Method Picker
            HStack(spacing: APSpacing.sm) {
                ForEach(SplitPaymentViewModel.paymentMethods, id: \.self) { method in
                    let isSelected = entry.method == method
                    Button(action: {
                        vm.updateMethod(for: entry.id, method: method)
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: iconForMethod(method))
                                .font(.system(size: 12))
                            Text(shortName(method))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                        .foregroundColor(isSelected ? .white : .textSecondary)
                        .cornerRadius(APRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.sm)
                                .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                }
            }

            // Amount field
            HStack {
                Text("฿")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textSecondary)

                TextField("0.00", text: Binding(
                    get: { entry.amountText },
                    set: { vm.updateAmount(for: entry.id, text: $0) }
                ))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
            .padding(APSpacing.sm)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.sm)
        }
        .apCard()
    }

    // MARK: - Add Payment Button

    private func addPaymentButton(vm: SplitPaymentViewModel) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4)) {
                vm.addPaymentEntry()
            }
            APHaptic.trigger()
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("split_add_payment_method".t)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.appAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
            )
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(vm: SplitPaymentViewModel) -> some View {
        VStack(spacing: APSpacing.sm) {
            Divider().background(Color.appDivider)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("split_total_payments".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text("฿\(vm.paidTotal, specifier: "%.2f") / ฿\(vm.totalAmount, specifier: "%.2f")")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(vm.isBalanced ? .appTeal : .textPrimary)
                }

                Spacer()

                Button(action: {
                    APHaptic.trigger()
                    onComplete(vm.entries)
                    dismiss()
                }) {
                    Text("split_complete_payment".t)
                        .apGradientButton(
                            gradient: APGradient.positive,
                            shadow: APShadow.positiveGlow,
                            disabled: !vm.isBalanced
                        )
                }
                .disabled(!vm.isBalanced)
                .frame(width: 220)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.sm)
        }
        .background(Color.appSurface)
    }

    // MARK: - Helpers

    private func iconForMethod(_ method: String) -> String {
        switch method {
        case "Cash": return "banknote"
        case "QR PromptPay": return "qrcode"
        case "Credit Card": return "creditcard"
        default: return "dollarsign.circle"
        }
    }

    private func shortName(_ method: String) -> String {
        switch method {
        case "QR PromptPay": return "QR"
        case "Credit Card": return "Card"
        default: return method
        }
    }
}
