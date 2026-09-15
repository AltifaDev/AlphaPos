// MARK: - BillingView (AlphaPos Parity Multi-Tender Payment & Theme Support)

import SwiftUI
import Combine
import CoreImage

// MARK: - Active Payment Modal Enum (AlphaPos Parity)

enum ActiveStaffPaymentModal: Identifiable {
    case cash
    case qrCode
    case creditCard
    case thaiChuaThaiPlus
    case splitPayment

    var id: String {
        switch self {
        case .cash: return "cash"
        case .qrCode: return "qrCode"
        case .creditCard: return "creditCard"
        case .thaiChuaThaiPlus: return "thaiChuaThaiPlus"
        case .splitPayment: return "splitPayment"
        }
    }
}

// MARK: - Split Payment Data Types

struct StaffSplitEntry: Identifiable {
    let id = UUID()
    var method: String = "Cash"   // "Cash" | "QR PromptPay" | "Credit Card"
    var amount: Double = 0.0
    var amountText: String = ""
    var cashReceived: Double = 0.0
}

// MARK: - Government Support Program Constants

enum GovernmentSupportProgram {
    static let thaiChuaThaiPlus = "ไทยช่วยไทย Plus"
    static let governmentRate = 0.60
    static let citizenRate = 0.40

    static func split(total: Double) -> (citizen: Double, government: Double) {
        let safeTotal = max(0, total)
        let citizen = (safeTotal * citizenRate * 100).rounded() / 100
        return (citizen, max(0, (safeTotal - citizen) * 100).rounded() / 100)
    }
}

// MARK: - BillingView

struct BillingView: View {
    let table: RestaurantTable
    let orders: [Order]
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
    @Environment(\.colorScheme) private var colorScheme

    @State private var activePaymentModal: ActiveStaffPaymentModal? = nil
    @State private var paymentProcessing = false
    @State private var paymentSuccess = false
    @State private var checkoutErrorMessage: String? = nil
    @State private var showReceiptPreview = false
    @State private var bgPhase: Double = 0
    @State private var cardsAppeared = false
    @State private var panelAppeared = false

    @Environment(\.dismiss) private var dismiss

    private var isDarkMode: Bool {
        if appTheme == "dark" { return true }
        if appTheme == "light" { return false }
        return colorScheme == .dark
    }

    // MARK: - Computed Financials (From Store Settings)

    var subtotal: Double {
        orders.filter { $0.status != "cancelled" }.map { $0.total }.reduce(0, +)
    }

    var taxRate: Double {
        NetworkService.shared.taxRate
    }

    var taxType: String {
        NetworkService.shared.taxType
    }

    var serviceChargeRate: Double {
        NetworkService.shared.serviceChargeRate
    }

    var serviceCharge: Double {
        guard serviceChargeRate > 0 else { return 0.0 }
        let rate = serviceChargeRate > 1.0 ? (serviceChargeRate / 100.0) : serviceChargeRate
        return ((subtotal * rate) * 100).rounded() / 100
    }

    var tax: Double {
        guard taxRate > 0 else { return 0.0 }
        let rate = taxRate > 1.0 ? (taxRate / 100.0) : taxRate
        let taxableBase = subtotal + serviceCharge
        if taxType.lowercased() == "inclusive" {
            return ((taxableBase * rate / (1.0 + rate)) * 100).rounded() / 100
        } else {
            return ((taxableBase * rate) * 100).rounded() / 100
        }
    }

    var grandTotal: Double {
        if taxType.lowercased() == "exclusive" && taxRate > 0 {
            return subtotal + serviceCharge + tax
        } else {
            return subtotal + serviceCharge
        }
    }

    private var isAllServed: Bool {
        if !NetworkService.shared.kitchenWorkflowRequired { return true }
        guard !orders.isEmpty else { return false }
        return orders.allSatisfy { order in
            order.status == "cancelled" ||
            order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Adaptive Light/Dark Background
                adaptiveBackground

                if paymentSuccess {
                    liquidSuccessView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                } else if !isAllServed {
                    checkoutBlockedState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            tableMetaHeader(geo: geo)
                                .padding(.top, geo.safeAreaInsets.top + 8)

                            VStack(spacing: 16) {
                                orderItemsSection
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 20)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: cardsAppeared)

                                financialSummaryCard
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 20)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: cardsAppeared)

