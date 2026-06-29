import SwiftUI
import Combine

// MARK: - Mixed Payment Entry (Staff)
struct StaffPaymentEntry: Identifiable {
    let id = UUID()
    var method: String = "cash"   // "cash" | "qr" | "card"
    var amount: Double = 0.0
    var amountText: String = ""
    var cashReceived: Double = 0.0  // only for cash entries
}

struct BillingView: View {
    let table: RestaurantTable
    let orders: [Order]
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var selectedMethod = "cash" // "cash", "qr", "card"

    // Cash payment calculator states
    @State private var paymentProcessing = false
    @State private var paymentSuccess = false

    // H-3: Error display after failed checkout
    @State private var checkoutErrorMessage: String? = nil

    // ── Mixed Payment state ────────────────────────────────────────────
    @State private var paymentEntries: [StaffPaymentEntry] = []
    @State private var isMixedMode = false
    @State private var activeEntryId: UUID? = nil    // which entry is being input
    @State private var showingEntryModal = false
    @State private var editingEntry: StaffPaymentEntry? = nil

    @Environment(\.dismiss) private var dismiss
    
    var subtotal: Double {
        orders.map { $0.total }.reduce(0, +)
    }
    
    var tax: Double {
        subtotal * 0.07
    }
    
    var serviceCharge: Double {
        subtotal * 0.10
    }
    
    var grandTotal: Double {
        subtotal + tax + serviceCharge
    }

