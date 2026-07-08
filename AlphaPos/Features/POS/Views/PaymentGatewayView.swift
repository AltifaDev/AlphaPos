// PaymentGatewayView.swift
// AlphaPos — Enterprise Payment Gateway Management
// Manages all payment methods, gateway integrations, and transaction settings.

import SwiftUI
import SwiftData

/// Payment Gateway Management for Enterprise POS.
///
/// Features:
/// - Manage active payment methods (cash, card, QR, e-wallet, etc.)
/// - Connect/configure payment gateways (Omise, 2C2P, Stripe, Kasikorn QR)
/// - Transaction fee display & reporting
/// - Test mode toggle
/// - Payment method ordering (drag-and-drop priority)
/// - Per-branch payment method enable/disable
struct PaymentGatewayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("payment_test_mode") private var paymentTestMode = false
    @AppStorage("app_currency_symbol") private var currencySymbol = "฿"
    @AppStorage("promptpay_number") private var promptPayNumber = ""

    @AppStorage("payment_method_cash_enabled") private var cashEnabled = true
    @AppStorage("payment_method_card_enabled") private var cardEnabled = true
    @AppStorage("payment_method_qr_enabled") private var qrEnabled = true
    @AppStorage("payment_method_truemoney_enabled") private var trueMoneyEnabled = true
    @AppStorage("payment_method_linepay_enabled") private var linePayEnabled = false
    @AppStorage("payment_method_grabpay_enabled") private var grabPayEnabled = false

    @Query(sort: \Payment.paidAt, order: .reverse) private var recentPayments: [Payment]

    @State private var selectedSection: PaymentSection = .methods
    @State private var showAddGateway = false
    @State private var showGatewayDetail: GatewayProvider? = nil

    enum PaymentSection: String, CaseIterable, Identifiable {
        case methods = "Payment Methods"
        case gateways = "Gateways"
        case transactions = "Transactions"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .methods: return "creditcard.fill"
            case .gateways: return "link.circle.fill"
            case .transactions: return "list.bullet.rectangle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    // MARK: - Gateway Providers

    enum GatewayProvider: String, CaseIterable, Identifiable {
        case omise = "Omise"
        case twoCTwoP = "2C2P"
        case stripe = "Stripe"
        case kasikornQR = "KBank QR"
        case scbQR = "SCB QR"
        case promptpay = "PromptPay"
        case trueMoney = "TrueMoney"
        case linePay = "LINE Pay"
        case grabPay = "GrabPay"
        case shopeePayLater = "ShopeePay"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .omise: return "building.columns.fill"
            case .twoCTwoP: return "globe.asia.australia.fill"
            case .stripe: return "globe.americas.fill"
            case .kasikornQR: return "qrcode"
            case .scbQR: return "qrcode.viewfinder"
            case .promptpay: return "banknote.fill"
            case .trueMoney: return "wallet.pass.fill"
            case .linePay: return "message.fill"
            case .grabPay: return "car.fill"
            case .shopeePayLater: return "bag.fill"
            }
        }

        var color: Color {
            switch self {
            case .omise: return Color(hex: "1A56DB")
            case .twoCTwoP: return Color(hex: "E11D48")
            case .stripe: return Color(hex: "635BFF")
            case .kasikornQR: return Color(hex: "00A651")
            case .scbQR: return Color(hex: "4E2D87")
            case .promptpay: return Color(hex: "003B71")
            case .trueMoney: return Color(hex: "F97316")
            case .linePay: return Color(hex: "00B900")
            case .grabPay: return Color(hex: "00B14F")
            case .shopeePayLater: return Color(hex: "EE4D2D")
            }
        }

        var category: PaymentCategory {
            switch self {
            case .omise, .twoCTwoP, .stripe: return .cardGateway
            case .kasikornQR, .scbQR, .promptpay: return .qrPayment
            case .trueMoney, .linePay, .grabPay, .shopeePayLater: return .eWallet
            }
        }

        var feeDescription: String {
            switch self {
            case .omise: return "3.65% + ฿0"
            case .twoCTwoP: return "3.5% + ฿5"
            case .stripe: return "3.6% + ฿10"
            case .kasikornQR: return "0.0% (PromptPay) / 0.6% (QR)"
            case .scbQR: return "0.0% (PromptPay)"
            case .promptpay: return "0.0%"
            case .trueMoney: return "1.5%"
            case .linePay: return "2.0%"
            case .grabPay: return "2.5%"
            case .shopeePayLater: return "3.0%"
            }
        }
    }

    enum PaymentCategory: String, CaseIterable {
        case cardGateway = "Card Gateways"
        case qrPayment = "QR Payments"
        case eWallet = "E-Wallets"
    }


    var body: some View {
        HStack(spacing: 0) {
            // Left nav
            sectionNav
                .frame(width: 200)

            Divider().background(Color.appDivider)

            // Content
            mainContent
                .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showAddGateway) {
            AddGatewaySheet(onSelect: { provider in
                showGatewayDetail = provider
                showAddGateway = false
            })
        }
        .sheet(item: $showGatewayDetail) { provider in
            GatewayConfigSheet(provider: provider)
        }
    }

    // MARK: - Section Nav

    private var sectionNav: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "10B981").opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "10B981"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("payment_gateway_title".t)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(paymentTestMode ? "payment_test_mode".t : "payment_live_mode".t)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(paymentTestMode ? .orange : .green)
                }
            }
            .padding()

            Divider().background(Color.appDivider).padding(.horizontal)

            // Sections
            ForEach(PaymentSection.allCases) { section in
                Button {
                    withAnimation { selectedSection = section }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 13))
                            .foregroundColor(selectedSection == section ? .appAccent : .textSecondary)
                            .frame(width: 22)
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))
                            .foregroundColor(selectedSection == section ? .textPrimary : .textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(selectedSection == section ? Color.appAccent.opacity(0.08) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            // Stats summary
            paymentStatsWidget
        }
        .background(Color.appSurface)
    }

    // MARK: - Stats Widget

    private var paymentStatsWidget: some View {
        let todayPayments = recentPayments.filter {
            Calendar.current.isDateInToday($0.paidAt) && $0.status == "completed"
        }
        let todayTotal = todayPayments.reduce(0.0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10))
                    .foregroundColor(.appAccent)
                Text("payment_today_stats".t)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(todayPayments.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("payment_txns".t)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(currencySymbol)\(todayTotal.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("payment_volume".t)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(10)
        .background(Color.appSurfaceHigh)
        .cornerRadius(10)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedSection {
                case .methods:
                    paymentMethodsSection
                case .gateways:
                    gatewaysSection
                case .transactions:
                    transactionsSection
                case .settings:
                    settingsSection
                }
            }
            .padding(24)
        }
    }

    // MARK: - Payment Methods Section

    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("payment_methods_title".t)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text("payment_methods_desc".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }

            paymentMethodRow(name: "Cash", subtitle: "payment_cash_desc".t, icon: "banknote.fill", color: Color(hex: "10B981"), fee: "0%", isEnabled: $cashEnabled)
            paymentMethodRow(name: "Credit/Debit Card", subtitle: "payment_card_desc".t, icon: "creditcard.fill", color: Color(hex: "3B82F6"), fee: "3.65%", isEnabled: $cardEnabled)
            paymentMethodRow(name: "PromptPay QR", subtitle: "payment_promptpay_desc".t, icon: "qrcode", color: Color(hex: "003B71"), fee: "0%", isEnabled: $qrEnabled)
            paymentMethodRow(name: "TrueMoney Wallet", subtitle: "payment_truemoney_desc".t, icon: "wallet.pass.fill", color: Color(hex: "F97316"), fee: "1.5%", isEnabled: $trueMoneyEnabled)
            paymentMethodRow(name: "LINE Pay", subtitle: "payment_linepay_desc".t, icon: "message.fill", color: Color(hex: "00B900"), fee: "2.0%", isEnabled: $linePayEnabled)
            paymentMethodRow(name: "GrabPay", subtitle: "payment_grabpay_desc".t, icon: "car.fill", color: Color(hex: "00B14F"), fee: "2.5%", isEnabled: $grabPayEnabled)
        }
    }

    private func paymentMethodRow(name: String, subtitle: String, icon: String, color: Color, fee: String, isEnabled: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            // Fee
            if !fee.isEmpty {
                Text(fee)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(6)
            }

            // Toggle
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .tint(.appAccent)
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEnabled.wrappedValue ? color.opacity(0.2) : Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Gateways Section

    private var gatewaysSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("payment_gateways_title".t)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text("payment_gateways_desc".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    showAddGateway = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("payment_add_gateway".t)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Group by category
            ForEach(PaymentCategory.allCases, id: \.rawValue) { category in
                let providers = GatewayProvider.allCases.filter { $0.category == category }

                VStack(alignment: .leading, spacing: 10) {
                    Text(category.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(providers) { provider in
                            gatewayCard(provider)
                        }
                    }
                }
            }
        }
    }

    private func gatewayCard(_ provider: GatewayProvider) -> some View {
        Button {
            showGatewayDetail = provider
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(provider.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: provider.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(provider.color)
                }

                Text(provider.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text(provider.feeDescription)
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)

                // Connection status
                HStack(spacing: 4) {
                    Circle()
                        .fill(isGatewayConnected(provider) ? Color.green : Color(hex: "9CA3AF"))
                        .frame(width: 6, height: 6)
                    Text(isGatewayConnected(provider) ? "payment_connected".t : "payment_not_connected".t)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isGatewayConnected(provider) ? .green : .textTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isGatewayConnected(provider) ? provider.color.opacity(0.3) : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transactions Section

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("payment_transactions_title".t)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)
                Spacer()

                // Summary
                HStack(spacing: 12) {
                    transactionStat(label: "payment_completed".t, count: completedPayments.count, color: .green)
                    transactionStat(label: "payment_failed".t, count: failedPayments.count, color: .red)
                    transactionStat(label: "payment_refunded".t, count: refundedPayments.count, color: .orange)
                }
            }

            // Transaction list
            if recentPayments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(.textTertiary)
                    Text("payment_no_transactions".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(Array(recentPayments.prefix(20).enumerated()), id: \.offset) { _, payment in
                    transactionRow(payment)
                }
            }
        }
    }

    private func transactionStat(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)").font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 10)).foregroundColor(.textSecondary)
        }
    }

    private func transactionRow(_ payment: Payment) -> some View {
        HStack(spacing: 12) {
            // Method icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(methodColor(payment.paymentMethod).opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: methodIcon(payment.paymentMethod))
                    .font(.system(size: 14))
                    .foregroundColor(methodColor(payment.paymentMethod))
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(methodDisplayName(payment.paymentMethod))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                    statusBadge(payment.status)
                }
                HStack(spacing: 4) {
                    if let ref = payment.transactionReference, !ref.isEmpty {
                        Text(ref)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                    Text(payment.paidAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currencySymbol)\(payment.amount.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(payment.status == "refunded" ? .orange : .textPrimary)
                if payment.tipAmount > 0 {
                    Text("+ tip \(currencySymbol)\(payment.tipAmount.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(10)
        .background(Color.appSurface)
        .cornerRadius(10)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "completed": return .green
            case "failed": return .red
            case "refunded": return .orange
            default: return .gray
            }
        }()

        return Text(status.capitalized)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("payment_settings_title".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)

            // Test mode toggle
            settingRow(
                icon: "flask.fill",
                title: "payment_test_mode_title".t,
                subtitle: "payment_test_mode_desc".t,
                color: .orange
            ) {
                Toggle("", isOn: $paymentTestMode)
                    .labelsHidden()
                    .tint(.orange)
            }

            Text("Automatic reconciliation, tipping, and multi-currency settlement require a configured payment provider and are not active in this build.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface)
                .cornerRadius(12)
        }
    }

    private func settingRow(icon: String, title: String, subtitle: String, color: Color, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            Spacer()
            trailing()
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private var completedPayments: [Payment] { recentPayments.filter { $0.status == "completed" } }
    private var failedPayments: [Payment] { recentPayments.filter { $0.status == "failed" } }
    private var refundedPayments: [Payment] { recentPayments.filter { $0.status == "refunded" } }

    private func isGatewayConnected(_ provider: GatewayProvider) -> Bool {
        provider == .promptpay && !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "cash": return Color(hex: "10B981")
        case "credit_card": return Color(hex: "3B82F6")
        case "qr_promptpay": return Color(hex: "003B71")
        case "true_money": return Color(hex: "F97316")
        default: return .appAccent
        }
    }

    private func methodIcon(_ method: String) -> String {
        switch method {
        case "cash": return "banknote.fill"
        case "credit_card": return "creditcard.fill"
        case "qr_promptpay": return "qrcode"
        case "true_money": return "wallet.pass.fill"
        default: return "creditcard.fill"
        }
    }

    private func methodDisplayName(_ method: String) -> String {
        switch method {
        case "cash": return "Cash"
        case "credit_card": return "Credit/Debit Card"
        case "qr_promptpay": return "PromptPay QR"
        case "true_money": return "TrueMoney"
        default: return method.capitalized
        }
    }
}

// MARK: - Payment Method Config

struct PaymentMethodConfig: Identifiable {
    let id = UUID()
    var name: String
    var subtitle: String
    var icon: String
    var color: Color
    var fee: String
    var isEnabled: Bool
    var methodKey: String

    static var defaults: [PaymentMethodConfig] {
        [
            PaymentMethodConfig(name: "Cash", subtitle: "payment_cash_desc".t, icon: "banknote.fill", color: Color(hex: "10B981"), fee: "0%", isEnabled: true, methodKey: "cash"),
            PaymentMethodConfig(name: "Credit/Debit Card", subtitle: "payment_card_desc".t, icon: "creditcard.fill", color: Color(hex: "3B82F6"), fee: "3.65%", isEnabled: true, methodKey: "credit_card"),
            PaymentMethodConfig(name: "PromptPay QR", subtitle: "payment_promptpay_desc".t, icon: "qrcode", color: Color(hex: "003B71"), fee: "0%", isEnabled: true, methodKey: "qr_promptpay"),
            PaymentMethodConfig(name: "TrueMoney Wallet", subtitle: "payment_truemoney_desc".t, icon: "wallet.pass.fill", color: Color(hex: "F97316"), fee: "1.5%", isEnabled: true, methodKey: "true_money"),
            PaymentMethodConfig(name: "LINE Pay", subtitle: "payment_linepay_desc".t, icon: "message.fill", color: Color(hex: "00B900"), fee: "2.0%", isEnabled: false, methodKey: "line_pay"),
            PaymentMethodConfig(name: "GrabPay", subtitle: "payment_grabpay_desc".t, icon: "car.fill", color: Color(hex: "00B14F"), fee: "2.5%", isEnabled: false, methodKey: "grab_pay"),
        ]
    }
}

// MARK: - Add Gateway Sheet

private struct AddGatewaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PaymentGatewayView.GatewayProvider) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("payment_choose_gateway".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal)

                    ForEach(PaymentGatewayView.PaymentCategory.allCases, id: \.rawValue) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .tracking(1)
                                .padding(.horizontal)

                            ForEach(PaymentGatewayView.GatewayProvider.allCases.filter { $0.category == category }) { provider in
                                Button { onSelect(provider) } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(provider.color.opacity(0.12)).frame(width: 36, height: 36)
                                            Image(systemName: provider.icon).font(.system(size: 14)).foregroundColor(provider.color)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(provider.rawValue).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                                            Text(provider.feeDescription).font(.system(size: 11)).foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textTertiary)
                                    }
                                    .padding(12)
                                    .background(Color.appSurface)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.appBackground)
            .navigationTitle("payment_add_gateway".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Gateway Config Sheet

private struct GatewayConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    let provider: PaymentGatewayView.GatewayProvider

    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var testMode = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Provider header
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(provider.color.opacity(0.12)).frame(width: 50, height: 50)
                            Image(systemName: provider.icon).font(.system(size: 22, weight: .semibold)).foregroundColor(provider.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.rawValue)
                                .font(.title3.weight(.bold))
                                .foregroundColor(.textPrimary)
                            Text("payment_fee".t + ": " + provider.feeDescription)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Divider().background(Color.appDivider)

                    // API Keys
                    VStack(alignment: .leading, spacing: 12) {
                        Text("payment_credentials".t)
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key (Public)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            TextField("pk_test_...", text: $apiKey)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(10)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(8)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secret Key (Private)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            SecureField("sk_test_...", text: $secretKey)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(10)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(8)
                        }
                    }

                    // Test mode
                    Toggle(isOn: $testMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("payment_test_mode_title".t)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text("payment_test_mode_gateway_desc".t)
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .tint(.orange)
                    .padding(14)
                    .background(Color.appSurface)
                    .cornerRadius(12)

                    Label("Provider integration unavailable", systemImage: "link.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(provider.color.opacity(0.35))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(provider.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { dismiss() }
                }
            }
        }
    }
}