                                prePaymentPrintButton
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 20)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.28), value: cardsAppeared)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            // Space for bottom payment panel
                            Spacer().frame(height: 290)
                        }
                    }
                    .ignoresSafeArea(edges: .top)

                    // Bottom payment selection panel (Responsive & Symmetrically Centered)
                    VStack(spacing: 0) {
                        alphaPosPaymentPanel
                    }
                    .offset(y: panelAppeared ? 0 : 290)
                    .animation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.1), value: panelAppeared)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $activePaymentModal) { modal in
            switch modal {
            case .cash:
                StaffCashPaymentModalView(totalAmount: grandTotal) { cashReceived in
                    completeCheckout(method: "Cash", cashTendered: cashReceived)
                }
            case .qrCode:
                StaffQRPaymentModalView(totalAmount: grandTotal) {
                    completeCheckout(method: "QR PromptPay")
                }
            case .creditCard:
                StaffCreditCardPaymentModalView(totalAmount: grandTotal) {
                    completeCheckout(method: "Credit Card")
                }
            case .thaiChuaThaiPlus:
                StaffThaiChuaThaiPlusPaymentModal(totalAmount: grandTotal) { reference in
                    completeThaiChuaThaiPlusCheckout(reference: reference)
                }
            case .splitPayment:
                StaffSplitPaymentView(totalAmount: grandTotal) { entries in
                    completeSplitCheckout(entries: entries)
                }
            }
        }
        .sheet(isPresented: $showReceiptPreview) {
            StaffPreBillSheetView(
                tableNumber: table.tableNumber,
                guestCount: table.guestCount,
                orders: orders.filter { $0.status != "cancelled" },
                subtotal: subtotal,
                tax: tax,
                taxRate: taxRate,
                taxType: taxType,
                serviceCharge: serviceCharge,
                serviceChargeRate: serviceChargeRate,
                grandTotal: grandTotal
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                bgPhase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation { cardsAppeared = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { panelAppeared = true }
            }
        }
        .alert("ชำระเงินไม่สำเร็จ", isPresented: Binding(
            get: { checkoutErrorMessage != nil },
            set: { if !$0 { checkoutErrorMessage = nil } }
        )) {
            Button("ลองใหม่", role: .cancel) { checkoutErrorMessage = nil }
        } message: {
            Text(checkoutErrorMessage ?? "")
        }
        .apColorScheme()
    }

    // MARK: - Adaptive Background (Light / Dark)

    private var adaptiveBackground: some View {
        ZStack {
            if isDarkMode {
                Color(hex: "0A0F1E").ignoresSafeArea()

                Circle()
                    .fill(RadialGradient(
                        colors: [Color.appAccent.opacity(0.22), Color.clear],
                        center: .center, startRadius: 0, endRadius: 220
                    ))
                    .frame(width: 440, height: 440)
                    .offset(x: -120 + sin(bgPhase * .pi * 2) * 30, y: -200 + cos(bgPhase * .pi * 2) * 20)
                    .blur(radius: 50)

                Circle()
                    .fill(RadialGradient(
                        colors: [Color.appTeal.opacity(0.18), Color.clear],
                        center: .center, startRadius: 0, endRadius: 180
                    ))
                    .frame(width: 360, height: 360)
                    .offset(x: 140 - cos(bgPhase * .pi * 2) * 25, y: 100 + sin(bgPhase * .pi * 2) * 25)
                    .blur(radius: 40)
            } else {
                LinearGradient(
                    colors: [Color(hex: "F3F5F9"), Color(hex: "EBF0F8"), Color(hex: "F0F4FA")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(RadialGradient(
                        colors: [Color.appAccent.opacity(0.10), Color.clear],
                        center: .center, startRadius: 0, endRadius: 200
                    ))
                    .frame(width: 400, height: 400)
                    .offset(x: -100 + sin(bgPhase * .pi * 2) * 20, y: -180 + cos(bgPhase * .pi * 2) * 15)
                    .blur(radius: 40)

                Circle()
                    .fill(RadialGradient(
                        colors: [Color.appTeal.opacity(0.08), Color.clear],
                        center: .center, startRadius: 0, endRadius: 160
                    ))
                    .frame(width: 320, height: 320)
                    .offset(x: 120 - cos(bgPhase * .pi * 2) * 20, y: 80 + sin(bgPhase * .pi * 2) * 20)
                    .blur(radius: 35)
            }
        }
    }

    // MARK: - Table Meta Header

    private func tableMetaHeader(geo: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("โต๊ะ \(table.tableNumber)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("รายการเช็คบิลและปิดโต๊ะ")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    APHaptic.trigger()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metaChip(icon: "person.2.fill", label: "ที่นั่ง", value: "\(table.guestCount)", color: .appTeal)
                    if table.elapsedMinutes > 0 {
                        metaChip(icon: "clock.fill", label: "เวลา", value: "\(table.elapsedMinutes) นาที", color: .appAmber)
                    }
                    let activeOrders = orders.filter { $0.status != "cancelled" }
                    metaChip(icon: "list.clipboard.fill", label: "ออเดอร์", value: "\(activeOrders.count) รายการ", color: Color.appPurple)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
        }
    }

    private func metaChip(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(.textSecondary)
                Text(value).font(.system(size: 12, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(isDarkMode ? 0.15 : 0.10), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(isDarkMode ? 0.35 : 0.25), lineWidth: 1))
    }

    // MARK: - Order Items Section

    private var activeOrderItems: [OrderItem] {
        orders.filter { $0.status != "cancelled" }.flatMap { $0.items.filter { $0.status != "cancelled" } }
    }

    private var orderItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("สรุปรายการอาหาร", systemImage: "receipt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(activeOrderItems.count) รายการ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(activeOrderItems) { item in
                    orderItemRow(item)
                }
            }
            .padding(14)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
            .shadow(color: isDarkMode ? Color.clear : Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
    }

    private func orderItemRow(_ item: OrderItem) -> some View {
        HStack(alignment: .top) {
            Text("\(item.quantity)x")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(.appAccent)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if !item.modifiers.isEmpty {
                    Text(item.modifiers.map(\.name).joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
            Text("฿\(String(format: "%.2f", item.price * Double(item.quantity)))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Financial Summary Card

    private var financialSummaryCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                liquidSummaryRow(label: "ยอดรวมอาหาร", value: subtotal, labelColor: .textSecondary, valueColor: .textPrimary, fontSize: 14)
                if serviceCharge > 0 {
                    liquidSummaryRow(
                        label: "ค่าบริการ Service Charge (\(Int(serviceChargeRate > 1.0 ? serviceChargeRate : serviceChargeRate * 100))%)",
                        value: serviceCharge,
                        labelColor: .textSecondary,
                        valueColor: .textPrimary,
                        fontSize: 13
                    )
                }
                if tax > 0 {
                    liquidSummaryRow(
                        label: "ภาษีมูลค่าเพิ่ม VAT (\(Int(taxRate > 1.0 ? taxRate : taxRate * 100))%\(taxType.lowercased() == "inclusive" ? " รวมในบิล" : ""))",
                        value: tax,
                        labelColor: .textSecondary,
                        valueColor: .textPrimary,
                        fontSize: 13
                    )
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.appDivider, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("ยอดสุทธิที่ต้องชำระ")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("฿")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textSecondary)
                Text(String(format: "%.2f", grandTotal))
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
            }
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: isDarkMode ? Color.clear : Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func liquidSummaryRow(label: String, value: Double, labelColor: Color, valueColor: Color, fontSize: CGFloat) -> some View {
        HStack {
            Text(label).font(.system(size: fontSize, weight: .medium)).foregroundColor(labelColor)
            Spacer()
            Text("฿\(String(format: "%.2f", value))")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Pre-Payment Print Button

    private var prePaymentPrintButton: some View {
        Button(action: { showReceiptPreview = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(isDarkMode ? 0.18 : 0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "printer.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("พิมพ์บิลรายการ (ก่อนชำระ)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("ตรวจสอบรายการและแสดง PromptPay QR ให้ลูกค้า")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
            .shadow(color: isDarkMode ? Color.clear : Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - AlphaPos Payment Method Selection Panel (Responsive Grid & Centered)

    private var isPromptPayConfigured: Bool {
        !NetworkService.shared.promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var alphaPosPaymentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Drag Indicator & Title
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 38, height: 4)
                    .padding(.top, 8)

                HStack {
                    Text("เลือกช่องทางชำระเงิน")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("ยอดรวม ฿\(String(format: "%.2f", grandTotal))")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.appAccent)
                }
                .padding(.horizontal, 16)
            }

            // Primary 3 Tenders Row (Cash, QR PromptPay, Credit Card) - Responsive & Equal Width
            HStack(spacing: 10) {
                tenderTile(
                    title: "เงินสด",
                    subtitle: "Cash",
                    icon: "banknote.fill",
                    tint: .appTeal
                ) {
                    APHaptic.trigger()
                    activePaymentModal = .cash
                }

                tenderTile(
                    title: "สแกน QR",
                    subtitle: isPromptPayConfigured ? "PromptPay" : "ยังไม่ตั้งค่า",
                    icon: "qrcode",
                    tint: Color.appPurple
                ) {
                    APHaptic.trigger()
                    activePaymentModal = .qrCode
                }

                tenderTile(
                    title: "บัตร",
                    subtitle: "Card",
                    icon: "creditcard.fill",
                    tint: Color.appRose
                ) {
                    APHaptic.trigger()
                    activePaymentModal = .creditCard
                }
            }
            .padding(.horizontal, 16)

            // Secondary 2 Tenders Row (Thai Chua Thai Plus, Split Payment) - Centered & Equal Width
            HStack(spacing: 10) {
                // โครงการไทยช่วยไทย Plus
                Button {
                    APHaptic.trigger()
                    activePaymentModal = .thaiChuaThaiPlus
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.20))
                                .frame(width: 34, height: 34)
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(GovernmentSupportProgram.thaiChuaThaiPlus)
                                .font(.system(size: 12.5, weight: .black))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("รัฐ 60% · จ่าย 40%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "1D4ED8"), Color(hex: "1E40AF")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color(hex: "1D4ED8").opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)

                // แยกชำระหลายช่องทาง (Split Pay)
                Button {
                    APHaptic.trigger()
                    activePaymentModal = .splitPayment
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.appAccent.opacity(0.12))
                                .frame(width: 34, height: 34)
                            Image(systemName: "square.split.2x2.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.appAccent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("แบ่งชำระเงิน")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text("หารคน / แยกจ่าย")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(isDarkMode ? 0.35 : 0.12), radius: 20, x: 0, y: -6)
    }

    private func tenderTile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isDarkMode ? 0.16 : 0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tint)
                }
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.appSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: isDarkMode ? Color.clear : tint.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Blocked State (Kitchen Tickets Pending)

    private var checkoutBlockedState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(Color.appAmber.opacity(0.15)).frame(width: 88, height: 88)
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.system(size: 40)).foregroundColor(.appAmber)
            }
            VStack(spacing: 8) {
                Text("ยังมีอาหารที่ยังไม่เสิร์ฟ")
                    .font(.title2.weight(.black)).foregroundColor(.textPrimary)
                Text("กรุณาเสิร์ฟรายการอาหารทั้งหมดในครัวให้เรียบร้อยก่อนชำระเงินและปิดโต๊ะ")
                    .font(.subheadline).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Button {
                dismiss()
            } label: {
                Text("กลับไปหน้าโต๊ะอาหาร")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundColor(.white).background(Color.appAccent)
                    .cornerRadius(APRadius.md)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Success View

    private var liquidSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()
            AnimatedPaymentSuccessMark()
            VStack(spacing: 8) {
                Text("ชำระเงินและปิดโต๊ะสำเร็จ!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("โต๊ะ \(table.tableNumber) · ยอดรวม ฿\(String(format: "%.2f", grandTotal))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            Button {
                dismiss()
            } label: {
                Text("เสร็จสิ้น")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundColor(.white).background(Color.appAccent)
                    .cornerRadius(APRadius.md)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Complete Checkout Logic

    private func completeCheckout(method: String, cashTendered: Double? = nil) {
        let payableOrders = orders.filter { !$0.isPaid && $0.status != "cancelled" }
        guard !payableOrders.isEmpty else {
            checkoutErrorMessage = "ออเดอร์นี้ถูกชำระเงินแล้ว ไม่สามารถชำระซ้ำได้"
            return
        }
        paymentProcessing = true
        checkoutErrorMessage = nil

        Task {
            do {
                let totalOrderAmt = payableOrders.map { $0.total }.reduce(0, +)
                let checkoutRunId = UUID().uuidString.lowercased()

                for (idx, order) in payableOrders.enumerated() {
                    let proportion = totalOrderAmt > 0 ? order.total / totalOrderAmt : 1.0
                    let orderAmount = (grandTotal * proportion * 100).rounded() / 100
                    var paymentObj: [String: Any] = [
                        "id": UUID().uuidString.lowercased(),
                        "amount": orderAmount,
                        "payment_method": method
                    ]
                    if let cash = cashTendered {
                        paymentObj["cash_tendered"] = cash
                        paymentObj["change_due"] = max(0, cash - grandTotal)
                    }

                    _ = try await NetworkService.shared.completeCheckoutAtomic(
                        orderId: order.id,
                        payments: [paymentObj],
                        tableNumber: table.tableNumber,
                        breakdown: [
                            "grand_total": orderAmount,
                            "subtotal": order.total,
                            "tax": tax * proportion,
                            "service_charge": serviceCharge * proportion
                        ],
                        idempotencyKey: "direct:\(checkoutRunId):\(idx):\(order.id)"
                    )
                }

                await MainActor.run {
                    paymentProcessing = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                        paymentSuccess = true
                    }
                    APHaptic.trigger()
                    NotificationCenter.default.post(name: .checkoutCompleted, object: table.tableNumber)
                }
                await NetworkService.shared.refreshAll()
            } catch {
                await MainActor.run {
                    paymentProcessing = false
                    checkoutErrorMessage = "เกิดข้อผิดพลาด: \(error.localizedDescription)\n\nกรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่"
                }
            }
        }
    }

    private func completeThaiChuaThaiPlusCheckout(reference: String) {
        let payableOrders = orders.filter { !$0.isPaid && $0.status != "cancelled" }
        guard !payableOrders.isEmpty else { return }
        paymentProcessing = true
        checkoutErrorMessage = nil

        Task {
            do {
                let totalOrderAmt = payableOrders.map { $0.total }.reduce(0, +)
                let checkoutRunId = UUID().uuidString.lowercased()
                let split = GovernmentSupportProgram.split(total: grandTotal)

                for (idx, order) in payableOrders.enumerated() {
                    let proportion = totalOrderAmt > 0 ? order.total / totalOrderAmt : 1.0
                    let orderAmount = (grandTotal * proportion * 100).rounded() / 100

                    let payments: [[String: Any]] = [
                        [
                            "id": UUID().uuidString.lowercased(),
                            "amount": (split.citizen * proportion * 100).rounded() / 100,
                            "payment_method": GovernmentSupportProgram.thaiChuaThaiPlus,
                            "support_program_name": GovernmentSupportProgram.thaiChuaThaiPlus,
                            "transaction_reference": reference,
                            "support_government_rate": GovernmentSupportProgram.governmentRate
                        ],
                        [
                            "id": UUID().uuidString.lowercased(),
                            "amount": (split.government * proportion * 100).rounded() / 100,
                            "payment_method": "Government Subsidy",
                            "support_program_name": GovernmentSupportProgram.thaiChuaThaiPlus,
                            "transaction_reference": reference,
                            "support_government_rate": GovernmentSupportProgram.governmentRate
                        ]
                    ]

                    _ = try await NetworkService.shared.completeCheckoutAtomic(
                        orderId: order.id,
                        payments: payments,
                        tableNumber: table.tableNumber,
                        breakdown: [
                            "grand_total": orderAmount,
                            "subtotal": order.total,
                            "tax": tax * proportion,
                            "service_charge": serviceCharge * proportion
                        ],
                        idempotencyKey: "tctp:\(checkoutRunId):\(idx):\(order.id)"
                    )
                }

                await MainActor.run {
                    paymentProcessing = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                        paymentSuccess = true
                    }
                    APHaptic.trigger()
                    NotificationCenter.default.post(name: .checkoutCompleted, object: table.tableNumber)
                }
                await NetworkService.shared.refreshAll()
            } catch {
                await MainActor.run {
                    paymentProcessing = false
                    checkoutErrorMessage = "เกิดข้อผิดพลาด: \(error.localizedDescription)"
                }
            }
        }
    }

    private func completeSplitCheckout(entries: [StaffSplitEntry]) {
        let payableOrders = orders.filter { !$0.isPaid && $0.status != "cancelled" }
        guard !payableOrders.isEmpty else { return }
        paymentProcessing = true
        checkoutErrorMessage = nil

        Task {
            do {
                let totalOrderAmt = payableOrders.map { $0.total }.reduce(0, +)
                let checkoutRunId = UUID().uuidString.lowercased()

                for (idx, order) in payableOrders.enumerated() {
                    let proportion = totalOrderAmt > 0 ? order.total / totalOrderAmt : 1.0
                    var allocated = 0.0
                    let positiveEntries = entries.filter { $0.amount > 0 }
                    let payments: [[String: Any]] = positiveEntries.enumerated().map { entryIndex, entry in
                        let amount: Double
                        if entryIndex == positiveEntries.count - 1 {
                            amount = max(0, (grandTotal * proportion) - allocated)
                        } else {
                            amount = (entry.amount * proportion * 100).rounded() / 100
                            allocated += amount
                        }
                        var p: [String: Any] = [
                            "id": UUID().uuidString.lowercased(),
                            "amount": amount,
                            "payment_method": entry.method
                        ]
                        if entry.method == "Cash" && entry.cashReceived > 0 {
                            p["cash_tendered"] = entry.cashReceived
                            p["change_due"] = max(0, entry.cashReceived - entry.amount)
                        }
                        return p
                    }

                    _ = try await NetworkService.shared.completeCheckoutAtomic(
                        orderId: order.id,
                        payments: payments,
                        tableNumber: table.tableNumber,
                        breakdown: [
                            "grand_total": (grandTotal * proportion * 100).rounded() / 100,
                            "subtotal": order.total,
                            "tax": tax * proportion,
                            "service_charge": serviceCharge * proportion
                        ],
                        idempotencyKey: "split:\(checkoutRunId):\(idx):\(order.id)"
                    )
                }

                await MainActor.run {
                    paymentProcessing = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                        paymentSuccess = true
                    }
                    APHaptic.trigger()
                    NotificationCenter.default.post(name: .checkoutCompleted, object: table.tableNumber)
                }
                await NetworkService.shared.refreshAll()
            } catch {
                await MainActor.run {
                    paymentProcessing = false
                    checkoutErrorMessage = "เกิดข้อผิดพลาด: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Staff Pre-Bill Sheet View (100% AlphaPos Parity with PromptPay QR)

struct StaffPreBillSheetView: View {
    let tableNumber: String
    let guestCount: Int
    let orders: [Order]
    let subtotal: Double
    let tax: Double
    let taxRate: Double
    let taxType: String
    let serviceCharge: Double
    let serviceChargeRate: Double
    let grandTotal: Double

    @Environment(\.dismiss) private var dismiss
    @State private var isSendingPrint = false
    @State private var printResultSuccess: Bool? = nil
    @State private var printResultMessage: String? = nil
    @State private var qrImage: UIImage? = nil

    private var storeName: String {
        NetworkService.shared.merchantName.isEmpty ? "AlphaPos Restaurant" : NetworkService.shared.merchantName
    }
    private var storePhone: String {
        NetworkService.shared.merchantPhone.isEmpty ? "02-123-4567" : NetworkService.shared.merchantPhone
    }
    private var storeAddress: String {
        NetworkService.shared.merchantAddress.isEmpty ? "Store Main Branch" : NetworkService.shared.merchantAddress
    }
    private var promptPayNumber: String {
        NetworkService.shared.promptPayNumber
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Thermal Receipt Paper Card
                        receiptPaperView

                        // Print to iPad Printer Action
                        Button {
                            sendPrintToiPad()
                        } label: {
                            HStack(spacing: 8) {
                                if isSendingPrint {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "printer.fill")
                                }
                                Text("สั่งพิมพ์ไปยังเครื่องพิมพ์ iPad (AlphaPos)")
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(Color.appAccent)
                            .cornerRadius(APRadius.md)
                            .shadow(color: Color.appAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isSendingPrint)
                        .padding(.horizontal, 16)

                        if let msg = printResultMessage {
                            HStack(spacing: 6) {
                                Image(systemName: printResultSuccess == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(printResultSuccess == true ? .appTeal : .appRose)
                                Text(msg)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(printResultSuccess == true ? .appTeal : .appRose)
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("ใบตรวจรายการ (Pre-Bill)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
        }
        .apColorScheme()
        .onAppear {
            if !promptPayNumber.isEmpty {
                let payload = PromptPayPayloadGenerator.buildPayload(target: promptPayNumber, amount: grandTotal)
                qrImage = PromptPayPayloadGenerator.generateQR(from: payload)
            }
        }
    }

    private var receiptPaperView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(storeName)
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                if !storeAddress.isEmpty {
                    Text(storeAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                Text("TEL: \(storePhone)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)

                dashedDivider

                Text("PRE-BILL / CHECK")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                Text("NOT TAX INVOICE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.85))
                Text("UNPAID - FOR CUSTOMER REVIEW")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)

                dashedDivider
            }
            .padding(.top, 18)
            .padding(.horizontal, 16)

            // Metadata
            VStack(alignment: .leading, spacing: 3) {
                receiptMetaRow(label: "DATE", value: Date().formatted(date: .numeric, time: .standard))
                if let firstOrder = orders.first {
                    receiptMetaRow(label: "ORDER", value: orders.map(\.orderNumber).joined(separator: ", "))
                }
                receiptMetaRow(label: "TABLE", value: "\(tableNumber)   |   GUESTS: \(guestCount)")
                receiptMetaRow(label: "TYPE", value: "DINE IN")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            dashedDivider
                .padding(.horizontal, 16)

            // Line items header
            HStack {
                Text("QTY  ITEM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text("PRICE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 2)

            dashedDivider
                .padding(.horizontal, 16)

            // Line items
            VStack(spacing: 6) {
                ForEach(orders) { order in
                    ForEach(order.items.filter { $0.status != "cancelled" }) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .top) {
                                Text("\(item.quantity)x  \(item.name)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                                Spacer()
                                Text("฿\(String(format: "%.2f", item.price * Double(item.quantity)))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                            }
                            if !item.modifiers.isEmpty {
                                ForEach(item.modifiers) { mod in
                                    Text("   + \(mod.name)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            dashedDivider
                .padding(.horizontal, 16)

            // Financial Summary Rows
            VStack(spacing: 4) {
                receiptTotalRow(label: "SUBTOTAL", value: subtotal)
                if serviceCharge > 0 {
                    receiptTotalRow(label: "SERVICE CHARGE (\(Int(serviceChargeRate > 1.0 ? serviceChargeRate : serviceChargeRate * 100))%)", value: serviceCharge)
                }
                if tax > 0 {
                    receiptTotalRow(label: "\(Int(taxRate > 1.0 ? taxRate : taxRate * 100))% VAT (\(taxType.uppercased()))", value: tax)
                }
                dashedDivider
                HStack {
                    Text("AMOUNT DUE")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                    Spacer()
                    Text("฿\(String(format: "%.2f", grandTotal))")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                }
                .foregroundColor(.black)
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            dashedDivider
                .padding(.horizontal, 16)

            // PromptPay QR Section (AlphaParity)
            if !promptPayNumber.isEmpty {
                VStack(spacing: 8) {
                    Text("SCAN TO PAY - PROMPTPAY")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.black)

                    if let img = qrImage {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .padding(6)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1.5))
                    }

                    Text("PromptPay: \(promptPayNumber)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.85))

                    Text("ยอดชำระ: ฿\(String(format: "%.2f", grandTotal))")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                }
                .padding(.vertical, 8)

                dashedDivider
                    .padding(.horizontal, 16)
            }

            // Footer Notice
            VStack(spacing: 2) {
                Text("Please review your order.")
                    .font(.system(size: 10, design: .monospaced))
                Text("Payment has not been received.")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(.gray)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
    }

    private var dashedDivider: some View {
        Text(String(repeating: "-", count: 40))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.gray.opacity(0.6))
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .padding(.vertical, 2)
    }

    private func receiptMetaRow(label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black.opacity(0.8))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.black.opacity(0.9))
            Spacer()
        }
    }

    private func receiptTotalRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.black.opacity(0.8))
            Spacer()
            Text("฿\(String(format: "%.2f", value))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black.opacity(0.9))
        }
    }

    private func sendPrintToiPad() {
        guard !isSendingPrint else { return }
        isSendingPrint = true
        printResultMessage = nil
        APHaptic.trigger()

        Task {
            do {
                let ids = orders.map(\.id)
                try await NetworkService.shared.requestPreBillPrint(orderIds: ids, tableNumber: tableNumber)
                await MainActor.run {
                    isSendingPrint = false
                    printResultSuccess = true
                    printResultMessage = "ส่งคำสั่งพิมพ์ไปยัง iPad เรียบร้อยแล้ว!"
                    APHaptic.trigger()
                }
            } catch {
                await MainActor.run {
                    isSendingPrint = false
                    printResultSuccess = false
                    printResultMessage = "ส่งพิมพ์ไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Staff Cash Payment Modal View (AlphaPos Parity)

struct StaffCashPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var banknoteAccumulated: Double = 0.0
    @State private var keypadSuffix: String = ""
    @State private var showSuccessOverlay = false
    @State private var delayRemaining = 3.0
    @State private var isProcessing = false
    @State private var confirmedCashReceived: Double = 0.0
    @State private var confirmedChangeDue: Double = 0.0

    private var cashReceived: Double {
        let suffixVal = Double(keypadSuffix) ?? 0.0
        return banknoteAccumulated + suffixVal
    }

    private var cashReceivedDisplayText: String {
        if banknoteAccumulated == 0 && keypadSuffix.isEmpty { return "0" }
        if !keypadSuffix.isEmpty {
            let total = banknoteAccumulated + (Double(keypadSuffix) ?? 0.0)
            return keypadSuffix.contains(".") ? String(format: "%.2f", total) : String(format: "%.0f", total)
        } else {
            return formatAmountNoCent(banknoteAccumulated)
        }
    }

    private var changeDue: Double { cashReceived - totalAmount }
    private var isAmountSufficient: Bool { cashReceived >= totalAmount && cashReceived > 0 }

    private struct QuickCashOption: Identifiable {
        let id: String
        let label: String
        let amount: Double
        let isExact: Bool
    }

    private var quickCashOptions: [QuickCashOption] {
        [
            QuickCashOption(id: "exact", label: "พอดี (Exact)", amount: totalAmount, isExact: true),
            QuickCashOption(id: "note_100", label: "฿100", amount: 100.0, isExact: false),
            QuickCashOption(id: "note_500", label: "฿500", amount: 500.0, isExact: false),
            QuickCashOption(id: "note_1000", label: "฿1,000", amount: 1000.0, isExact: false)
        ]
    }

    private func handleQuickCashTap(_ option: QuickCashOption) {
        APHaptic.trigger()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
            if option.isExact {
                banknoteAccumulated = totalAmount
                keypadSuffix = ""
            } else {
                banknoteAccumulated += option.amount
            }
        }
    }

    private func handleKeypadInput(_ input: String) {
        APHaptic.trigger()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
            if input == "⌫" {
                if !keypadSuffix.isEmpty {
                    keypadSuffix.removeLast()
                } else if banknoteAccumulated > 0 {
                    banknoteAccumulated = 0
                }
            } else if input == "." {
                if !keypadSuffix.contains(".") {
                    keypadSuffix = keypadSuffix.isEmpty ? "0." : (keypadSuffix + ".")
                }
            } else if input == "00" {
                if !keypadSuffix.isEmpty && keypadSuffix != "0" && keypadSuffix.count <= 6 {
                    keypadSuffix += "00"
                }
            } else {
                if keypadSuffix == "0" {
                    keypadSuffix = input
                } else if keypadSuffix.count < 8 {
                    keypadSuffix += input
                }
            }
        }
    }

    private func formatAmountNoCent(_ amount: Double) -> String {
        amount.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", amount) : String(format: "%.2f", amount)
    }

    private func confirmPayment() {
        guard !isProcessing, isAmountSufficient else { return }
        isProcessing = true
        APHaptic.trigger()

        let tenderedSnapshot = cashReceived
        let changeSnapshot = max(0, tenderedSnapshot - totalAmount)
        confirmedCashReceived = tenderedSnapshot
        confirmedChangeDue = changeSnapshot

        onConfirm(tenderedSnapshot)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        let holdSeconds = changeSnapshot > 0 ? 3 : 2
        delayRemaining = Double(holdSeconds)
        Task {
            for _ in 0..<holdSeconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if delayRemaining > 1 { delayRemaining -= 1 }
                }
            }
            await MainActor.run { dismiss() }
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
            .navigationTitle("ชำระด้วยเงินสด")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showSuccessOverlay ? "เสร็จสิ้น" : "ยกเลิก") { dismiss() }
                        .foregroundColor(.appAccent)
                }
            }
        }
        .apColorScheme()
    }

    private var mainContentView: some View {
        VStack(spacing: APSpacing.md) {
            // Bill Total vs Change Due Header Card
            HStack(spacing: APSpacing.sm) {
                VStack(spacing: 3) {
                    Text("ยอดที่ต้องชำระ")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textSecondary)
                    Text("฿\(totalAmount, specifier: "%.2f")")
                        .font(.title3.weight(.black))
                        .foregroundStyle(APGradient.accent)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))

                VStack(spacing: 3) {
                    if isAmountSufficient {
                        Text("เงินทอน (Change)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.appTeal)
                        Text("฿\(changeDue, specifier: "%.2f")")
                            .font(.title3.weight(.black))
                            .foregroundColor(.appTeal)
                            .contentTransition(.numericText())
                    } else {
                        Text("ยังขาดอีก")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.appRose)
                        Text("฿\(totalAmount - cashReceived, specifier: "%.2f")")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.appRose)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isAmountSufficient ? Color.appTeal.opacity(0.08) : Color.appRose.opacity(0.08))
                .cornerRadius(APRadius.md)
                .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(isAmountSufficient ? Color.appTeal.opacity(0.35) : Color.appRose.opacity(0.35), lineWidth: 1))
            }

            // Cash Received Input Box
            HStack {
                Text("฿").font(.title2.weight(.black)).foregroundColor(.textPrimary)
                Spacer()
                Text(cashReceivedDisplayText)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(cashReceived == 0 ? .textTertiary : .textPrimary)
                    .contentTransition(.numericText())
                if !keypadSuffix.isEmpty || banknoteAccumulated > 0 {
                    Button {
                        withAnimation {
                            keypadSuffix = ""
                            banknoteAccumulated = 0
                        }
                        APHaptic.trigger()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textSecondary).font(.system(size: 20))
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .background(Color.appSurface).cornerRadius(APRadius.md)
            .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))

            // Quick Cash Shortcuts
            HStack(spacing: APSpacing.xs) {
                ForEach(quickCashOptions) { opt in
                    Button {
                        handleQuickCashTap(opt)
                    } label: {
                        Text(opt.label)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(APRadius.sm)
                            .overlay(RoundedRectangle(cornerRadius: APRadius.sm).stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Numberpad Grid
            VStack(spacing: 8) {
                let keys = [["7","8","9"],["4","5","6"],["1","2","3"],[".","0","⌫"]]
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            Button { handleKeypadInput(key) } label: {
                                Group {
                                    if key == "⌫" {
                                        Image(systemName: "delete.left.fill").font(.title2).foregroundColor(.appRose)
                                    } else {
                                        Text(key).font(.title2.weight(.bold))
                                            .foregroundColor(key == "." ? .textSecondary : .textPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Color.appSurfaceHigh).cornerRadius(APRadius.sm)
                                .overlay(RoundedRectangle(cornerRadius: APRadius.sm).stroke(Color.appBorderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()

            // Confirm Button
            Button(action: confirmPayment) {
                Label("ยืนยันรับเงินสด ฿\(String(format: "%.2f", cashReceived))", systemImage: "checkmark.circle.fill")
                    .apGradientButton(
                        gradient: isAmountSufficient ? APGradient.positive : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .leading, endPoint: .trailing),
                        shadow: isAmountSufficient ? APShadow.positiveGlow : APShadow.card,
                        disabled: !isAmountSufficient
                    )
            }
            .disabled(!isAmountSufficient || isProcessing)
        }
        .padding(APSpacing.md)
    }

    private var successOverlayView: some View {
        VStack(spacing: 24) {
            Spacer()
            AnimatedPaymentSuccessMark()
            VStack(spacing: 6) {
                Text("รับชำระเงินสดสำเร็จ!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("รับเงิน: ฿\(String(format: "%.2f", confirmedCashReceived))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }

            if confirmedChangeDue > 0 {
                VStack(spacing: 6) {
                    Text("เงินทอนลูกค้า (Change Due)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textSecondary)
                    Text("฿\(String(format: "%.2f", confirmedChangeDue))")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.appTeal)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Color.appTeal.opacity(0.08))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appTeal.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 24)
            }

            Button {
                dismiss()
            } label: {
                Text("เสร็จสิ้น (\(Int(delayRemaining))s)")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundColor(.white).background(Color.appAccent)
                    .cornerRadius(APRadius.md)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

// MARK: - Staff QR Payment Modal View (AlphaPos Parity Thai QR Frame)

struct StaffQRPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: UIImage? = nil

    private var promptPayNumber: String {
        NetworkService.shared.promptPayNumber
    }

    private var isConfigured: Bool {
        !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            if !isConfigured {
                                VStack(spacing: APSpacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.appAmber)
                                    Text("ยังไม่ได้ตั้งค่าเบอร์ PromptPay")
                                        .font(.headline.weight(.bold))
                                    Text("กรุณาตั้งค่าเบอร์ PromptPay ใน Store Settings ของ AlphaPos ก่อน")
                                        .font(.subheadline).foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(APSpacing.lg)
                                .frame(maxWidth: .infinity)
                                .background(Color.appSurface)
                                .cornerRadius(APRadius.lg)
                            } else {
                                // Thai QR Frame
                                StaffThaiQRPaymentFrame(
                                    storeName: NetworkService.shared.merchantName.isEmpty ? "AlphaPos Store" : NetworkService.shared.merchantName,
                                    promptPayNumber: promptPayNumber,
                                    amount: totalAmount,
                                    qrImage: qrImage
                                )

                                // Instruction notice
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.appTeal)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("พร้อมเพย์ตรง · ล็อกยอดเงินตามบิล")
                                            .font(.footnote.weight(.bold))
                                            .foregroundColor(.appTeal)
                                        Text("ระบบได้สร้าง QR Code พร้อมเพย์ตามยอดบิล ฿\(String(format: "%.2f", totalAmount)) เรียบร้อยแล้ว กรุณาตรวจสอบสลิปก่อนกดยืนยัน")
                                            .font(.footnote).foregroundColor(.textSecondary)
                                    }
                                }
                                .padding()
                                .background(Color.appSurface)
                                .cornerRadius(APRadius.md)
                                .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                            }
                        }
                        .padding(APSpacing.md)
                        .frame(maxWidth: 440)
                    }

                    // Pinned confirm footer
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            APHaptic.trigger()
                            onConfirm()
                            dismiss()
                        } label: {
                            Label("ยืนยันรับชำระเงินเรียบร้อย (฿\(String(format: "%.2f", totalAmount)))",
                                  systemImage: "checkmark.circle.fill")
                                .apGradientButton(
                                    gradient: APGradient.positive,
                                    shadow: APShadow.positiveGlow,
                                    disabled: !isConfigured
                                )
                        }
                        .disabled(!isConfigured)
                        .padding(APSpacing.md)
                    }
                    .background(Color.appSurface)
                }
            }
            .navigationTitle("PromptPay QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
            }
        }
        .apColorScheme()
        .onAppear {
            if isConfigured {
                let payload = PromptPayPayloadGenerator.buildPayload(target: promptPayNumber, amount: totalAmount)
                qrImage = PromptPayPayloadGenerator.generateQR(from: payload)
            }
        }
    }
}

// MARK: - Staff Credit Card Payment Modal View (AlphaPos Parity)

struct StaffCreditCardPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.lg) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.appRose.opacity(0.12)).frame(width: 72, height: 72)
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 34, weight: .bold)).foregroundColor(.appRose)
                        }
                        Text("ชำระด้วยบัตรเครดิต / เดบิต")
                            .font(.title3.weight(.bold))
                        Text("กรุณารูด เสียบ หรือแตะบัตรที่เครื่อง EDC/Card Terminal")
                            .font(.subheadline).foregroundColor(.textSecondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 10) {
                        HStack {
                            Text("ยอดชำระเต็มจำนวน").foregroundColor(.textSecondary)
                            Spacer()
                            Text("฿\(String(format: "%.2f", totalAmount))")
                                .font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                        }
                        Divider()
                        HStack(spacing: 12) {
                            Text("VISA").font(.footnote.weight(.black)).italic().foregroundColor(.appAccent)
                            Text("Mastercard").font(.footnote.weight(.bold)).foregroundColor(.appAmber)
                            Text("JCB").font(.footnote.weight(.bold)).foregroundColor(.appTeal)
                            Text("UnionPay").font(.footnote.weight(.bold)).foregroundColor(.appRose)
                        }
                    }
                    .padding(16)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))

                    Spacer()

                    Button {
                        APHaptic.trigger()
                        onConfirm()
                        dismiss()
                    } label: {
                        Label("ยืนยันรูดบัตรสำเร็จ (฿\(String(format: "%.2f", totalAmount)))", systemImage: "checkmark.circle.fill")
                            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow)
                    }
                }
                .padding(APSpacing.md)
            }
            .navigationTitle("Credit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Staff Thai Chua Thai Plus Modal View (AlphaPos Parity)

struct StaffThaiChuaThaiPlusPaymentModal: View {
    let totalAmount: Double
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""

    private var split: (citizen: Double, government: Double) {
        GovernmentSupportProgram.split(total: totalAmount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    VStack(spacing: 8) {
                        Image("ThaiChuaThaiPlusLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 100)
                        Text(GovernmentSupportProgram.thaiChuaThaiPlus)
                            .font(.title2.bold())
                        Text("วิธีชำระเฉพาะโครงการร่วมจ่าย")
                            .font(.subheadline).foregroundColor(.textSecondary)
                    }

                    VStack(spacing: 12) {
                        supportRow("ยอดขายเต็มจำนวน (100%)", amount: totalAmount, color: .textPrimary)
                        Divider()
                        supportRow("รัฐสนับสนุน 60%", amount: split.government, color: .appAccent)
                        supportRow("ประชาชนชำระผ่านโครงการ 40%", amount: split.citizen, color: .appTeal)
                    }
                    .padding(APSpacing.lg)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("เลขอ้างอิงรายการโครงการ (ไม่บังคับ)")
                            .font(.caption.bold()).foregroundColor(.textSecondary)
                        TextField("กรอกตอนนี้ หรือเพิ่มภายหลังในหน้ากระทบยอด", text: $reference)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Text("ยอดสนับสนุน 60% จะบันทึกเป็นลูกหนี้รอรับจากรัฐ ไม่ถือเป็นเงินสดหรือ PromptPay")
                        .font(.footnote).foregroundColor(.appAmber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(APSpacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("ไทยช่วยไทย Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button {
                        APHaptic.trigger()
                        onConfirm(reference.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } label: {
                        Label("ชำระเงินและออกใบเสร็จ (฿\(String(format: "%.2f", totalAmount)))", systemImage: "checkmark.seal.fill")
                            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow)
                    }
                }
                .padding(APSpacing.md)
                .background(.ultraThinMaterial)
            }
        }
        .apColorScheme()
    }

    private func supportRow(_ label: String, amount: Double, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.textSecondary)
            Spacer()
            Text("฿\(String(format: "%.2f", amount))")
                .font(.headline.monospacedDigit()).foregroundColor(color)
        }
    }
}

// MARK: - Staff Split Payment View (AlphaPos Parity Multi-Tender)

struct StaffSplitPaymentView: View {
    let totalAmount: Double
    let onComplete: ([StaffSplitEntry]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [StaffSplitEntry] = []
    @State private var splitByGuests = 2
    @State private var showEqualSplit = false

    private var paidTotal: Double { entries.reduce(0.0) { $0 + $1.amount } }
    private var remainingBalance: Double { max(0, totalAmount - paidTotal) }
    private var isBalanced: Bool { abs(paidTotal - totalAmount) < 0.01 }
    private var isOverpaid: Bool { paidTotal > totalAmount + 0.01 }

    static let paymentMethods = ["Cash", "QR PromptPay", "Credit Card"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            // Bill total & balance progress card
                            billTotalCard

                            // Equal split by guests stepper
                            equalSplitSection

                            // Payment entries
                            VStack(spacing: APSpacing.sm) {
                                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                                    paymentEntryRow(entry: entry, index: idx)
                                }
                            }

                            // Add payment method button
                            if entries.count < 4 && !isBalanced {
                                Button {
                                    APHaptic.trigger()
                                    entries.append(StaffSplitEntry(
                                        method: "QR PromptPay",
                                        amount: remainingBalance,
                                        amountText: remainingBalance > 0 ? String(format: "%.2f", remainingBalance) : ""
                                    ))
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("+ เพิ่มช่องทางชำระเงิน")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.appAccent)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(Color.appSurface)
                                    .cornerRadius(APRadius.md)
                                    .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appAccent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(APSpacing.md)
                    }

                    // Bottom confirm bar
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            APHaptic.trigger()
                            onComplete(entries)
                            dismiss()
                        } label: {
                            Label(
                                isBalanced ? "ยืนยันชำระเงิน ฿\(String(format: "%.2f", totalAmount))" : "ยืนยันชำระเงิน (ยังขาด ฿\(String(format: "%.2f", remainingBalance)))",
                                systemImage: "checkmark.circle.fill"
                            )
                            .apGradientButton(
                                gradient: isBalanced ? APGradient.positive : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .leading, endPoint: .trailing),
                                shadow: isBalanced ? APShadow.positiveGlow : APShadow.card,
                                disabled: !isBalanced
                            )
                        }
                        .disabled(!isBalanced)
                        .padding(APSpacing.md)
                    }
                    .background(Color.appSurface)
                }
            }
            .navigationTitle("แบ่งชำระเงิน (Split Payment)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
            }
        }
        .apColorScheme()
        .onAppear {
            if entries.isEmpty {
                entries = [StaffSplitEntry(method: "Cash", amount: totalAmount, amountText: String(format: "%.2f", totalAmount))]
            }
        }
    }

    private var billTotalCard: some View {
        VStack(spacing: APSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ยอดรวมบิล").font(.subheadline).foregroundColor(.textSecondary)
                    Text("฿\(totalAmount, specifier: "%.2f")")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ยอดคงเหลือ").font(.subheadline).foregroundColor(.textSecondary)
                    Text("฿\(remainingBalance, specifier: "%.2f")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(isBalanced ? .appTeal : .appRose)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.appSurfaceHigh)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOverpaid ? AnyShapeStyle(APGradient.destructive) : isBalanced ? AnyShapeStyle(APGradient.positive) : AnyShapeStyle(APGradient.accent))
                        .frame(width: min(geo.size.width, geo.size.width * CGFloat(paidTotal / max(totalAmount, 1))))
                        .animation(.spring(response: 0.4), value: paidTotal)
                }
            }
            .frame(height: 6)

            HStack {
                Text("ชำระแล้ว: ฿\(paidTotal, specifier: "%.2f")").font(.caption).foregroundColor(.textSecondary)
                Spacer()
                if isBalanced {
                    Label("ยอดครบถ้วน", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundColor(.appTeal)
                } else if isOverpaid {
                    Label("จ่ายเกิน", systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundColor(.appRose)
                }
            }
        }
        .apCard()
    }

    private var equalSplitSection: some View {
        VStack(spacing: APSpacing.sm) {
            Button {
                withAnimation { showEqualSplit.toggle() }
                APHaptic.trigger()
            } label: {
                HStack {
                    Image(systemName: "person.2.fill").foregroundColor(.appAccent)
                    Text("แบ่งจ่ายเท่ากันตามจำนวนคน").font(.subheadline.weight(.semibold)).foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: showEqualSplit ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.textSecondary)
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if showEqualSplit {
                HStack(spacing: APSpacing.md) {
                    Text("จำนวนคน").font(.subheadline).foregroundColor(.textSecondary)
                    HStack(spacing: 0) {
                        Button {
                            if splitByGuests > 2 { splitByGuests -= 1 }
                            APHaptic.trigger()
                        } label: {
                            Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.appAccent)
                                .frame(width: 34, height: 34).background(Color.appSurfaceHigh).cornerRadius(APRadius.sm)
                        }
                        Text("\(splitByGuests)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.textPrimary).frame(width: 44)
                        Button {
                            splitByGuests += 1
                            APHaptic.trigger()
                        } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.appAccent)
                                .frame(width: 34, height: 34).background(Color.appSurfaceHigh).cornerRadius(APRadius.sm)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("คนละ").font(.caption).foregroundColor(.textSecondary)
                        Text("฿\(totalAmount / Double(splitByGuests), specifier: "%.2f")")
                            .font(.subheadline.weight(.bold)).foregroundColor(.textPrimary)
                    }
                    Button {
                        splitEqually()
                        APHaptic.trigger()
                    } label: {
                        Text("นำไปใช้")
                            .font(.subheadline.weight(.bold)).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.appAccent).cornerRadius(APRadius.sm)
                    }
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
            }
        }
    }

    private func splitEqually() {
        guard splitByGuests > 0 else { return }
        let base = (totalAmount / Double(splitByGuests) * 100).rounded() / 100
        entries = (0..<splitByGuests).map { idx in
            let amt = (idx == splitByGuests - 1) ? max(0, totalAmount - (base * Double(splitByGuests - 1))) : base
            return StaffSplitEntry(method: "QR PromptPay", amount: amt, amountText: String(format: "%.2f", amt))
        }
    }

    private func paymentEntryRow(entry: StaffSplitEntry, index: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("ช่องทางที่ \(index + 1)")
                    .font(.caption.weight(.bold)).foregroundColor(.textSecondary)
                Spacer()
                if entries.count > 1 {
                    Button {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundColor(.appRose)
                    }
                }
            }

            HStack(spacing: 8) {
                // Method Chips
                ForEach(["Cash", "QR PromptPay", "Credit Card"], id: \.self) { method in
                    let isSelected = entry.method == method
                    Button {
                        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                            entries[idx].method = method
                        }
                    } label: {
                        Text(method == "Cash" ? "เงินสด" : method == "QR PromptPay" ? "QR" : "บัตร")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isSelected ? .white : .textSecondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Amount Field
                HStack {
                    Text("฿").font(.subheadline.bold()).foregroundColor(.textSecondary)
                    TextField("0.00", text: Binding(
                        get: { entry.amountText },
                        set: { val in
                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[idx].amountText = val
                                entries[idx].amount = Double(val) ?? 0.0
                            }
                        }
                    ))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)
                .frame(width: 110)
            }
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}

// MARK: - Staff Thai QR Payment Frame (Standard Compliant)

struct StaffThaiQRPaymentFrame: View {
    let storeName: String
    let promptPayNumber: String
    let amount: Double
    let qrImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 0) {
                    Text("THAI QR PAYMENT")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("พร้อมเพย์ (PromptPay)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Text("PromptPay")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(hex: "0C2B64"))

            // QR Code Content
            VStack(spacing: 12) {
                Text(storeName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 12)

                if let img = qrImage {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
                } else {
                    ProgressView().frame(width: 200, height: 200)
                }

                VStack(spacing: 2) {
                    Text(promptPayNumber)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.textSecondary)
                    Text("฿\(String(format: "%.2f", amount))")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(APGradient.accent)
                }
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }
}

// MARK: - PromptPay Payload Generator (EMVCo Standard)

enum PromptPayPayloadGenerator {
    static func buildPayload(target: String, amount: Double) -> String {
        let sanitized = target.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        var accountInfo = "0016A000000677010111"
        if sanitized.count == 13 {
            accountInfo += "0213\(sanitized)"
        } else {
            var phone = sanitized
            if phone.hasPrefix("0") { phone.removeFirst() }
            accountInfo += "0113" + "0066" + phone
        }
        var payload = "000201010212"
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764"
        let amtStr = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amtStr.count, amtStr)
        payload += "5802TH6304"
        let crc = crc16emv(payload)
        return payload + String(format: "%04X", crc)
    }

    private static func crc16emv(_ str: String) -> UInt16 {
        let bytes = Array(str.utf8)
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            for i in 0..<8 {
                let bit = ((byte >> (7 - i)) & 1) == 1
                let c15 = ((crc >> 15) & 1) == 1
                crc <<= 1
                if c15 != bit { crc ^= 0x1021 }
            }
        }
        return crc
    }

    static func generateQR(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Animated Payment Success Mark

struct AnimatedPaymentSuccessMark: View {
    @State private var scale = 0.4
    @State private var opacity = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.appTeal.opacity(0.35), Color.clear],
                    center: .center, startRadius: 0, endRadius: 60
                ))
                .frame(width: 120, height: 120)

            Circle()
                .fill(Color.appTeal)
                .frame(width: 76, height: 76)
                .shadow(color: Color.appTeal.opacity(0.45), radius: 16, x: 0, y: 8)

            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