    private var isAllServed: Bool {
        if !NetworkService.shared.kitchenWorkflowRequired { return true }
        guard !orders.isEmpty else { return false }
        return orders.allSatisfy { order in
            order.status == "cancelled" ||
            order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
        }
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if paymentSuccess {
                successState
            } else if !isAllServed {
                checkoutBlockedState
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            orderSummaryCard
                            financialSummaryCard
                            mixedPaymentSection
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("checkout_title".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { entry in
            StaffPaymentEntrySheet(
                entry: entry,
                remaining: remainingAfterOthers(excluding: entry.id),
                appLanguage: appLanguage
            ) { updated in
                applyEntryUpdate(updated)
            }
        }
        .onAppear {
            initPaymentEntries()
        }
        // H-3: Show error alert when checkout fails
        .alert("ชำระเงินไม่สำเร็จ", isPresented: Binding(
            get: { checkoutErrorMessage != nil },
            set: { if !$0 { checkoutErrorMessage = nil } }
        )) {
            Button("ลองใหม่", role: .cancel) { checkoutErrorMessage = nil }
        } message: {
            Text(checkoutErrorMessage ?? "")
        }
    }

    // MARK: - Computed helpers

    private var paidTotal: Double { paymentEntries.reduce(0) { $0 + $1.amount } }
    private var remainingBalance: Double { max(0, grandTotal - paidTotal) }
    private var isBalanced: Bool { abs(paidTotal - grandTotal) < 0.01 }
    private var isOverpaid: Bool { paidTotal > grandTotal + 0.01 }

    private func remainingAfterOthers(excluding id: UUID) -> Double {
        let othersTotal = paymentEntries.filter { $0.id != id }.reduce(0) { $0 + $1.amount }
        return max(0, grandTotal - othersTotal)
    }

    private func methodLabel(_ m: String) -> String {
        switch m {
        case "cash": return "เงินสด"
        case "qr":   return "QR"
        case "card": return "บัตร"
        default:     return m
        }
    }
    private func methodIcon(_ m: String) -> String {
        switch m {
        case "cash": return "banknote.fill"
        case "qr":   return "qrcode"
        case "card": return "creditcard.fill"
        default:     return "dollarsign.circle"
        }
    }
    private func methodColor(_ m: String) -> Color {
        switch m {
        case "cash": return .appTeal
        case "qr":   return Color.appPurple
        case "card": return Color.appRose
        default:     return .appAccent
        }
    }

    // MARK: - Init payment entries

    private func initPaymentEntries() {
        guard paymentEntries.isEmpty else { return }
        paymentEntries = [StaffPaymentEntry(method: "cash", amount: grandTotal,
                                            amountText: String(format: "%.2f", grandTotal))]
    }

    // MARK: - Order Summary Card

    private var orderSummaryCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("billing_summary".localized(for: appLanguage))
                .font(.headline).fontWeight(.bold).foregroundColor(.textPrimary)
            Divider().background(Color.appDivider)
            ForEach(orders) { order in
                ForEach(order.items) { item in
                    HStack {
                        Text("\(item.quantity)x \(item.name)")
                            .font(.subheadline).foregroundColor(.textPrimary)
                        Spacer()
                        Text("฿\(Int(item.price * Double(item.quantity)))")
                            .font(.subheadline).foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .apCard()
    }

    // MARK: - Financial Summary Card

    private var financialSummaryCard: some View {
        VStack(spacing: APSpacing.sm) {
            receiptRow(label: "subtotal".localized(for: appLanguage), value: subtotal)
            receiptRow(label: "vat_label".localized(for: appLanguage), value: tax)
            receiptRow(label: "service_charge_label".localized(for: appLanguage), value: serviceCharge)
            Divider().background(Color.appDivider).padding(.vertical, 4)
            HStack {
                Text("grand_total".localized(for: appLanguage))
                    .font(.title3).fontWeight(.black).foregroundColor(.textPrimary)
                Spacer()
                Text("฿\(String(format: "%.2f", grandTotal))")
                    .font(.title3).fontWeight(.black).foregroundColor(.appRose)
            }
        }
        .apCard()
    }

    // MARK: - Mixed Payment Section

    private var mixedPaymentSection: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                Text("ช่องทางการชำระเงิน")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.textSecondary)
                Spacer()
                if isBalanced {
                    Label("ครบแล้ว", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold)).foregroundColor(.appTeal)
                } else if paidTotal > 0 {
                    Text("คงเหลือ ฿\(String(format: "%.2f", remainingBalance))")
                        .font(.caption.weight(.bold)).foregroundColor(.appRose)
                }
            }

            if paymentEntries.count > 1 || (paidTotal > 0 && !isBalanced) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.appSurfaceHigh)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isOverpaid ? Color.appRose : isBalanced ? Color.appTeal : Color.appAccent)
                            .frame(width: geo.size.width * min(1, CGFloat(grandTotal > 0 ? paidTotal / grandTotal : 0)))
                            .animation(.spring(response: 0.45), value: paidTotal)
                    }
                }
                .frame(height: 6)
            }

            ForEach(Array(paymentEntries.enumerated()), id: \.element.id) { idx, entry in
                paymentEntryCard(entry: entry, index: idx)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .scale(scale: 0.92).combined(with: .opacity)
                    ))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: paymentEntries.count)

            if paymentEntries.count < 3 && !isBalanced {
                Button {
                    APHaptic.trigger()
                    addPaymentEntry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 15))
                        Text("+ เพิ่มช่องทางการชำระเงิน")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.appAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color.appAccent.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    )
                }
            }

            Button {
                APHaptic.trigger()
                processMixedCheckout()
            } label: {
                ZStack {
                    if paymentProcessing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(isBalanced
                                 ? "ยืนยันชำระเงิน  ฿\(String(format: "%.2f", grandTotal))"
                                 : "ยืนยันชำระเงิน (ขาด ฿\(String(format: "%.2f", remainingBalance)))")
                                .font(.system(size: 16, weight: .black))
                        }
                    }
                }
                .foregroundColor(isBalanced && !paymentProcessing ? .white : .textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Group {
                        if isBalanced && !paymentProcessing {
                            LinearGradient(colors: [Color.appTeal, Color.appTeal],
                                           startPoint: .leading, endPoint: .trailing)
                                .cornerRadius(APRadius.md)
                        } else {
                            Color.appSurfaceHigh
                                .cornerRadius(APRadius.md)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
            }
            .disabled(!isBalanced || paymentProcessing)
            .animation(.spring(response: 0.3), value: isBalanced)
        }
        .padding()
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Payment Entry Card

    private func paymentEntryCard(entry: StaffPaymentEntry, index: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("ช่องทางที่ \(index + 1)")
                    .font(.caption.weight(.bold)).foregroundColor(.textSecondary)
                Spacer()
                if paymentEntries.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            paymentEntries.removeAll { $0.id == entry.id }
                            if let lastIdx = paymentEntries.indices.last {
                                let others = paymentEntries.dropLast().reduce(0) { $0 + $1.amount }
                                let remain = max(0, grandTotal - others)
                                paymentEntries[lastIdx].amount = remain
                                paymentEntries[lastIdx].amountText = String(format: "%.2f", remain)
                            }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.appRose).font(.system(size: 16))
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(["cash", "qr", "card"], id: \.self) { method in
                    let isSelected = entry.method == method
                    Button {
                        APHaptic.trigger()
                        updateEntryMethod(id: entry.id, method: method)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: methodIcon(method)).font(.system(size: 12))
                            Text(methodLabel(method)).font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(isSelected ? .white : .textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isSelected ? methodColor(method) : Color.appSurfaceHigh)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Button {
                editingEntry = entry
            } label: {
                HStack {
                    Image(systemName: methodIcon(entry.method))
                        .foregroundColor(methodColor(entry.method)).font(.system(size: 18))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("฿\(String(format: "%.2f", entry.amount))")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(entry.amount > 0 ? methodColor(entry.method) : .textSecondary)
                        if entry.method == "cash" && entry.cashReceived > 0 {
                            Text("รับมา ฿\(String(format: "%.2f", entry.cashReceived)) · ทอน ฿\(String(format: "%.2f", entry.cashReceived - entry.amount))")
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                }
                .padding(12)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(entry.amount > 0 ? methodColor(entry.method).opacity(0.25) : Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Entry management

    private func addPaymentEntry() {
        let remaining = remainingBalance
        paymentEntries.append(StaffPaymentEntry(
            method: "qr",
            amount: remaining,
            amountText: remaining > 0 ? String(format: "%.2f", remaining) : ""
        ))
    }

    private func updateEntryMethod(id: UUID, method: String) {
        guard let idx = paymentEntries.firstIndex(where: { $0.id == id }) else { return }
        paymentEntries[idx].method = method
    }

    private func applyEntryUpdate(_ updated: StaffPaymentEntry) {
        guard let idx = paymentEntries.firstIndex(where: { $0.id == updated.id }) else { return }
        paymentEntries[idx] = updated
        editingEntry = nil
    }

    // MARK: - Mixed Checkout

    private func processMixedCheckout() {
        // C-8 FIX: guard against double-tap — paymentProcessing acts as mutex
        guard isAllServed, isBalanced, !paymentProcessing else { return }
        paymentProcessing = true
        checkoutErrorMessage = nil

        Task {
            do {
                let activeOrders  = orders.filter { $0.status != "cancelled" }
                let totalOrderAmt = activeOrders.map { $0.total }.reduce(0, +)
                let primaryEntry  = paymentEntries[0]

                // Upload secondary entries
                for entry in paymentEntries.dropFirst() {
                    guard entry.amount > 0 else { continue }
                    _ = try await NetworkService.shared.uploadPayment(
                        orderId: activeOrders.last?.id ?? "",
                        amount:  entry.amount,
                        method:  entry.method
                    )
                }

                // Primary entry via completeCheckout RPC
                for (idx, order) in activeOrders.enumerated() {
                    let isLast     = idx == activeOrders.count - 1
                    let proportion = totalOrderAmt > 0 ? order.total / totalOrderAmt : 1.0
                    let orderAmt   = primaryEntry.amount * proportion

                    if isLast {
                        _ = try await NetworkService.shared.completeCheckout(
                            paymentId:   UUID(),
                            orderId:     order.id,
                            amount:      orderAmt,
                            method:      primaryEntry.method,
                            tableNumber: table.tableNumber
                        )
                    } else {
                        _ = try await NetworkService.shared.uploadPayment(
                            orderId: order.id,
                            amount:  orderAmt,
                            method:  primaryEntry.method
                        )
                    }
                }

                await MainActor.run {
                    paymentProcessing = false
                    paymentSuccess     = true
                    APHaptic.trigger()
                    NotificationCenter.default.post(name: .checkoutCompleted, object: table.tableNumber)
                }
                await NetworkService.shared.refreshAll()

            } catch {
                // H-3 FIX: Show meaningful error to user instead of silently resetting
                await MainActor.run {
                    paymentProcessing = false
                    checkoutErrorMessage = "เกิดข้อผิดพลาด: \(error.localizedDescription)\n\nกรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่"
                }
            }
        }
    }
    
    private func receiptRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline).foregroundColor(.textSecondary)
            Spacer()
            Text("฿\(Int(value))")
                .font(.subheadline).foregroundColor(.textPrimary)
        }
    }

    // MARK: - Transaction success state

    // MARK: - Checkout Blocked State

    private var checkoutBlockedState: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.appAmber.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 62))
                    .foregroundColor(.appAmber)
            }

            VStack(spacing: APSpacing.xs) {
                Text("checkout_blocked_unserved_title".localized(for: appLanguage))
                    .font(.title3).fontWeight(.black).foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text("all_items_served_before_checkout".localized(for: appLanguage))
                    .font(.subheadline).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(APSpacing.lg)
    }

    private var successState: some View {
        VStack(spacing: APSpacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(APGradient.positive)
            }
            
            VStack(spacing: APSpacing.sm) {
                Text("payment_successful_title".localized(for: appLanguage))
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Text(String(format: "receipt_printed_msg".localized(for: appLanguage), String(table.tableNumber)))
                    .font(.subheadline).foregroundColor(.textSecondary)
            }
            
            VStack(spacing: APSpacing.sm) {
                receiptRow(label: "grand_total".localized(for: appLanguage), value: grandTotal)
                HStack {
                    Text("payment_type".localized(for: appLanguage))
                        .font(.caption).foregroundColor(.textSecondary)
                    Spacer()
                    Text(selectedMethod.uppercased())
                        .font(.caption).fontWeight(.bold).foregroundColor(.textPrimary)
                }
            }
            .padding()
            .apCard()
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text("done".localized(for: appLanguage))
                    .apGradientButton()
            }
            .padding()
        }
    }
}

