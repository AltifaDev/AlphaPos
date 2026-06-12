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
    @State private var showingQRModal = false
    @State private var showingCardModal = false
    
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
        .sheet(isPresented: $showingQRModal) {
            StaffQRPaymentModalView(totalAmount: grandTotal) {
                self.processCheckout()
            }
        }
        .sheet(isPresented: $showingCardModal) {
            StaffCreditCardPaymentModalView(totalAmount: grandTotal) {
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
            } else if id == "qr" {
                showingQRModal = true
            } else if id == "card" {
                showingCardModal = true
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PromptPay QR")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("scan_promptpay_sub".localized(for: appLanguage))
                        .font(.caption).foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "qrcode")
                    .font(.title)
                    .foregroundColor(.appRose)
            }
            .padding()
            .apCard()
            
            Button(action: {
                showingQRModal = true
            }) {
                Label("Open QR Terminal", systemImage: "qrcode")
                    .apGradientButton(gradient: APGradient.accent)
            }
        }
    }
    
    // MARK: - Card Simulation
    
    private var cardSimulateView: some View {
        VStack(spacing: APSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("credit_card".localized(for: appLanguage))
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("emv_simulator".localized(for: appLanguage))
                        .font(.caption).foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "creditcard.fill")
                    .font(.title)
                    .foregroundColor(.appAccent)
            }
            .padding()
            .apCard()
            
            Button(action: {
                showingCardModal = true
            }) {
                Label("Open Card Reader", systemImage: "creditcard")
                    .apGradientButton(gradient: APGradient.accent)
            }
        }
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
