// SplitBillView.swift
// AlphaPosStaff — Split Bill Feature
//
// Allows staff to split a bill among multiple guests using three modes:
// Equal Split, By Amount, or By Item assignment.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Split Mode Enum
// ─────────────────────────────────────────────────────────────────────────────

enum SplitMode: String, CaseIterable, Identifiable {
    case equal    = "equal"
    case byAmount = "by_amount"
    case byItem   = "by_item"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .equal:    return "divide.circle.fill"
        case .byAmount: return "dollarsign.circle.fill"
        case .byItem:   return "list.bullet.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .equal:    return Color.appIndigo      // indigo → appIndigo token
        case .byAmount: return Color.appTeal        // emerald → appTeal token
        case .byItem:   return Color.appAmber       // amber → appAmber token
        }
    }

    func localizedName(lang: String) -> String {
        switch self {
        case .equal:    return "equal_split".localized(for: lang)
        case .byAmount: return "split_by_amount".localized(for: lang)
        case .byItem:   return "split_by_item".localized(for: lang)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Split Payment Model
// ─────────────────────────────────────────────────────────────────────────────

struct SplitPayment: Identifiable {
    let id = UUID()
    var personIndex: Int
    var amount: Double
    var paymentMethod: String? // nil = unpaid
    var assignedItems: [OrderItem] // used in byItem mode
    var isPaid: Bool { paymentMethod != nil }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SplitBillView
// ─────────────────────────────────────────────────────────────────────────────

struct SplitBillView: View {
    let orderId: String
    let orderItems: [OrderItem]
    let totalAmount: Double

    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss

    // ── State ────────────────────────────────────────────────────────────────
    @State private var splitMode: SplitMode = .equal
    @State private var numberOfPeople: Int = 2
    @State private var splits: [SplitPayment] = []
    @State private var customAmounts: [Int: String] = [:] // personIndex -> amount string
    @State private var itemAssignments: [String: Int] = [:] // item.id -> personIndex
    @State private var selectedPersonForPayment: Int? = nil
    @State private var showPaymentPicker = false
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var animateSplit = false
    @State private var submitError: String? = nil
    @State private var showConfirmDialog = false

    // Design tokens
    private let accentBlue = Color.appAccent
    private let surfaceColor = Color.appSurface
    private let bgColor = Color.appBackground

    // ── Computed ─────────────────────────────────────────────────────────────

    private var amountPerPerson: Double {
        guard numberOfPeople > 0 else { return 0 }
        return totalAmount / Double(numberOfPeople)
    }

    private var totalPaid: Double {
        splits.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    private var remainingAmount: Double {
        totalAmount - totalPaid
    }

    private var allPaid: Bool {
        splits.allSatisfy { $0.isPaid }
    }

    /// ตรวจสอบว่า byAmount ยอดตรงหรือไม่
    private var byAmountIsBalanced: Bool {
        guard splitMode == .byAmount else { return true }
        let customTotal = splits.reduce(0.0) { $0 + $1.amount }
        return abs(totalAmount - customTotal) <= 0.01
    }

    /// ปุ่ม confirm ควร enable ไหม
    private var canConfirm: Bool {
        !isSubmitting && byAmountIsBalanced
    }

    private var confirmSummary: String {
        "\(numberOfPeople) " + "people".localized(for: appLanguage) + " • ฿\(String(format: "%.2f", totalAmount))"
    }

    // ── Body ─────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            ZStack {
                bgColor.ignoresSafeArea()

                if showSuccess {
                    successOverlay
                } else {
                    mainContent
                }
            }
            .navigationTitle("split_bill".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showPaymentPicker) {
                if let personIdx = selectedPersonForPayment {
                    PersonPaymentSheet(
                        personIndex: personIdx,
                        amount: splits.first(where: { $0.personIndex == personIdx })?.amount ?? 0,
                        appLanguage: appLanguage,
                        onPay: { method in
                            markAsPaid(personIndex: personIdx, method: method)
                            showPaymentPicker = false
                        }
                    )
                    .presentationDetents([.height(320)])
                }
            }
        }
        .onAppear {
            recalculateSplits()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animateSplit = true
            }
        }
        .alert("split_payment_failed".localized(for: appLanguage),
               isPresented: Binding(get: { submitError != nil }, set: { if !$0 { submitError = nil } })) {
            Button("ok".localized(for: appLanguage), role: .cancel) { submitError = nil }
        } message: {
            if let err = submitError {
                Text(err)
            }
        }
        .confirmationDialog(
            "confirm_split".localized(for: appLanguage),
            isPresented: $showConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("confirm".localized(for: appLanguage), role: .destructive) {
                Task { await submitSplitPayments() }
            }
            Button("cancel".localized(for: appLanguage), role: .cancel) {}
        } message: {
            Text(confirmSummary)
        }
    }


    // ── Main Content ─────────────────────────────────────────────────────────

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Total Header Card
                totalHeaderCard

                // Split Mode Selector
                modeSelector

                // People Count (for equal / byAmount)
                if splitMode != .byItem {
                    peopleCountSection
                }

                // Mode-specific content
                switch splitMode {
                case .equal:
                    equalSplitContent
                case .byAmount:
                    byAmountContent
                case .byItem:
                    byItemContent
                }

                // Payment Status
                paymentStatusSection

                // Confirm Button
                if !allPaid {
                    confirmSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // ── Total Header ─────────────────────────────────────────────────────────

    private var totalHeaderCard: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("total_amount".localized(for: appLanguage))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("฿\(String(format: "%.2f", totalAmount))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(orderItems.count) " + "items_label".localized(for: appLanguage))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("remaining".localized(for: appLanguage) + ": ฿\(String(format: "%.2f", remainingAmount))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(remainingAmount > 0 ? Color.appRose : Color.appTeal)
                }
            }
        }
        .padding(16)
        .background(surfaceColor)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appDivider, lineWidth: 1)
        )
    }

    // ── Mode Selector ────────────────────────────────────────────────────────

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(SplitMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        splitMode = mode
                        recalculateSplits()
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(mode.localizedName(lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(splitMode == mode ? .white : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        splitMode == mode
                            ? AnyShapeStyle(LinearGradient(
                                colors: [mode.color, mode.color.opacity(0.8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(surfaceColor)
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(splitMode == mode ? mode.color.opacity(0.5) : Color.appDivider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── People Count ─────────────────────────────────────────────────────────

    private var peopleCountSection: some View {
        VStack(spacing: 8) {
            Text("number_of_people".localized(for: appLanguage))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    if numberOfPeople > 2 {
                        numberOfPeople -= 1
                        recalculateSplits()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(numberOfPeople > 2 ? accentBlue : .textTertiary)
                }
                .disabled(numberOfPeople <= 2)

                Text("\(numberOfPeople)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .frame(minWidth: 40)

                Button {
                    if numberOfPeople < 10 {
                        numberOfPeople += 1
                        recalculateSplits()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(numberOfPeople < 10 ? accentBlue : .textTertiary)
                }
                .disabled(numberOfPeople >= 10)

                Spacer()

                if splitMode == .equal {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("each_pays".localized(for: appLanguage))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                        Text("฿\(String(format: "%.2f", amountPerPerson))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(splitMode.color)
                    }
                }
            }
            .padding(14)
            .background(surfaceColor)
            .cornerRadius(12)
        }
    }

    // ── Equal Split Content ──────────────────────────────────────────────────

    private var equalSplitContent: some View {
        VStack(spacing: 10) {
            ForEach(splits.indices, id: \.self) { idx in
                let split = splits[idx]
                personRow(split: split, index: idx)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
        }
    }

    // ── By Amount Content ────────────────────────────────────────────────────

    private var byAmountContent: some View {
        VStack(spacing: 10) {
            ForEach(splits.indices, id: \.self) { idx in
                let split = splits[idx]
                HStack(spacing: 12) {
                    // Person avatar
                    personAvatar(index: split.personIndex)

                    // Amount input
                    VStack(alignment: .leading, spacing: 2) {
                        Text(personLabel(split.personIndex))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        HStack(spacing: 4) {
                            Text("฿")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textTertiary)
                            TextField("0.00", text: Binding(
                                get: { customAmounts[split.personIndex] ?? String(format: "%.2f", split.amount) },
                                set: { newVal in
                                    customAmounts[split.personIndex] = newVal
                                    if let amt = Double(newVal) {
                                        splits[idx].amount = amt
                                    }
                                }
                            ))
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        }
                    }

                    Spacer()

                    // Pay button
                    payButtonForPerson(split: split)
                }
                .padding(14)
                .background(surfaceColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(split.isPaid ? Color.appTeal.opacity(0.5) : Color.appDivider, lineWidth: 1)
                )
            }

            // Remaining indicator
            let customTotal = splits.reduce(0.0) { $0 + $1.amount }
            let diff = totalAmount - customTotal
            if abs(diff) > 0.01 {
                HStack(spacing: 6) {
                    Image(systemName: diff > 0 ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 12))
                    Text(diff > 0
                         ? "\("remaining".localized(for: appLanguage)): ฿\(String(format: "%.2f", diff))"
                         : "Over by ฿\(String(format: "%.2f", -diff))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(diff > 0 ? .appAmber : .appRose)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(diff > 0 ? Color.appAmber.opacity(0.1) : Color.appRose.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // ── By Item Content ──────────────────────────────────────────────────────

    private var byItemContent: some View {
        VStack(spacing: 12) {
            // People count for item mode
            peopleCountSection

            // Items with assignment
            VStack(spacing: 8) {
                Text("assign_items".localized(for: appLanguage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(orderItems) { item in
                    HStack(spacing: 10) {
                        // Item info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text("x\(item.quantity) • ฿\(String(format: "%.0f", item.price * Double(item.quantity)))")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        // Person picker (horizontal scroll of avatars)
                        HStack(spacing: 6) {
                            ForEach(0..<numberOfPeople, id: \.self) { pIdx in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        itemAssignments[item.id] = pIdx
                                        recalculateItemSplits()
                                    }
                                } label: {
                                    Text("\(pIdx + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(itemAssignments[item.id] == pIdx ? .white : .textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            itemAssignments[item.id] == pIdx
                                                ? splitMode.color
                                                : Color.appDivider.opacity(0.5)
                                        )
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(surfaceColor)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                itemAssignments[item.id] != nil ? splitMode.color.opacity(0.3) : Color.appDivider,
                                lineWidth: 1
                            )
                    )
                }
            }

            // Summary per person
            if !splits.isEmpty {
                VStack(spacing: 8) {
                    Divider().background(Color.appDivider)
                    ForEach(splits.indices, id: \.self) { idx in
                        personRow(split: splits[idx], index: idx)
                    }
                }
            }
        }
    }

    // ── Person Row (reusable) ────────────────────────────────────────────────

    private func personRow(split: SplitPayment, index: Int) -> some View {
        HStack(spacing: 12) {
            personAvatar(index: split.personIndex)

            VStack(alignment: .leading, spacing: 2) {
                Text(personLabel(split.personIndex))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if splitMode == .byItem && !split.assignedItems.isEmpty {
                    Text("\(split.assignedItems.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Text("฿\(String(format: "%.2f", split.amount))")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(split.isPaid ? Color.appTeal : .textPrimary)

            payButtonForPerson(split: split)
        }
        .padding(14)
        .background(surfaceColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(split.isPaid ? Color.appTeal.opacity(0.5) : Color.appDivider, lineWidth: 1)
        )
        .opacity(animateSplit ? 1 : 0)
        .offset(y: animateSplit ? 0 : 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.08), value: animateSplit)
    }

    // ── Pay Button ───────────────────────────────────────────────────────────

    private func payButtonForPerson(split: SplitPayment) -> some View {
        Group {
            if split.isPaid {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("paid".localized(for: appLanguage))
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color.appTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appTeal.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button {
                    selectedPersonForPayment = split.personIndex
                    showPaymentPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 12))
                        Text("pay_now".localized(for: appLanguage))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentBlue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Payment Status Section ───────────────────────────────────────────────

    private var paymentStatusSection: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appDivider)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.appTeal, Color(hex: "10B981")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (totalAmount > 0 ? totalPaid / totalAmount : 0), height: 6)
                        .animation(.spring(response: 0.4), value: totalPaid)
                }
            }
            .frame(height: 6)

            HStack {
                Text("paid".localized(for: appLanguage) + ": ฿\(String(format: "%.2f", totalPaid))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appTeal)
                Spacer()
                Text("unpaid".localized(for: appLanguage) + ": ฿\(String(format: "%.2f", remainingAmount))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(remainingAmount > 0 ? Color.appRose : .textTertiary)
            }
        }
        .padding(14)
        .background(surfaceColor)
        .cornerRadius(12)
    }

    // ── Confirm Section ──────────────────────────────────────────────────────

    private var confirmSection: some View {
        Button {
            showConfirmDialog = true
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                }
                Text("confirm_split".localized(for: appLanguage))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: allPaid
                        ? [Color.appTeal, Color(hex: "10B981")]
                        : [accentBlue, accentBlue.opacity(0.8)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: accentBlue.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm)
        .padding(.top, 8)
    }

    // ── Success Overlay ──────────────────────────────────────────────────────

    private var successOverlay: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.12))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Color.appTeal.opacity(0.06))
                    .frame(width: 160, height: 160)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color.appTeal)
            }
            .scaleEffect(showSuccess ? 1 : 0.5)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showSuccess)

            Text("split_bill".localized(for: appLanguage) + " ✓")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("\(numberOfPeople) people • ฿\(String(format: "%.2f", totalAmount))")
                .font(.system(size: 15))
                .foregroundColor(.textSecondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("done".localized(for: appLanguage))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appTeal)
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func personAvatar(index: Int) -> some View {
        let colors: [Color] = [
            Color(hex: "6366F1"), Color(hex: "EC4899"), Color(hex: "10B981"),
            Color(hex: "F59E0B"), Color(hex: "3B82F6"), Color(hex: "8B5CF6"),
            Color(hex: "EF4444"), Color(hex: "14B8A6"), Color(hex: "F97316"),
            Color(hex: "06B6D4")
        ]
        let color = colors[index % colors.count]

        return Text("\(index + 1)")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(color)
            .clipShape(Circle())
    }

    private func personLabel(_ index: Int) -> String {
        let template = "person_n".localized(for: appLanguage)
        if template.contains("%d") {
            return template.replacingOccurrences(of: "%d", with: "\(index + 1)")
        }
        return "\(template) \(index + 1)"
    }

    private func recalculateSplits() {
        switch splitMode {
        case .equal:
            splits = (0..<numberOfPeople).map { idx in
                SplitPayment(
                    personIndex: idx,
                    amount: amountPerPerson,
                    paymentMethod: splits.first(where: { $0.personIndex == idx })?.paymentMethod,
                    assignedItems: []
                )
            }
        case .byAmount:
            let existing = splits
            splits = (0..<numberOfPeople).map { idx in
                SplitPayment(
                    personIndex: idx,
                    amount: existing.first(where: { $0.personIndex == idx })?.amount ?? amountPerPerson,
                    paymentMethod: existing.first(where: { $0.personIndex == idx })?.paymentMethod,
                    assignedItems: []
                )
            }
        case .byItem:
            recalculateItemSplits()
        }
    }

    private func recalculateItemSplits() {
        var personAmounts: [Int: Double] = [:]
        var personItems: [Int: [OrderItem]] = [:]
        for i in 0..<numberOfPeople {
            personAmounts[i] = 0
            personItems[i] = []
        }

        for item in orderItems {
            let assignedTo = itemAssignments[item.id] ?? 0
            personAmounts[assignedTo, default: 0] += item.price * Double(item.quantity)
            personItems[assignedTo, default: []].append(item)
        }

        splits = (0..<numberOfPeople).map { idx in
            SplitPayment(
                personIndex: idx,
                amount: personAmounts[idx] ?? 0,
                paymentMethod: splits.first(where: { $0.personIndex == idx })?.paymentMethod,
                assignedItems: personItems[idx] ?? []
            )
        }
    }

    private func markAsPaid(personIndex: Int, method: String) {
        if let idx = splits.firstIndex(where: { $0.personIndex == personIndex }) {
            withAnimation(.spring(response: 0.3)) {
                splits[idx].paymentMethod = method
            }
        }
    }

    private func submitSplitPayments() async {
        isSubmitting = true
        APHaptic.trigger()

        // Build split payment payloads
        let splitPayloads: [[String: Any]] = splits.map { split in
            var payload: [String: Any] = [
                "person_index": split.personIndex,
                "amount": split.amount,
                "payment_method": split.paymentMethod ?? "pending"
            ]
            if !split.assignedItems.isEmpty {
                payload["item_ids"] = split.assignedItems.map { $0.id }
            }
            return payload
        }

        do {
            _ = try await NetworkService.shared.uploadSplitPayment(
                orderId: orderId,
                splits: splitPayloads
            )
            withAnimation(.spring(response: 0.4)) {
                showSuccess = true
            }
            APHaptic.success()
        } catch {
            // 🔴 แสดง error จริง — ห้าม set showSuccess = true เมื่อ fail
            submitError = "split_payment_error_msg".localized(for: appLanguage) + "\n\(error.localizedDescription)"
            APHaptic.error()
        }

        isSubmitting = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Person Payment Sheet
// ─────────────────────────────────────────────────────────────────────────────

private struct PersonPaymentSheet: View {
    let personIndex: Int
    let amount: Double
    let appLanguage: String
    let onPay: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Amount
                VStack(spacing: 4) {
                    Text("person_n".localized(for: appLanguage)
                        .replacingOccurrences(of: "%d", with: "\(personIndex + 1)"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("฿\(String(format: "%.2f", amount))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                .padding(.top, 8)

                Divider().background(Color.appDivider)

                // Payment methods
                VStack(spacing: 10) {
                    paymentOption(icon: "banknote.fill", label: "Cash", color: Color(hex: "10B981"), method: "cash")
                    paymentOption(icon: "creditcard.fill", label: "Card", color: Color(hex: "3B82F6"), method: "credit_card")
                    paymentOption(icon: "qrcode", label: "PromptPay QR", color: Color(hex: "003B71"), method: "qr_promptpay")
                }

                Spacer()
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle("select_payment".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
    }

    private func paymentOption(icon: String, label: String, color: Color, method: String) -> some View {
        Button { onPay(method) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
