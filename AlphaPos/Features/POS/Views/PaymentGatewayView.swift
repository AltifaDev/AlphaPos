// PaymentGatewayView.swift
// AlphaPos — Enterprise Payment Gateway Management
// Manages all payment methods, gateway integrations, and transaction settings.

import SwiftUI
import SwiftData
import UIKit
import CoreImage

/// Payment Gateway Management for Enterprise POS.
///
/// Single source of truth for tender enablement (also consumed by POS checkout).
/// Scope today: device-local AppStorage — not yet per-branch.
///
/// Sections:
/// - Methods: enable/disable tenders used at POS
/// - Gateways: third-party processor connections (stubs until integrated)
/// - Transactions: recent completed payments
/// - Settings: sandbox / test mode
struct PaymentGatewayView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("payment_test_mode") private var paymentTestMode = false
    @AppStorage("app_currency_symbol") private var currencySymbol = "฿"
    @AppStorage("promptpay_mode") private var promptPayMode = "direct"
    @AppStorage("promptpay_number") private var promptPayNumber = ""
    @AppStorage("promptpay_account_name") private var promptPayAccountName = ""
    @AppStorage("promptpay_id_type") private var promptPayIdType = "phone"
    @AppStorage("promptpay_lock_amount") private var promptPayLockAmount = true
    @AppStorage("promptpay_api_key") private var promptPayApiKey = ""
    @AppStorage("promptpay_secret_key") private var promptPaySecretKey = ""
    @AppStorage("promptpay_gateway_provider") private var promptPayGatewayProvider = "omise"
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    @AppStorage("payment_method_cash_enabled") private var cashEnabled = true
    @AppStorage("payment_method_card_enabled") private var cardEnabled = true
    @AppStorage("payment_method_qr_enabled") private var qrEnabled = true
    @AppStorage("payment_method_truemoney_enabled") private var trueMoneyEnabled = true
    @AppStorage("payment_method_linepay_enabled") private var linePayEnabled = false
    @AppStorage("payment_method_grabpay_enabled") private var grabPayEnabled = false
    @AppStorage(GovernmentSupportProgram.enabledSettingsKey) private var thaiChuaThaiPlusEnabled = true

    @Query(sort: \Payment.paidAt, order: .reverse) private var recentPayments: [Payment]

    private var branchPayments: [Payment] {
        guard let branchId = UUID(uuidString: activeBranchId) else { return [] }
        return recentPayments.filter { $0.order?.branch.id == branchId }
    }

    @State private var selectedSection: PaymentSection = .methods
    @State private var showAddGateway = false
    @State private var showGatewayDetail: GatewayProvider? = nil

    // Enterprise transaction filters (default = recent window, never unbounded dump)
    @State private var txnDatePreset: TxnDatePreset = .last7Days
    @State private var txnStatusFilter: TxnStatusFilter = .all
    @State private var txnMethodFilter: TxnMethodFilter = .all
    @State private var txnSearchText = ""
    @State private var txnDisplayLimit = 50

    enum TxnDatePreset: String, CaseIterable, Identifiable {
        case today, last7Days, last30Days, thisMonth
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .today: return "payment_txn_range_today"
            case .last7Days: return "payment_txn_range_7d"
            case .last30Days: return "payment_txn_range_30d"
            case .thisMonth: return "payment_txn_range_month"
            }
        }
    }

    enum TxnStatusFilter: String, CaseIterable, Identifiable {
        case all, completed, failed, refunded
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .all: return "payment_txn_status_all"
            case .completed: return "payment_completed"
            case .failed: return "payment_failed"
            case .refunded: return "payment_refunded"
            }
        }
    }

    enum TxnMethodFilter: String, CaseIterable, Identifiable {
        case all, cash, credit_card, qr_promptpay, true_money
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .all: return "payment_txn_method_all"
            case .cash: return "Cash"
            case .credit_card: return "Card"
            case .qr_promptpay: return "PromptPay"
            case .true_money: return "TrueMoney"
            }
        }
        var methodKey: String? {
            self == .all ? nil : rawValue
        }
    }

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
        .navigationTitle("payment_gateway_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddGateway = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("payment_add_gateway".t)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.appAccent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
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
            .padding(.horizontal)
            .padding(.top, 0)
            .padding(.bottom, 12)

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
        let todayPayments = activePayments.filter {
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
            .padding(.horizontal, 24)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Payment Methods Section

    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("payment_methods_title".t)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("payment_methods_desc".t)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                Text("payment_methods_scope_note".t)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            paymentMethodRow(
                name: "Cash",
                subtitle: "payment_cash_desc".t,
                icon: "banknote.fill",
                color: Color(hex: "10B981"),
                isEnabled: $cashEnabled,
                availability: .posActive
            )
            paymentMethodRow(
                name: "Credit/Debit Card",
                subtitle: "payment_card_desc".t,
                icon: "creditcard.fill",
                color: Color(hex: "3B82F6"),
                isEnabled: $cardEnabled,
                availability: .posActive
            )
            paymentMethodRow(
                name: "PromptPay QR",
                subtitle: "payment_promptpay_desc".t,
                icon: "qrcode",
                color: Color(hex: "003B71"),
                isEnabled: $qrEnabled,
                availability: .posActive
            )
            paymentMethodRow(
                name: GovernmentSupportProgram.thaiChuaThaiPlus,
                subtitle: "เปิดเฉพาะร้านที่เข้าร่วมโครงการ · เมื่อปิดจะซ่อนจาก POS และ Dashboard",
                icon: "qrcode.viewfinder",
                color: Color(hex: "1D4ED8"),
                isEnabled: $thaiChuaThaiPlusEnabled,
                availability: .posActive
            )
            paymentMethodRow(
                name: "TrueMoney Wallet",
                subtitle: "payment_truemoney_desc".t,
                icon: "wallet.pass.fill",
                color: Color(hex: "F97316"),
                isEnabled: $trueMoneyEnabled,
                availability: .comingSoon
            )
            paymentMethodRow(
                name: "LINE Pay",
                subtitle: "payment_linepay_desc".t,
                icon: "message.fill",
                color: Color(hex: "00B900"),
                isEnabled: $linePayEnabled,
                availability: .comingSoon
            )
            paymentMethodRow(
                name: "GrabPay",
                subtitle: "payment_grabpay_desc".t,
                icon: "car.fill",
                color: Color(hex: "00B14F"),
                isEnabled: $grabPayEnabled,
                availability: .comingSoon
            )
        }
    }

    private enum TenderAvailability {
        case posActive
        case comingSoon
    }

    private func paymentMethodRow(
        name: String,
        subtitle: String,
        icon: String,
        color: Color,
        isEnabled: Binding<Bool>,
        availability: TenderAvailability
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(availability == .posActive ? "payment_pos_active_badge".t : "payment_coming_soon_badge".t)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(availability == .posActive ? Color(hex: "059669") : .textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (availability == .posActive ? Color(hex: "10B981").opacity(0.15) : Color.appSurfaceHigh)
                        )
                        .clipShape(Capsule())
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .tint(.appAccent)
                .disabled(availability == .comingSoon)
                .opacity(availability == .comingSoon ? 0.55 : 1)
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEnabled.wrappedValue && availability == .posActive ? color.opacity(0.2) : Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var isOfflineMode: Bool {
        OfflineSyncModeController.isEnabled || OfflineSyncModeController.isOfflineSubscriptionPlan
    }

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

            if isOfflineMode {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.slash.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("แพ็กเกจระบบออฟไลน์ (Offline Mode Active)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("ระบบทำงานแบบ Stand-alone 100% ปราศจากการเชื่อมต่อคลาวด์ รองรับการรับชำระผ่าน PromptPay QR Code ล็อกยอดเงินโดยตรงในเครื่อง สำหรับเกตเวย์ภายนอกจะสามารถใช้งานได้ในโหมดออนไลน์เท่านั้น")
                            .font(.system(size: 11.5))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
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
                    Text(gatewayConnectionStatusText(provider))
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
        let filtered = filteredTransactions
        let visible = Array(filtered.prefix(txnDisplayLimit))
        let statusScoped = transactionsInDateRange // status chips reflect date window only

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("payment_transactions_title".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(String(format: "payment_txn_showing".t, visible.count, filtered.count))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                HStack(spacing: 10) {
                    transactionStat(
                        label: "payment_completed".t,
                        count: statusScoped.filter { $0.status == "completed" }.count,
                        color: .green
                    )
                    transactionStat(
                        label: "payment_failed".t,
                        count: statusScoped.filter { $0.status == "failed" }.count,
                        color: .red
                    )
                    transactionStat(
                        label: "payment_refunded".t,
                        count: statusScoped.filter { $0.status == "refunded" }.count,
                        color: .orange
                    )
                }
            }

            transactionFilterBar

            HStack {
                Text("payment_txn_filtered_total".t)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(currencySymbol)\(filteredCompletedTotal.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)

            if activePayments.isEmpty {
                emptyTransactionsState(message: "payment_no_transactions".t)
            } else if filtered.isEmpty {
                emptyTransactionsState(message: "payment_txn_no_match".t)
            } else {
                ForEach(visible, id: \.id) { payment in
                    transactionRow(payment)
                }

                if filtered.count > visible.count {
                    Button {
                        txnDisplayLimit += 50
                        APHaptic.trigger()
                    } label: {
                        Text("payment_txn_load_more".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.appAccent.opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: txnDatePreset) { _, _ in txnDisplayLimit = 50 }
        .onChange(of: txnStatusFilter) { _, _ in txnDisplayLimit = 50 }
        .onChange(of: txnMethodFilter) { _, _ in txnDisplayLimit = 50 }
        .onChange(of: txnSearchText) { _, _ in txnDisplayLimit = 50 }
    }

    private var transactionFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("payment_txn_filter_date".t)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                    ForEach(TxnDatePreset.allCases) { preset in
                        filterChip(
                            title: preset.titleKey.t,
                            selected: txnDatePreset == preset
                        ) {
                            txnDatePreset = preset
                        }
                    }
                }
            }

            // Status + method
            HStack(spacing: 8) {
                Menu {
                    ForEach(TxnStatusFilter.allCases) { status in
                        Button(status.titleKey.t) { txnStatusFilter = status }
                    }
                } label: {
                    filterMenuLabel(
                        title: "payment_txn_filter_status".t,
                        value: txnStatusFilter.titleKey.t
                    )
                }

                Menu {
                    ForEach(TxnMethodFilter.allCases) { method in
                        Button(method.titleKey) { txnMethodFilter = method }
                    }
                } label: {
                    filterMenuLabel(
                        title: "payment_txn_filter_method".t,
                        value: txnMethodFilter == .all ? "payment_txn_method_all".t : txnMethodFilter.titleKey
                    )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                TextField("payment_txn_search_placeholder".t, text: $txnSearchText)
                    .font(.system(size: 12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !txnSearchText.isEmpty {
                    Button {
                        txnSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
        }
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.appAccent : Color.appSurfaceHigh)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func filterMenuLabel(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appSurfaceHigh)
        .cornerRadius(8)
    }

    private func emptyTransactionsState(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.textTertiary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func transactionStat(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)").font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 12)).foregroundColor(.textSecondary)
        }
    }

    private func transactionRow(_ payment: Payment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(methodColor(payment.paymentMethod).opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: methodIcon(payment.paymentMethod))
                    .font(.system(size: 14))
                    .foregroundColor(methodColor(payment.paymentMethod))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(methodDisplayName(payment.paymentMethod))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    statusBadge(payment.status)
                }
                HStack(spacing: 4) {
                    if let ref = payment.transactionReference, !ref.isEmpty {
                        Text(ref)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                    Text(payment.paidAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currencySymbol)\(payment.amount.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(payment.status == "refunded" ? .orange : .textPrimary)
                if payment.tipAmount > 0 {
                    Text("+ tip \(currencySymbol)\(payment.tipAmount.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 12))
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
        let label: String = {
            switch status {
            case "completed": return "payment_completed".t
            case "failed": return "payment_failed".t
            case "refunded": return "payment_refunded".t
            default: return status.capitalized
            }
        }()

        return Text(label)
            .font(.system(size: 10, weight: .bold))
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

    /// Soft-deleted rows excluded (enterprise ledger hygiene).
    private var activePayments: [Payment] {
        branchPayments.filter { !$0.isDeleted }
    }

    private var txnDateInterval: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch txnDatePreset {
        case .today:
            let start = cal.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: now)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: now)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        }
    }

    /// Date-windowed set used for status summary chips.
    private var transactionsInDateRange: [Payment] {
        let interval = txnDateInterval
        return activePayments.filter { interval.contains($0.paidAt) }
    }

    /// Full enterprise filter pipeline: date → status → method → search.
    private var filteredTransactions: [Payment] {
        let query = txnSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return transactionsInDateRange.filter { payment in
            if txnStatusFilter != .all, payment.status != txnStatusFilter.rawValue {
                return false
            }
            if let method = txnMethodFilter.methodKey, payment.paymentMethod != method {
                return false
            }
            if !query.isEmpty {
                let ref = (payment.transactionReference ?? "").lowercased()
                let method = payment.paymentMethod.lowercased()
                if !ref.contains(query) && !method.contains(query) {
                    return false
                }
            }
            return true
        }
    }

    private var filteredCompletedTotal: Double {
        filteredTransactions
            .filter { $0.status == "completed" }
            .reduce(0) { $0 + $1.amount }
    }

    private var completedPayments: [Payment] { activePayments.filter { $0.status == "completed" } }
    private var failedPayments: [Payment] { activePayments.filter { $0.status == "failed" } }
    private var refundedPayments: [Payment] { activePayments.filter { $0.status == "refunded" } }

    private func isGatewayConnected(_ provider: GatewayProvider) -> Bool {
        if isOfflineMode {
            // In offline mode, only direct PromptPay is allowed
            if provider == .promptpay {
                return !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
        if provider == .promptpay {
            if promptPayMode == "api" {
                return !promptPayApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else {
                return !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        return false
    }

    private func gatewayConnectionStatusText(_ provider: GatewayProvider) -> String {
        if isOfflineMode && provider != .promptpay {
            return "โหมดออนไลน์เท่านั้น"
        }
        if isGatewayConnected(provider) {
            if provider == .promptpay {
                return (promptPayMode == "api" && !isOfflineMode) ? "เชื่อมต่อ API แล้ว" : "พร้อมเพย์ตรง (ล็อกยอด)"
            }
            return "payment_connected".t
        } else {
            return "payment_not_connected".t
        }
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
    let provider: PaymentGatewayView.GatewayProvider

    var body: some View {
        if provider == .promptpay {
            PromptPayGatewayConfigView()
        } else {
            GenericGatewayConfigView(provider: provider)
        }
    }
}

// MARK: - PromptPay Dual-Mode Configuration View

struct PromptPayGatewayConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("promptpay_mode") private var promptPayMode = "direct"
    @AppStorage("promptpay_number") private var promptPayNumber = ""
    @AppStorage("promptpay_account_name") private var promptPayAccountName = ""
    @AppStorage("promptpay_id_type") private var promptPayIdType = "phone"
    @AppStorage("promptpay_lock_amount") private var promptPayLockAmount = true
    @AppStorage("promptpay_api_key") private var promptPayApiKey = ""
    @AppStorage("promptpay_secret_key") private var promptPaySecretKey = ""
    @AppStorage("promptpay_gateway_provider") private var promptPayGatewayProvider = "omise"
    @AppStorage("payment_test_mode") private var paymentTestMode = false
    @AppStorage("store_name") private var storeName = ""

    @State private var selectedMode: String = "direct"
    @State private var idType: String = "phone"
    @State private var ppNumber: String = ""
    @State private var accountName: String = ""
    @State private var lockAmount: Bool = true
    @State private var apiKey: String = ""
    @State private var secretKey: String = ""
    @State private var gatewayProvider: String = "omise"
    @State private var testMode: Bool = false
    @State private var isSaved: Bool = false

    private let gatewayOptions = [
        ("omise", "Opn Payments (Omise)"),
        ("stripe", "Stripe"),
        ("gbprimepay", "GB Prime Pay"),
        ("2c2p", "2C2P"),
        ("kbank", "KBank Open API"),
        ("scb", "SCB Open API")
    ]

    private var isOfflineMode: Bool {
        OfflineSyncModeController.isEnabled || OfflineSyncModeController.isOfflineSubscriptionPlan
    }

    private var idTypeTitle: String {
        switch idType {
        case "national_id": return "เลขประจำตัวประชาชน (13 หลัก)"
        case "tax_id": return "เลขประจำตัวผู้เสียภาษี / e-Wallet (13-15 หลัก)"
        default: return "เบอร์โทรศัพท์มือถือที่ผูกพร้อมเพย์ (10 หลัก)"
        }
    }

    private var idTypeIcon: String {
        switch idType {
        case "national_id": return "person.text.rectangle.fill"
        case "tax_id": return "building.columns.fill"
        default: return "phone.fill"
        }
    }

    private var idTypePlaceholder: String {
        switch idType {
        case "national_id": return "เช่น 1234567890123"
        case "tax_id": return "เช่น 0105558000123"
        default: return "เช่น 0812345678"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color(hex: "003B71").opacity(0.12)).frame(width: 50, height: 50)
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(Color(hex: "003B71"))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("PromptPay QR Code")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(.textPrimary)
                                Text("ค่าธรรมเนียม: 0.0%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Text(isOfflineMode ? "โหมดออฟไลน์: สร้าง QR Code ล็อกยอดเงินตามบิลในเครื่อง 100%" : "รองรับทั้งแบบต่อ API เกตเวย์ และพร้อมเพย์ตรงล็อกยอดเงินตามบิล")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    if isOfflineMode {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bolt.slash.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("แพ็กเกจออฟไลน์ (Offline Mode Active)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text("ระบบทำงานแบบ Stand-alone 100% โดยสร้าง QR Code พร้อมเพย์ล็อกยอดเงินตามบิลในเครื่องทันที ไม่ต้องใช้อินเทอร์เน็ต และไม่มีการส่งข้อมูลไปยังเซิร์ฟเวอร์ภายนอก")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))

                        directModeView
                    } else {
                        // Segmented Mode Selector
                        Picker("โหมดการทำงาน", selection: $selectedMode) {
                            Text("📱 พร้อมเพย์ตรง (ล็อกยอดเงิน)").tag("direct")
                            Text("🔗 เชื่อมต่อผ่าน API").tag("api")
                        }
                        .pickerStyle(.segmented)

                        if selectedMode == "direct" {
                            directModeView
                        } else {
                            apiModeView
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle("ตั้งค่า PromptPay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaved ? "บันทึกแล้ว ✓" : "บันทึกข้อมูล") {
                        saveConfiguration()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(isSaved ? .green : .appAccent)
                }
            }
            .onAppear {
                selectedMode = isOfflineMode ? "direct" : promptPayMode
                idType = promptPayIdType
                ppNumber = promptPayNumber
                accountName = promptPayAccountName.isEmpty ? storeName : promptPayAccountName
                lockAmount = promptPayLockAmount
                apiKey = promptPayApiKey
                secretKey = promptPaySecretKey
                gatewayProvider = promptPayGatewayProvider
                testMode = paymentTestMode
            }
        }
    }

    private var directModeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Explanation Notice Card
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.appAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ระบบพร้อมเพย์ตรง (Direct Dynamic PromptPay)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("ระบบจะสร้าง Thai QR Code มาตรฐานสากล (EMVCo) ที่**ล็อกยอดเงินตามบิลอัตโนมัติ** ป้องกันลูกค้าใส่จำนวนเงินไม่ครบ ไม่ต้องต่อ API ธนาคารปลายทาง โดยแคชเชียร์จะตรวจสอบสลิปแล้วกดยืนยันการรับเงิน")
                        .font(.system(size: 11.5))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color.appAccent.opacity(0.08))
            .cornerRadius(12)

            // Form Card
            VStack(alignment: .leading, spacing: 16) {
                Text("ข้อมูลบัญชีพร้อมเพย์")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                // Identifier Type Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("ประเภทหมายเลข")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Picker("ประเภท", selection: $idType) {
                        Text("📱 เบอร์โทรศัพท์").tag("phone")
                        Text("🪪 เลขบัตรประชาชน").tag("national_id")
                        Text("🏢 เลขประจำตัวผู้เสียภาษี").tag("tax_id")
                    }
                    .pickerStyle(.segmented)
                }

                // Number input
                VStack(alignment: .leading, spacing: 6) {
                    Text(idTypeTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: idTypeIcon)
                            .foregroundColor(.textTertiary)
                            .frame(width: 20)

                        TextField(idTypePlaceholder, text: $ppNumber)
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.numberPad)
                    }
                    .padding(12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                }

                // Account / Store Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("ชื่อบัญชี / ชื่อร้านค้าสำหรับแสดงบนหน้าจอ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: "storefront.fill")
                            .foregroundColor(.textTertiary)
                            .frame(width: 20)

                        TextField("ระบุชื่อบัญชีหรือชื่อร้านค้า", text: $accountName)
                            .font(.system(size: 14))
                    }
                    .padding(12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                }

                // Dynamic Amount Lock Toggle
                Toggle(isOn: $lockAmount) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.appAccent)
                            Text("ล็อกราคาสินค้าใน QR Code อัตโนมัติ (แนะนำ)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                        Text("ลูกค้าจะไม่สามารถแก้ไขยอดเงินในแอปธนาคารได้ ป้องกันการกรอกยอดเงินผิดพลาด")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                }
                .tint(.appAccent)
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color.appSurface)
            .cornerRadius(12)

            // Live Preview Card
            if !ppNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.appAccent)
                        Text("ตัวอย่างการแสดงผล QR Code (ทดสอบ ฿100.00)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                    }

                    let testPayload = PromptPayPayloadGenerator.generate(
                        target: ppNumber,
                        amount: lockAmount ? 100.0 : nil,
                        isDynamic: lockAmount
                    )
                    let testQR = PromptPayPayloadGenerator.generateQRCodeImage(from: testPayload, scale: 6.0)

                    HStack(spacing: 16) {
                        if let img = testQR {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 110, height: 110)
                                .padding(6)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountName.isEmpty ? "ชื่อร้านค้า" : accountName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("PromptPay: \(ppNumber)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.textSecondary)

                            HStack(spacing: 4) {
                                Image(systemName: lockAmount ? "lock.fill" : "lock.open.fill")
                                Text(lockAmount ? "ล็อกยอดเงิน ฿100.00" : "ยอดเงินกำหนดเอง")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(lockAmount ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background((lockAmount ? Color.green : Color.orange).opacity(0.12))
                            .cornerRadius(4)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                }
                .padding(14)
                .background(Color.appSurface)
                .cornerRadius(12)
            }

            // Save Button
            Button(action: saveConfiguration) {
                HStack {
                    Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down.fill")
                    Text(isSaved ? "บันทึกการตั้งค่าแล้ว ✓" : "บันทึกข้อมูลพร้อมเพย์ตรง")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSaved ? Color.green : Color.appAccent)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private var apiModeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Notice
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "635BFF"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("เชื่อมต่อผ่าน Payment Gateway API")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("เชื่อมต่อระบบกับ Payment Gateway เพื่อออก Dynamic QR Code และรับผลการชำระเงินจากธนาคารผ่าน Webhook แบบอัตโนมัติ")
                        .font(.system(size: 11.5))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color(hex: "635BFF").opacity(0.08))
            .cornerRadius(12)

            // Form Card
            VStack(alignment: .leading, spacing: 16) {
                Text("ข้อมูลรับรอง API (API Credentials)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                // Provider Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("ผู้ให้บริการเกตเวย์")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Picker("ผู้ให้บริการ", selection: $gatewayProvider) {
                        ForEach(gatewayOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
                }

                // API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key (Public Key)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                    TextField("pk_test_...", text: $apiKey)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(8)
                }

                // Secret Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("Secret Key (Private Key)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                    SecureField("sk_test_...", text: $secretKey)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(8)
                }

                // Test Mode
                Toggle(isOn: $testMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("โหมดทดสอบ (Sandbox Mode)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("ใช้คีย์ทดสอบ — ไม่มีการตัดเงินจริง")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                }
                .tint(.orange)
            }
            .padding(16)
            .background(Color.appSurface)
            .cornerRadius(12)

            // Save Button
            Button(action: saveConfiguration) {
                HStack {
                    Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down.fill")
                    Text(isSaved ? "บันทึกการตั้งค่าแล้ว ✓" : "บันทึกข้อมูลเชื่อมต่อ API")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSaved ? Color.green : Color.appAccent)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private func saveConfiguration() {
        let cleanNumber = ppNumber.filter { $0.isNumber }
        promptPayMode = isOfflineMode ? "direct" : selectedMode
        promptPayIdType = idType
        promptPayNumber = cleanNumber
        promptPayAccountName = accountName
        promptPayLockAmount = lockAmount
        promptPayApiKey = apiKey
        promptPaySecretKey = secretKey
        promptPayGatewayProvider = gatewayProvider
        paymentTestMode = testMode

        // Cloud sync only if online
        if !isOfflineMode {
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }

        APHaptic.trigger()
        withAnimation {
            isSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismiss()
        }
    }
}

// MARK: - Generic Gateway Config Sheet

private struct GenericGatewayConfigView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: PaymentGatewayView.GatewayProvider

    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var testMode = true

    private var isOfflineMode: Bool {
        OfflineSyncModeController.isEnabled || OfflineSyncModeController.isOfflineSubscriptionPlan
    }

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

                    if isOfflineMode {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ไม่รองรับในแพ็กเกจออฟไลน์")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text("เกตเวย์รับชำระเงินภายนอกจำเป็นต้องเชื่อมต่ออินเทอร์เน็ตเพื่อสื่อสารกับธนาคาร จึงเปิดใช้งานเฉพาะในโหมดออนไลน์เท่านั้น สำหรับโหมดออฟไลน์แนะนำให้ใช้ PromptPay QR Code ล็อกยอดเงิน")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
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
                                .disabled(isOfflineMode)
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
                                .disabled(isOfflineMode)
                        }
                    }
                    .opacity(isOfflineMode ? 0.6 : 1.0)

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
                    .disabled(isOfflineMode)
                    .opacity(isOfflineMode ? 0.6 : 1.0)

                    Label(isOfflineMode ? "เกตเวย์ปิดใช้งานในโหมดออฟไลน์" : "Provider integration unavailable", systemImage: isOfflineMode ? "wifi.slash" : "link.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isOfflineMode ? Color.gray.opacity(0.3) : provider.color.opacity(0.35))
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

// MARK: - PromptPay Payload & QR Generator Helper

struct PromptPayPayloadGenerator {
    static func generate(target: String, amount: Double? = nil, isDynamic: Bool = true) -> String {
        let sanitized = target.filter { $0.isNumber }

        var accountInfo = "0016A000000677010111"
        if sanitized.count == 13 {
            // National ID or Tax ID
            accountInfo += "0213\(sanitized)"
        } else if sanitized.count >= 14 {
            // e-Wallet or 15-digit ID
            accountInfo += String(format: "03%02d%@", sanitized.count, sanitized)
        } else {
            // Mobile Phone number
            var phone = sanitized
            if phone.hasPrefix("0") {
                phone.removeFirst()
            }
            let phoneFormatted = "0066" + phone
            accountInfo += "0113\(phoneFormatted)"
        }

        let qrType = (isDynamic && amount != nil && (amount ?? 0) > 0) ? "12" : "11"
        var payload = "0002010102" + qrType
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764"

        if let amt = amount, isDynamic, amt > 0 {
            let amtStr = String(format: "%.2f", amt)
            payload += String(format: "54%02d%@", amtStr.count, amtStr)
        }

        payload += "5802TH"
        payload += "6304"

        let crc = crc16(payload)
        payload += String(format: "%04X", crc)
        return payload
    }

    static func crc16(_ dataString: String) -> UInt16 {
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

    private static let sharedCIContext = CIContext()
    private static let qrCache = NSCache<NSString, UIImage>()

    static func generateQRCodeImage(from string: String, scale: CGFloat = 10.0) -> UIImage? {
        let cacheKey = "\(string)_\(scale)" as NSString
        if let cached = qrCache.object(forKey: cacheKey) {
            return cached
        }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCIImage = ciImage.transformed(by: transform)
        guard let cgImage = sharedCIContext.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        qrCache.setObject(image, forKey: cacheKey)
        return image
    }
}
