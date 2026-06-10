import SwiftUI

struct BillingView: View {
    let table: RestaurantTable
    let orders: [Order]
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var selectedMethod = "cash" // "cash", "qr", "card"
    
    // Cash payment calculator states
    @State private var cashReceived = ""
    @State private var paymentProcessing = false
    @State private var paymentSuccess = false
    @State private var showingCashModal = false
    
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
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            if paymentSuccess {
                successState
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            // Order items checklist
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("billing_summary".localized(for: appLanguage))
                                    .font(.headline).fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
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
                            
                            // Financial Details
                            VStack(spacing: APSpacing.sm) {
                                receiptRow(label: "subtotal".localized(for: appLanguage), value: subtotal)
                                receiptRow(label: "vat_label".localized(for: appLanguage), value: tax)
                                receiptRow(label: "service_charge_label".localized(for: appLanguage), value: serviceCharge)
                                
                                Divider().background(Color.appDivider).padding(.vertical, 4)
                                
                                HStack {
                                    Text("grand_total".localized(for: appLanguage))
                                        .font(.title3).fontWeight(.black)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Text("฿\(Int(grandTotal))")
                                        .font(.title3).fontWeight(.black)
                                        .foregroundColor(.appRose)
                                }
                            }
                            .apCard()
                            
                            // Payment selector
                            VStack(alignment: .leading, spacing: APSpacing.md) {
                                Text("select_payment_method".localized(for: appLanguage))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.textSecondary)
                                
                                HStack(spacing: APSpacing.sm) {
                                    paymentMethodButton(id: "cash", label: "cash".localized(for: appLanguage), icon: "banknote.fill")
                                    paymentMethodButton(id: "qr", label: "PromptPay", icon: "qrcode")
                                    paymentMethodButton(id: "card", label: "credit_card".localized(for: appLanguage), icon: "creditcard.fill")
                                }
                            }
                            .padding(.vertical, APSpacing.sm)
                            
                            // Selected payment options
                            if selectedMethod == "cash" {
                                cashCalculatorView
                            } else if selectedMethod == "qr" {
                                qrSimulateView
                            } else {
                                cardSimulateView
                            }
                        }
                        .padding()
                    }
                    
                    // Checkout Button
                    if selectedMethod != "cash" {
                        Button(action: {
                            processCheckout()
                        }) {
                            if paymentProcessing {
                                ProgressView().tint(.white)
                            } else {
                                Label("confirm_payment".localized(for: appLanguage), systemImage: "checkmark.circle.fill")
                                    .apGradientButton(gradient: APGradient.positive)
                            }
                        }
                        .padding()
                        .background(Color.appSurface)
                        .disabled(paymentProcessing)
                    }
                }
            }
        }
        .navigationTitle("checkout_title".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCashModal) {
            StaffCashPaymentModalView(totalAmount: grandTotal) { received in
                self.cashReceived = String(format: "%.2f", received)
                self.processCheckout()
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
    
    private func paymentMethodButton(id: String, label: String, icon: String) -> some View {
        let selected = selectedMethod == id
        return Button(action: {
            APHaptic.trigger()
            selectedMethod = id
            if id == "cash" {
                showingCashModal = true
            }
        }) {
            VStack(spacing: APSpacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption).fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, APSpacing.md)
            .background(selected ? APGradient.accent : LinearGradient(colors: [Color.appSurface], startPoint: .top, endPoint: .bottom))
            .foregroundColor(selected ? .white : .textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(selected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Cash Calculator
    
    private var cashCalculatorView: some View {
        VStack(spacing: APSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("cash_payment".localized(for: appLanguage))
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("cash_payment_sub".localized(for: appLanguage))
                        .font(.caption).foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "banknote.fill")
                    .font(.title)
                    .foregroundColor(.appTeal)
            }
            .padding()
            .apCard()
            
            Button(action: {
                showingCashModal = true
            }) {
                Label("open_cash_terminal".localized(for: appLanguage), systemImage: "keyboard")
                    .apGradientButton(gradient: APGradient.accent)
            }
        }
    }
    
    // MARK: - QR Simulation
    
    private var qrSimulateView: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "qrcode")
                .font(.system(size: 140))
                .foregroundColor(.textPrimary)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                .shadow(radius: 6)
            
            Text("scan_promptpay_sub".localized(for: appLanguage))
                .font(.caption).foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .apCard()
    }
    
    // MARK: - Card Simulation
    
    private var cardSimulateView: some View {
        VStack(spacing: APSpacing.md) {
            HStack {
                Image(systemName: "creditcard.and.123")
                    .font(.title).foregroundColor(.appAccent)
                Spacer()
                Text("emv_simulator".localized(for: appLanguage))
                    .font(.caption).foregroundColor(.textSecondary)
            }
            
            Text("emv_instruction".localized(for: appLanguage))
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical)
        }
        .padding()
        .apCard()
    }
    
    // MARK: - Checkout flow logic
    
    private func processCheckout() {
        paymentProcessing = true
        
        Task {
            do {
                // Submit payments for orders, using transactional RPC for the last one to close session atomically
                for (index, order) in orders.enumerated() {
                    let isLast = index == orders.count - 1
                    if isLast {
                        _ = try await NetworkService.shared.completeCheckout(
                            paymentId: UUID(),
                            orderId: order.id,
                            amount: order.total,
                            method: selectedMethod,
                            tableNumber: table.tableNumber
                        )
                    } else {
                        _ = try await NetworkService.shared.uploadPayment(
                            orderId: order.id,
                            amount: order.total,
                            method: selectedMethod
                        )
                    }
                }
                
                await MainActor.run {
                    paymentProcessing = false
                    paymentSuccess = true
                    APHaptic.trigger()
                }
            } catch {
                await MainActor.run {
                    paymentProcessing = false
                }
            }
        }
    }

    
    // MARK: - Transaction success state
    
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
        APHaptic.trigger()
        
        if changeDue == 0.0 {
            // Exact change: no delay, confirm immediately
            onConfirm(cashReceived)
            dismiss()
        } else {
            // Show success screen and hold for 3 seconds
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSuccessOverlay = true
            }
            
            Task {
                for _ in 0..<3 {
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
        VStack(spacing: APSpacing.lg) {
            Spacer()
            
            // Checkmark Animation
            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(Color.appTeal, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .scaleEffect(isProcessing ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isProcessing)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.appTeal)
            }
            
            VStack(spacing: APSpacing.xs) {
                Text("payment_successful_title".localized(for: appLanguage))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                Text("cash".localized(for: appLanguage) + ": ฿\(String(format: "%.2f", cashReceived))")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            // Large Change Due Box
            if changeDue > 0 {
                VStack(spacing: 6) {
                    Text("change_due".localized(for: appLanguage))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    
                    Text(String(format: "฿%.2f", changeDue))
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(.appTeal)
                        .shadow(color: Color.appTeal.opacity(0.2), radius: 10, x: 0, y: 5)
                        .scaleEffect(1.05)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .background(Color.appTeal.opacity(0.08))
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appTeal.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Loading/Countdown indicator
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.textSecondary)
                Text(String(format: "closing_in_seconds_format".localized(for: appLanguage), delayRemaining))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(APSpacing.md)
    }
}