// MARK: - Staff Payment Entry Sheet (Mixed Payment Input)
// ─────────────────────────────────────────────────────────────────────────────
// Opens as a .sheet for each payment entry — handles cash calc, QR confirm,
// and card confirm. Returns an updated StaffPaymentEntry via onConfirm.
// ─────────────────────────────────────────────────────────────────────────────

struct StaffPaymentEntrySheet: View {
    let entry:       StaffPaymentEntry
    let remaining:   Double          // max allowed for this entry
    let appLanguage: String
    let onConfirm:   (StaffPaymentEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText:    String = ""
    @State private var cashReceivedText: String = ""
    @State private var localEntry:    StaffPaymentEntry
    // H-6: FocusState for keyboard dismissal via Done toolbar button
    @FocusState private var amountFieldFocused: Bool
    @FocusState private var cashFieldFocused:   Bool

    init(entry: StaffPaymentEntry, remaining: Double, appLanguage: String,
         onConfirm: @escaping (StaffPaymentEntry) -> Void) {
        self.entry       = entry
        self.remaining   = remaining
        self.appLanguage = appLanguage
        self.onConfirm   = onConfirm
        _localEntry      = State(initialValue: entry)
        _amountText      = State(initialValue: entry.amount > 0 ? String(format: "%.2f", entry.amount) : "")
        _cashReceivedText = State(initialValue: entry.cashReceived > 0 ? String(format: "%.2f", entry.cashReceived) : "")
    }

    private var parsedAmount: Double { Double(amountText) ?? 0 }
    private var parsedCashReceived: Double { Double(cashReceivedText) ?? 0 }
    private var change: Double { max(0, parsedCashReceived - parsedAmount) }
    private var isOverAmount: Bool { parsedAmount > remaining + 0.01 }
    private var canConfirm: Bool {
        parsedAmount > 0 && !isOverAmount &&
        (localEntry.method != "cash" || parsedCashReceived >= parsedAmount)
    }

    private func methodColor(_ m: String) -> Color {
        switch m {
        case "cash": return .appTeal
        case "qr":   return Color.appPurple
        case "card": return Color.appRose
        default:     return .appAccent
        }
    }
    private func methodIcon(_ m: String) -> String {
        switch m {
        case "cash": return "banknote.fill"
        case "qr":   return "qrcode"
        case "card": return "creditcard.fill"
        default:     return "dollarsign.circle"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {

                        // Remaining balance chip
                        HStack {
                            Text("ยอดที่ต้องชำระในช่องทางนี้")
                                .font(.caption).foregroundColor(.textSecondary)
                            Spacer()
                            Text("฿\(String(format: "%.2f", remaining))")
                                .font(.caption.weight(.black))
                                .foregroundColor(methodColor(localEntry.method))
                        }
                        .padding(10)
                        .background(methodColor(localEntry.method).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Amount input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("จำนวนเงินในช่องทางนี้")
                                .font(.subheadline.weight(.semibold)).foregroundColor(.textSecondary)
                            HStack {
                                Text("฿").font(.system(size: 22, weight: .bold)).foregroundColor(.textSecondary)
                                TextField("0.00", text: $amountText)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundColor(isOverAmount ? .appRose : .textPrimary)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($amountFieldFocused)
                                    .toolbar { ToolbarItem(placement: .keyboard) { Button("เสร็จ") { amountFieldFocused = false; cashFieldFocused = false } } }
                            }
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Quick amount buttons
                            HStack(spacing: 8) {
                                let quickAmounts: [Double] = [remaining, 100, 200, 500, 1000]
                                ForEach(quickAmounts.filter { $0 > 0 }.prefix(4), id: \.self) { amt in
                                    Button {
                                        amountText = String(format: "%.2f", amt)
                                        if localEntry.method == "cash" {
                                            cashReceivedText = String(format: "%.2f", max(amt, parsedCashReceived))
                                        }
                                    } label: {
                                        Text(amt == remaining ? "เต็มจำนวน" : "฿\(Int(amt))")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.appAccent)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color.appAccent.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            if isOverAmount {
                                Label("เกินยอดคงเหลือ ฿\(String(format: "%.2f", remaining))",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.bold)).foregroundColor(.appRose)
                            }
                        }
                        .apCard()

                        // Cash: received + change
                        if localEntry.method == "cash" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("รับเงินมา")
                                    .font(.subheadline.weight(.semibold)).foregroundColor(.textSecondary)
                                HStack {
                                    Text("฿").font(.system(size: 20, weight: .bold)).foregroundColor(.textSecondary)
                                    TextField("0.00", text: $cashReceivedText)
                                        .font(.system(size: 28, weight: .black, design: .rounded))
                                        .foregroundColor(.textPrimary)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(12)
                                .background(Color.appSurfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                HStack(spacing: 8) {
                                    ForEach([parsedAmount, parsedAmount + (100 - parsedAmount.truncatingRemainder(dividingBy: 100)),
                                             500.0, 1000.0].filter { $0 >= parsedAmount }.prefix(4), id: \.self) { amt in
                                        Button {
                                            cashReceivedText = String(format: "%.2f", amt)
                                        } label: {
                                            Text("฿\(Int(amt))")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(.appTeal)
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(Color.appTeal.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }

                                if parsedCashReceived > 0 && parsedCashReceived >= parsedAmount {
                                    HStack {
                                        Text("เงินทอน")
                                            .font(.subheadline.weight(.semibold)).foregroundColor(.textSecondary)
                                        Spacer()
                                        Text("฿\(String(format: "%.2f", change))")
                                            .font(.system(size: 22, weight: .black, design: .rounded))
                                            .foregroundColor(.appTeal)
                                    }
                                    .padding(12)
                                    .background(Color.appTeal.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else if parsedCashReceived > 0 {
                                    Label("รับเงินน้อยกว่ายอดชำระ",
                                          systemImage: "exclamationmark.circle.fill")
                                        .font(.caption.weight(.bold)).foregroundColor(.appRose)
                                }
                            }
                            .apCard()
                        }

                        // QR: just confirm
                        if localEntry.method == "qr" {
                            VStack(spacing: 10) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 44)).foregroundColor(Color.appPurple)
                                Text("แสดง QR PromptPay ให้ลูกค้าสแกน")
                                    .font(.subheadline).foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .apCard()
                        }

                        // Card: just confirm
                        if localEntry.method == "card" {
                            VStack(spacing: 10) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 44)).foregroundColor(Color.appRose)
                                Text("รูดบัตรหรือแตะบัตรที่เครื่อง EDC")
                                    .font(.subheadline).foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .apCard()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("ใส่ยอดชำระ — ช่องทางที่ \(localEntry.method == "cash" ? "เงินสด" : localEntry.method == "qr" ? "QR" : "บัตร")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }.foregroundColor(.appAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ยืนยัน") {
                        var confirmed = localEntry
                        confirmed.amount       = parsedAmount
                        confirmed.amountText   = amountText
                        confirmed.cashReceived = localEntry.method == "cash" ? parsedCashReceived : 0
                        onConfirm(confirmed)
                    }
                    .fontWeight(.bold)
                    .foregroundColor(canConfirm ? .appTeal : .textSecondary)
                    .disabled(!canConfirm)
                }
            }
        }
    }
}

// MARK: - Notification name
extension Notification.Name {
    static let checkoutCompleted = Notification.Name("AlphaPosStaff.CheckoutCompleted")
}

// MARK: - Staff Cash Payment Modal View

struct StaffCashPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var cashReceivedText = ""
    @State private var showSuccessOverlay = false
    @State private var delayRemaining = 3.0
    @State private var isProcessing = false
    
    private var cashReceived: Double {
        Double(cashReceivedText) ?? 0.0
    }
    
    private var changeDue: Double {
        cashReceived - totalAmount
    }
    
    private var isAmountSufficient: Bool {
        cashReceived >= totalAmount
    }
    
    private func handleKeypadInput(_ input: String) {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            if input == "⌫" {
                if !cashReceivedText.isEmpty {
                    cashReceivedText.removeLast()
                }
            } else if input == "." {
                if !cashReceivedText.contains(".") {
                    if cashReceivedText.isEmpty {
                        cashReceivedText = "0."
                    } else {
                        cashReceivedText += "."
                    }
                }
            } else {
                if cashReceivedText == "0" {
                    cashReceivedText = input
                } else {
                    if cashReceivedText.count < 8 {
                        cashReceivedText += input
                    }
                }
            }
        }
    }
    
    private func formatAmountNoCent(_ amount: Double) -> String {
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", amount)
        } else {
            return String(format: "%.2f", amount)
        }
    }
    
