// DailySalesReportView.swift
// AlphaPos — Reports Feature Module
//
// International tax-inclusive Daily Sales report with sales bridge,
// tender reconciliation, hourly chart, and staggered appear animations.

import SwiftUI
import SwiftData

struct DailySalesReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("store_name") private var storeName = ""
    // Live sync state — the badge must reflect the real connection, not the
    // stored plan preference, otherwise online stores see a confusing
    // "Offline" label.
    @ObservedObject private var syncEngine = SyncEngine.shared

    @State private var appeared = false

    private var validPaymentBreakdown: [PaymentMethodPoint] {
        let positive = viewModel.paymentBreakdown.filter { $0.amount > 0 }
        let total = positive.reduce(0.0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        return positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            headerStrip
            kpiCardsSection
            storefrontSettlementSection
            deliveryReceivablesSection
            salesBridgeSection
            reconcileSection
            hourlySalesChart
            paymentBreakdownSection
            zReportHint
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Header

    private var headerStrip: some View {
        HStack(alignment: .center, spacing: APSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(storeName.isEmpty ? "AlphaPos" : storeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(L.Reports.asOf.t) \(computedAtString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.dailySalesReportId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            modeBadge
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
    }

    private var modeBadge: some View {
        // Reflect the LIVE sync state. "Offline" is shown only when the store
        // is on an offline plan OR the sync engine actually lost connection —
        // never from a stale preference flag.
        let (label, color): (String, Color) = {
            if offlineSyncMode {
                return (L.Reports.modeOffline.t, .orange)
            }
            switch syncEngine.syncStatus {
            case .offline:
                return (lm.languageCode == "th" ? "ขาดการเชื่อมต่อ" : "No Connection", .orange)
            case .syncing:
                return (lm.languageCode == "th" ? "กำลังซิงก์…" : "Syncing…", .appAccent)
            default:
                return (L.Reports.modeOnline.t, .appTeal)
            }
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var computedAtString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: viewModel.reportComputedAt)
    }

    // MARK: - Primary KPIs

    private var kpiCardsSection: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: APSpacing.md, alignment: .top),
            count: 4
        )
        return LazyVGrid(columns: columns, spacing: APSpacing.md) {
            kpiCard(
                title: L.Reports.netSalesIncVAT.t,
                value: viewModel.formatCurrency(viewModel.netSalesIncVAT),
                icon: "banknote.fill",
                color: .appTeal,
                index: 0
            )
            kpiCard(
                title: lm.currentLanguage == .thai ? "รายได้ทางบัญชี (ไม่รวม VAT)" : "Accounting Revenue (ex. VAT)",
                value: viewModel.formatCurrency(viewModel.accountingRevenueExVAT),
                icon: "chart.line.uptrend.xyaxis",
                color: .appAccent,
                index: 1
            )
            kpiCard(
                title: L.Reports.totalOrders.t,
                value: "\(viewModel.totalOrders)",
                icon: "bag.fill",
                color: .orange,
                index: 2
            )
            kpiCard(
                title: L.Reports.avgTicket.t,
                value: viewModel.formatCurrency(viewModel.averageTicket),
                icon: "ticket.fill",
                color: .indigo,
                index: 3
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : CGFloat(10 + index * 4))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.06), value: appeared)
    }

    // MARK: - Section 1: In-Store Direct Cash & Tenders
    private var storefrontSettlementSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appTeal.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "storefront.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                }
                Text(lm.currentLanguage == .thai ? "1. ยอดขายและการรับเงินจริงหน้าร้าน (In-Store Direct Settlements)" : "1. In-Store Direct Cash & Settlements")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(viewModel.storefrontOrdersCount) " + (lm.currentLanguage == .thai ? "ออเดอร์" : "orders"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
            }

            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายรวมหน้าร้าน (Gross Storefront)" : "Gross Storefront Sales", viewModel.storefrontGross, emphasis: false)
            bridgeRow(lm.currentLanguage == .thai ? "หัก ส่วนลดหน้าร้าน" : "Less: Storefront Discounts", -viewModel.storefrontDiscount, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิหน้าร้าน (รวม VAT)" : "Net Storefront Sales (incl. VAT)", viewModel.storefrontNetSales, emphasis: true)

            if viewModel.storefrontRefunds > 0 {
                bridgeRow(lm.currentLanguage == .thai ? "หัก คืนเงินหน้าร้าน" : "Less: Storefront Refunds", -viewModel.storefrontRefunds, emphasis: false, negative: true)
                bridgeRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิหลังคืนเงินหน้าร้าน" : "Net Storefront after Refunds", viewModel.storefrontNetRevenue, emphasis: true)
            }

            Divider().opacity(0.35)

            Text(lm.currentLanguage == .thai ? "การแจกแจงวิธีรับเงินจริง (ตรวจนับปิดกะ / เข้าบัญชีทันที)" : "Cash & Direct Tenders Breakdown (Instant Settlements)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: APSpacing.md) {
                sideMetric(
                    title: lm.currentLanguage == .thai ? "💵 เงินสดในลิ้นชัก" : "💵 Cash in Drawer",
                    value: viewModel.formatCurrency(viewModel.storefrontCash),
                    icon: "banknote.fill",
                    color: .appTeal
                )
                sideMetric(
                    title: lm.currentLanguage == .thai ? "📱 QR / เงินโอน" : "📱 QR / PromptPay",
                    value: viewModel.formatCurrency(viewModel.storefrontTransfer),
                    icon: "qrcode",
                    color: .appAccent
                )
                sideMetric(
                    title: lm.currentLanguage == .thai ? "💳 บัตรเครดิต EDC" : "💳 EDC Card",
                    value: viewModel.formatCurrency(viewModel.storefrontCard),
                    icon: "creditcard.fill",
                    color: .indigo
                )
            }
            .padding(.top, 2)
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.1), value: appeared)
    }

    // MARK: - Section 2: Delivery Platforms & Trade Receivables
    private var deliveryReceivablesSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "bicycle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                Text(lm.currentLanguage == .thai ? "2. ยอดขายเดลิเวอรีและลูกหนี้การค้า (Delivery Platforms & Trade Receivables)" : "2. Delivery Platforms & Trade Receivables")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(viewModel.deliveryOrdersCount) " + (lm.currentLanguage == .thai ? "ออเดอร์" : "orders"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
            }

            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายรวมบนแอปเดลิเวอรี (Gross Delivery)" : "Gross Delivery Sales", viewModel.deliveryGross, emphasis: false)
            bridgeRow(lm.currentLanguage == .thai ? "หัก ส่วนลดที่ร้านออกบนแอป" : "Less: Merchant Discounts", -viewModel.deliveryDiscount, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิเดลิเวอรี (รวม VAT)" : "Net Delivery Sales (incl. VAT)", viewModel.deliveryNetSales, emphasis: true)
            bridgeRow(lm.currentLanguage == .thai ? "หัก คืนเงินเดลิเวอรีในงวด" : "Less: Delivery Refunds in Period", -viewModel.deliveryRefunds, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "หัก ค่า GP & ค่าโฆษณาแพลตฟอร์ม" : "Less: Platform GP & Ads Fees", -viewModel.deliveryPlatformFees, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "= ยอดคาดรับสุทธิของงวด (ยังไม่หักยอดโอนแล้ว)" : "= Estimated Period Payout (before settlements)", viewModel.deliveryNetReceivables, emphasis: true)

            if !viewModel.deliveryPlatformBreakdown.isEmpty {
                Divider().opacity(0.35)

                Text(lm.currentLanguage == .thai ? "สรุปแยกตามแพลตฟอร์ม (Grab / LINE MAN / ShopeeFood)" : "Breakdown by Platform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(spacing: 6) {
                    ForEach(viewModel.deliveryPlatformBreakdown) { p in
                        HStack {
                            Text(p.brandName)
                                .font(.subheadline.weight(.semibold))
                            Text("(\(p.ordersCount))")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(viewModel.formatCurrency(p.netReceivables))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.appTeal)
                                Text((lm.currentLanguage == .thai ? "ยอดขาย " : "Net sales ") + viewModel.formatCurrency(p.netSales)
                                     + (lm.currentLanguage == .thai ? " • ค่าธรรมเนียม " : " • Fees ") + viewModel.formatCurrency(p.platformFees))
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                                Text((lm.currentLanguage == .thai ? "คืนเงิน " : "Refunds ") + viewModel.formatCurrency(p.refunds))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.appSurfaceHigh.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    }
                }
            }
            if !viewModel.deliveryOrderDetails.isEmpty {
                DisclosureGroup(lm.currentLanguage == .thai ? "รายละเอียดเลขเดลิเวอรี" : "Delivery Order Details") {
                    ForEach(viewModel.deliveryOrderDetails) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.brandName + " · " + (item.platformOrderNumber ?? (lm.currentLanguage == .thai ? "ไม่ระบุเลขเดลิเวอรี" : "Delivery number missing")))
                                .font(.subheadline.weight(.semibold))
                                .textSelection(.enabled)
                            Text((lm.currentLanguage == .thai ? "บิล POS: " : "POS receipt: ") + item.orderNumber)
                                .font(.caption).foregroundStyle(.secondary)
                            Text((lm.currentLanguage == .thai ? "ยอดขาย " : "Sales ") + viewModel.formatCurrency(item.netSales)
                                 + (lm.currentLanguage == .thai ? " • คืนเงิน " : " • Refunds ") + viewModel.formatCurrency(item.refunds))
                                .font(.caption.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                }
            }
            Text(lm.currentLanguage == .thai ? "ยอดคาดรับเป็นประมาณการจากค่าธรรมเนียมในออเดอร์ ต้องเทียบรายการโอนและค่าธรรมเนียมจริงของแพลตฟอร์ม" : "Payout is estimated from order fees; reconcile with actual platform fees and settlements.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.15), value: appeared)
    }

    // MARK: - Section 3: Sales Bridge (DBD & Combined Tax Submission)

    private var salesBridgeSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }
                Text(lm.currentLanguage == .thai ? "3. สรุปรายได้รวมทางบัญชีและภาษี (เพื่อประกอบการลงบัญชี / ยื่นภาษี)" : "3. Total Accounting Revenue & Tax Summary (For Accounting & Tax Filing)")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(lm.currentLanguage == .thai
                ? "รายงานนี้ใช้เป็นเอกสารหลักฐานประกอบการบันทึกบัญชีรายได้และภาษีขาย ไม่ใช่ชุดงบการเงินสำหรับยื่น DBD e-Filing โดยตรง"
                : "This report serves as supporting evidence for revenue and sales tax reconciliation, not a certified financial statement for direct DBD e-Filing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            bridgeRow(L.Reports.grossSales.t, viewModel.grossRevenue, emphasis: false)
            bridgeRow(L.Reports.lessDiscounts.t, -viewModel.totalDiscount, emphasis: false, negative: true)
            bridgeRow(L.Reports.netSalesIncVAT.t, viewModel.netSalesIncVAT, emphasis: true)
            Divider().opacity(0.35)
            bridgeRow(L.Reports.merchandiseSubtotal.t, viewModel.merchandiseSubtotal, inset: true)
            bridgeRow(L.Reports.serviceCharge.t, viewModel.serviceChargeTotal, inset: true)
            Divider().opacity(0.35)
            bridgeRow(L.Reports.lessRefunds.t, -viewModel.totalRefunds, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิหลังคืนเงิน (รวม VAT)" : "Net Sales after Refunds (incl. VAT)", viewModel.netRevenue, emphasis: true)
            bridgeRow(lm.currentLanguage == .thai ? "หัก ภาษีขายสุทธิ" : "Less: Net Output VAT", -viewModel.vatCollected, emphasis: false, negative: true)
            if viewModel.refundVAT > 0.005 {
                bridgeRow(lm.currentLanguage == .thai ? "VAT ที่กลับรายการจากการคืนเงิน" : "VAT Reversed on Refunds", viewModel.refundVAT, inset: true)
            }
            bridgeRow(lm.currentLanguage == .thai ? "รายได้ทางบัญชี (ไม่รวม VAT)" : "Accounting Revenue (ex. VAT)", viewModel.accountingRevenueExVAT, emphasis: true)

            HStack(spacing: APSpacing.md) {
                sideMetric(
                    title: L.Reports.tipsNotInSales.t,
                    value: viewModel.formatCurrency(viewModel.tipsTotal),
                    icon: "hand.thumbsup.fill",
                    color: .mint
                )
                sideMetric(
                    title: L.Reports.voids.t,
                    value: "\(viewModel.voidOrderCount) · \(viewModel.formatCurrency(viewModel.voidAmount))",
                    icon: "xmark.circle.fill",
                    color: .red
                )
                sideMetric(
                    title: L.Reports.peakHour.t,
                    value: peakHourString,
                    icon: "clock.fill",
                    color: .orange
                )
            }
            .padding(.top, APSpacing.sm)
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.15), value: appeared)
    }

    private func bridgeRow(_ title: String, _ amount: Double, emphasis: Bool = false, negative: Bool = false, inset: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasis ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(inset ? .secondary : .primary)
                .padding(.leading, inset ? 12 : 0)
            Spacer()
            Text(viewModel.formatCurrency(amount))
                .font(emphasis ? .subheadline.weight(.bold).monospacedDigit() : .subheadline.monospacedDigit())
                .foregroundStyle(negative ? Color.red : Color.primary)
        }
        .padding(.vertical, 3)
    }

    private func sideMetric(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(2)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
    }

    // MARK: - Reconciliation

    private var reconcileSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.tenderReconcile.t)
                .font(.headline)

            bridgeRow(lm.currentLanguage == .thai ? "ยอดรับชำระสำเร็จ" : "Captured Tenders", viewModel.paymentsCollected, emphasis: false)
            bridgeRow(lm.currentLanguage == .thai ? "หัก คืนเงินสำเร็จ" : "Less: Completed Refunds", -viewModel.totalRefunds, emphasis: false, negative: true)
            bridgeRow(lm.currentLanguage == .thai ? "ยอดรับชำระสุทธิ" : "Net Tender", viewModel.paymentsCollected - viewModel.totalRefunds, emphasis: true)
            Divider().opacity(0.35)
            bridgeRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิหลังคืนเงิน" : "Net Sales after Refunds", viewModel.netRevenue, emphasis: false)
            bridgeRow(L.Reports.tipsNotInSales.t, viewModel.tipsTotal, emphasis: false)
            bridgeRow(L.Reports.tenderVariance.t, viewModel.salesTenderVariance, emphasis: true,
                      negative: abs(viewModel.salesTenderVariance) > 0.009)

            Text(L.Reports.tenderVarianceHint.t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L.Reports.zReportCrossLink.t)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.22), value: appeared)
    }

    // MARK: - Visualizers

    private var hourlySalesChart: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Text(L.Reports.hourlySales.t)
                    .font(.headline)
                Spacer()
                if let peak = viewModel.peakHour {
                    Text("\(L.Reports.peakHour.t): \(String(format: "%02d:00", peak))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appTeal)
                }
            }

            let maxRevenue = max(viewModel.hourlySales.map(\.revenue).max() ?? 0, 1)
            let hasSales = viewModel.hourlySales.contains(where: { $0.revenue > 0 })

            if !hasSales {
                Text(L.Reports.noData.t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(viewModel.hourlySales) { point in
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            let ratio = CGFloat(max(point.revenue, 0) / maxRevenue)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    point.revenue > 0
                                        ? LinearGradient(colors: [Color.appTeal, Color.appTeal.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(colors: [Color.appSurfaceHigh.opacity(0.35), Color.appSurfaceHigh.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: max(ratio * 120, point.revenue > 0 ? 6 : 2))

                            if point.hour % 3 == 0 {
                                Text(String(format: "%02d", point.hour))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("")
                                    .font(.system(size: 9))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 150)
                .padding(.top, 8)
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var paymentBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.paymentBreakdown.t)
                .font(.headline)

            let total = validPaymentBreakdown.reduce(0.0) { $0 + $1.amount }

            if validPaymentBreakdown.isEmpty || total <= 0 {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
            } else {
                VStack(spacing: APSpacing.md) {
                    // Segmented horizontal distribution bar
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(validPaymentBreakdown) { point in
                                let width = max((CGFloat(point.amount / total) * geo.size.width) - 2, 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(paymentMethodColor(point.method))
                                    .frame(width: width, height: 10)
                            }
                        }
                    }
                    .frame(height: 10)

                    // Breakdown Rows
                    VStack(spacing: APSpacing.sm) {
                        ForEach(validPaymentBreakdown) { point in
                            HStack(spacing: APSpacing.sm) {
                                Circle()
                                    .fill(paymentMethodColor(point.method))
                                    .frame(width: 8, height: 8)
                                Text(displayPaymentMethod(point.method))
                                    .font(.subheadline)
                                Spacer()
                                Text(viewModel.formatCurrency(point.amount))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                Text(total > 0 ? String(format: "%.0f%%", point.amount / total * 100) : "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.28), value: appeared)
    }

    private func paymentMethodColor(_ method: String) -> Color {
        switch method {
        case "cash": return .appTeal
        case "credit_card": return .blue
        case "qr_promptpay": return .purple
        case "true_money": return .orange
        default: return .appAccent
        }
    }

    private var zReportHint: some View {
        Text(L.Reports.zReportCrossLink.t)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var peakHourString: String {
        guard let hour = viewModel.peakHour else { return "-" }
        return String(format: "%02d:00", hour)
    }

    private func displayPaymentMethod(_ method: String) -> String {
        switch method {
        case "cash":           return L.Reports.methodCash.t
        case "credit_card":    return L.Reports.methodCard.t
        case "qr_promptpay":   return L.Reports.methodQR.t
        case "true_money":     return "TrueMoney"
        default:               return method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value >= 1000000 {
            return String(format: "%.1fM", value / 1000000)
        }
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