    private func startCheckoutDelay() {
        isProcessing = true
        APHaptic.success()  // payment success haptic

        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            showSuccessOverlay = true
        }

        Task {
            let holdSeconds = changeDue == 0.0 ? 2 : 3
            for _ in 0..<holdSeconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    withAnimation {
                        if delayRemaining > 1 {
                            delayRemaining -= 1
                        }
                    }
                }
            }
            await MainActor.run {
                onConfirm(cashReceived)
                dismiss()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if showSuccessOverlay {
                    successOverlayView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
                } else {
                    mainContentView
                        .transition(.opacity)
                }
            }
            .navigationTitle("cash_payment".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(for: appLanguage)) { dismiss() }
                        .foregroundColor(.textSecondary)
                        .disabled(isProcessing)
                }
            }
        }
        .apColorScheme()
    }
    
    private var mainContentView: some View {
        VStack(spacing: APSpacing.md) {
            // Amount due cards
            HStack(spacing: APSpacing.sm) {
                // Total Due Card
                VStack(spacing: 4) {
                    Text("total_due".localized(for: appLanguage))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    
                    Text(String(format: "฿%.2f", totalAmount))
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundStyle(APGradient.accent)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                
                // Change Due Card
                VStack(spacing: 4) {
                    if isAmountSufficient {
                        Text("change_due".localized(for: appLanguage))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        
                        Text(String(format: "฿%.2f", changeDue))
                            .font(.title3)
                            .fontWeight(.black)
                            .foregroundColor(.appTeal)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: changeDue)
                    } else {
                        let missingAmount = totalAmount - cashReceived
                        Text("missing".localized(for: appLanguage))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        
                        Text(String(format: "฿%.2f", missingAmount))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.appRose)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: missingAmount)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isAmountSufficient ? Color.appTeal.opacity(0.08) : Color.appRose.opacity(0.08))
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(isAmountSufficient ? Color.appTeal.opacity(0.3) : Color.appRose.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Cash Received Display Card
            HStack {
                Text("฿")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Text(cashReceivedText.isEmpty ? "0" : cashReceivedText)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(cashReceivedText.isEmpty ? .textTertiary : .textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: cashReceivedText)
                
                if !cashReceivedText.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                            cashReceivedText = ""
                        }
                        APHaptic.trigger()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                            .font(.system(size: 18))
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.appSurface)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            
            // Quick Cash Shortcuts
            HStack(spacing: APSpacing.xs) {
                quickCashButton(label: "exact".localized(for: appLanguage), amountValue: totalAmount)
                quickCashButton(label: "฿100", amountValue: 100.0)
                quickCashButton(label: "฿500", amountValue: 500.0)
                quickCashButton(label: "฿1,000", amountValue: 1000.0)
            }
            
            // Keypad grid
            keypadGrid
            
            Spacer()
            
            // Confirm CTA
            Button(action: startCheckoutDelay) {
                Label("confirm_payment".localized(for: appLanguage), systemImage: "checkmark.circle.fill")
                    .apGradientButton(
                        gradient: isAmountSufficient ? APGradient.positive : LinearGradient(colors: [Color.appSurface], startPoint: .leading, endPoint: .trailing),
                        shadow: APShadow.positiveGlow,
                        disabled: !isAmountSufficient
                    )
            }
            .disabled(!isAmountSufficient)
        }
        .padding(APSpacing.md)
    }
    
    private func quickCashButton(label: String, amountValue: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                if label == "exact".localized(for: appLanguage) || label.contains("Exact") {
                    cashReceivedText = formatAmountNoCent(amountValue)
                } else {
                    cashReceivedText = String(format: "%.0f", amountValue)
                }
            }
            APHaptic.trigger()
        }) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.appSurfaceHigh)
                .foregroundColor(.textPrimary)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var keypadGrid: some View {
        VStack(spacing: 8) {
            let keys = [
                ["7", "8", "9"],
                ["4", "5", "6"],
                ["1", "2", "3"],
                [".", "0", "⌫"]
            ]
            
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            handleKeypadInput(key)
                        }) {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left.fill")
                                        .font(.title2)
                                        .foregroundColor(.appRose)
                                } else {
                                    Text(key)
                                        .font(.title2).fontWeight(.bold)
                                        .foregroundColor(key == "." ? .textSecondary : .textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(APRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.sm)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var successOverlayView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.appTeal.opacity(0.10),
                    Color.appBackground,
                    Color.appAccent.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: APSpacing.lg) {
                AnimatedPaymentSuccessMark()

                VStack(spacing: APSpacing.xs) {
                    Text("payment_successful_title".localized(for: appLanguage))
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("cash".localized(for: appLanguage) + ": ฿\(String(format: "%.2f", cashReceived))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.textSecondary)
                }

                if changeDue > 0 {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.left.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.appTeal)
                            Text("change_due".localized(for: appLanguage))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.textSecondary)
                        }

                        Text(String(format: "฿%.2f", changeDue))
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.appTeal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.appSurface.opacity(0.94))
                            .shadow(color: Color.appTeal.opacity(0.18), radius: 22, x: 0, y: 14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.appTeal.opacity(0.28), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                }

                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.appTeal)
                        .scaleEffect(0.78)
                    Text("finalizing_payment".localized(for: appLanguage))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.appSurface.opacity(0.78))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }
}

private struct AnimatedPaymentSuccessMark: View {
    @State private var started = false

    private let particleAngles: [Double] = [0, 38, 82, 132, 185, 232, 286, 326]

    var body: some View {
        ZStack {
            ForEach(Array(particleAngles.enumerated()), id: \.offset) { index, angle in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.appTeal : Color.appAccent)
                    .frame(width: index.isMultiple(of: 3) ? 8 : 6, height: index.isMultiple(of: 3) ? 8 : 6)
                    .offset(x: started ? CGFloat(cos(angle * .pi / 180) * 78) : 0,
                            y: started ? CGFloat(sin(angle * .pi / 180) * 78) : 0)
                    .scaleEffect(started ? 0.9 : 0.1)
                    .opacity(started ? 0.0 : 0.95)
                    .animation(.easeOut(duration: 0.9).delay(0.18 + Double(index) * 0.025), value: started)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.appTeal.opacity(0.20), Color.appAccent.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 138, height: 138)
                .scaleEffect(started ? 1.08 : 0.76)
                .shadow(color: Color.appTeal.opacity(started ? 0.24 : 0.05), radius: started ? 28 : 8, x: 0, y: 16)
                .animation(.spring(response: 0.62, dampingFraction: 0.62).delay(0.02), value: started)

            Circle()
                .trim(from: 0, to: started ? 1 : 0)
                .stroke(
                    AngularGradient(colors: [.appTeal, .appAccent, .appTeal], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 126, height: 126)
                .rotationEffect(.degrees(started ? 360 : -72))
                .animation(.spring(response: 0.82, dampingFraction: 0.78).delay(0.08), value: started)

            Circle()
                .fill(Color.appSurface)
                .frame(width: 94, height: 94)
                .overlay(
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(APGradient.accent)
                        .offset(y: started ? -18 : 0)
                        .opacity(started ? 0 : 1)
                        .animation(.easeInOut(duration: 0.28).delay(0.34), value: started)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundColor(.appTeal)
                        .scaleEffect(started ? 1 : 0.2)
                        .opacity(started ? 1 : 0)
                        .animation(.interpolatingSpring(stiffness: 220, damping: 13).delay(0.48), value: started)
                )
        }
        .frame(width: 178, height: 178)
        .onAppear {
            started = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                started = true
            }
        }
    }
}

// MARK: - Staff QR Payment Modal View

struct StaffQRPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var progressStatus = "waiting" // "waiting", "success"
    
    private var promptPayNumber: String {
        NetworkService.shared.promptPayNumber
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: APSpacing.lg) {
                    
                    if promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: APSpacing.md) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.appAmber)
                                .padding()
                            
                            Text("PromptPay Not Configured")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            
                            Text("Please specify your PromptPay number in Store Settings on iPad first.")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                    } else {
                        // QR Content Card
                        VStack(spacing: APSpacing.md) {
                            let payload = generatePromptPayPayload(target: promptPayNumber, amount: totalAmount)
                            if let qrImage = generateQRCode(from: payload) {
                                Image(uiImage: qrImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 160, height: 160)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: .black.opacity(0.1), radius: 8)
                            } else {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 120, weight: .light))
                                    .foregroundColor(.textPrimary)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: .black.opacity(0.1), radius: 8)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Scan PromptPay QR Code to pay")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                
                                Text("PromptPay ID: \(promptPayNumber)")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .fontWeight(.bold)
                            }
                            
                            Text(String(format: "฿%.2f", totalAmount))
                                .font(.title2).fontWeight(.black)
                                .foregroundStyle(APGradient.accent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                    }
                    
                    // Status Bar
                    HStack(spacing: APSpacing.sm) {
                        if progressStatus == "waiting" {
                            if promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Awaiting configuration...")
                                    .font(.footnote)
                                    .foregroundColor(.appAmber)
                            } else {
                                ProgressView()
                                    .tint(.appAmber)
                                Text("Waiting for scan...")
                                    .font(.footnote)
                                    .foregroundColor(.appAmber)
                            }
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.appTeal)
                            Text("Payment confirmed successfully!")
                                .font(.footnote).fontWeight(.bold)
                                .foregroundColor(.appTeal)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(progressStatus == "waiting" ? Color.appAmber.opacity(0.08) : Color.appTeal.opacity(0.08))
                    .cornerRadius(APRadius.md)
                    
                    Spacer()
                    
                    // CTA Button
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Label(progressStatus == "waiting" ? "Force Confirm" : "Confirm & Close", systemImage: "checkmark.circle.fill")
                            .apGradientButton(
                                gradient: progressStatus == "success" ? APGradient.positive : APGradient.accent,
                                shadow: progressStatus == "success" ? APShadow.positiveGlow : APShadow.glow,
                                disabled: promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progressStatus == "waiting"
                            )
                    }
                    .disabled(promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progressStatus == "waiting")
                }
                .padding(APSpacing.md)
            }
            .navigationTitle("PromptPay QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(for: appLanguage)) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                if !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            progressStatus = "success"
                            APHaptic.trigger()
                        }
                    }
                }
            }
        }
        .apColorScheme()
    }
    
    // MARK: - PromptPay QR Code Generation Helpers
    
    private func generatePromptPayPayload(target: String, amount: Double) -> String {
        let sanitized = target.replacingOccurrences(of: " ", with: "")
                              .replacingOccurrences(of: "-", with: "")
        
        var accountInfo = "0016A000000677010111"
        
        if sanitized.count == 13 {
            accountInfo += "0213\(sanitized)"
        } else {
            var phone = sanitized
            if phone.hasPrefix("0") {
                phone.removeFirst()
            }
            let phoneFormatted = "0066" + phone
            accountInfo += "0113\(phoneFormatted)"
        }
        
        var payload = "000201010212"
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764"
        
        let amtStr = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amtStr.count, amtStr)
        
        payload += "5802TH"
        payload += "6304"
        
        let crc = crc16(payload)
        payload += String(format: "%04X", crc)
        
        return payload
    }
    
    private func crc16(_ dataString: String) -> UInt16 {
        let bytes = Array(dataString.utf8)
        var crc: UInt16 = 0xFFFF
        let polynomial: UInt16 = 0x1021
        
        for byte in bytes {
            for i in 0..<8 {
                let bit = ((byte >> (7 - i)) & 1) == 1
                let c15 = ((crc >> 15) & 1) == 1
                crc <<= 1
                if c15 != bit {
                    crc ^= polynomial
                }
            }
        }
        return crc
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Staff Credit Card Payment Modal View

struct StaffCreditCardPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var step = 1 // 1: Connecting, 2: Insert Card, 3: Processing, 4: Authorized
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: APSpacing.lg) {
                    // Info Card
                    VStack(spacing: 8) {
                        Text("Card Total")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "฿%.2f", totalAmount))
                            .font(.title2).fontWeight(.black)
                            .foregroundStyle(APGradient.accent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    
                    // Terminal Simulator Screen
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 64))
                            .foregroundColor(step == 4 ? .appTeal : .appAccent)
                        
                        VStack(spacing: 4) {
                            switch step {
                            case 1:
                                ProgressView()
                                    .tint(.appAccent)
                                    .padding(.bottom, 4)
                                Text("Connecting to Payment Terminal...")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("Please wait while establishing connection")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            case 2:
                                Text("Please Tap, Insert, or Swipe Card")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("EDC Terminal is ready")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            case 3:
                                ProgressView()
                                    .tint(.appAccent)
                                    .padding(.bottom, 4)
                                Text("Authorizing Transaction...")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("Processing payment request")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            default:
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .foregroundColor(.appTeal)
                                Text("Transaction Approved")
                                    .font(.headline).fontWeight(.bold)
                                    .foregroundColor(.appTeal)
                                Text("Payment completed successfully")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    // Complete Button
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Label(step == 4 ? "Finish & Confirm" : "Skip EDC Simulation", systemImage: "checkmark.circle.fill")
                            .apGradientButton(
                                gradient: step == 4 ? APGradient.positive : APGradient.accent,
                                shadow: step == 4 ? APShadow.positiveGlow : APShadow.glow
                            )
                    }
                }
                .padding(APSpacing.md)
            }
            .navigationTitle("Card Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(for: appLanguage)) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { step = 2 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { step = 3 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    withAnimation {
                        step = 4
                        APHaptic.trigger()
                    }
                }
            }
        }
        .apColorScheme()
    }
}
