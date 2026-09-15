import SwiftUI
import SwiftData

struct ForceCloseStaleShiftSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    
    let session: RegisterSession
    
    @Query(sort: \Payment.paidAt, order: .reverse) private var allPayments: [Payment]
    @Query(sort: \CashMovement.updatedAt, order: .reverse) private var allCashMovements: [CashMovement]
    @Query private var allRefunds: [RefundTransaction]
    @Query private var allRegisterSessions: [RegisterSession]
    @Query(sort: \User.username) private var users: [User]
    
    @State private var actualCashString = ""
    @State private var closingNotes = ""
    
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    
    // Financial calculations for this session
    private func financialScope(closingAt: Date) -> ForceCloseSessionScope {
        ForceCloseSessionScope(session: session, sessions: allRegisterSessions, closingAt: closingAt)
    }

    private var cashSalesAmount: Double {
        let scope = financialScope(closingAt: Date())
        return allPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.isCaptured &&
                payment.paymentMethod.lowercased() == "cash" &&
                scope.contains(payment)
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var cashRefundsAmount: Double {
        let scope = financialScope(closingAt: Date())
        return allRefunds
            .filter {
                !$0.isDeleted &&
                $0.status == "completed" &&
                scope.contains($0) &&
                ($0.refundMethod == "cash" || $0.originalPayment?.paymentMethod == "cash")
            }
            .reduce(0.0) { $0 + $1.refundAmount }
    }
    
    private var cashInAmount: Double {
        allCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_in" || movement.movementType == "paid_in")
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var cashOutAmount: Double {
        allCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_out" || movement.movementType == "paid_out")
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var expectedCash: Double {
        session.openingCash + cashSalesAmount + cashInAmount - cashOutAmount - cashRefundsAmount
    }
    
    private func localT(_ key: String) -> String {
        let isThai = lm.currentLanguage == .thai
        switch key {
        case "stale_shift_title":
            return isThai ? "พบประวัติกะค้างคืนตกค้าง" : "Overnight Shift Detected"
        case "stale_shift_subtitle":
            return isThai ? "มีกะการทำงานที่ลืมปิดการทำงานค้างไว้ กรุณาเคลียร์ยอดและปิดกะเก่าเพื่อเริ่มต้นวันใหม่" : "There is an active shift left open from a previous day. Please reconcile and close it to begin."
        case "opened_date_label":
            return isThai ? "เปิดกะเมื่อ:" : "Opened At:"
        case "reconcile_and_close_btn":
            return isThai ? "เคลียร์ยอดเงินสด & บังคับปิดกะเก่า" : "Reconcile & Close Past Shift"
        default:
            return key
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: APSpacing.lg) {
                        // Stale Warning Header
                        VStack(spacing: APSpacing.xs) {
                            ZStack {
                                Circle()
                                    .fill(Color.appSurface)
                                    .frame(width: 80, height: 80)
                                    .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.appAmber)
                            }
                            .padding(.top, 24)
                            
                            Text(localT("stale_shift_title"))
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            
                            Text(localT("stale_shift_subtitle"))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        // Shift Details & Expected Cash Card
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(localT("opened_date_label"))
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text(formatDate(session.openedAt))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.textPrimary)
                            }
                            
                            Divider().background(Color.appDivider)
                            
                            HStack {
                                Text("expected_cash_label".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text("฿\(expectedCash.formatted(.number.precision(.fractionLength(2))))")
                                    .font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                                    .foregroundColor(.appTeal)
                            }
                        }
                        .apCard()
                        .padding(.horizontal)
                        
                        // Counting Cash Form
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("actual_cash_counted_label".t)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                
                                HStack {
                                    Text("฿").font(.title3).foregroundColor(.textSecondary)
                                    TextField("0.00", text: $actualCashString)
                                        .font(.title3).fontWeight(.bold)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.plain)
                                }
                                .padding(14)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(APRadius.md)
                            }
                            
                            // Discrepancy indicator
                            let actual = Double(actualCashString) ?? 0.0
                            let discrepancy = actual - expectedCash
                            HStack {
                                Text("discrepancy_label".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                if discrepancy == 0.0 {
                                    Text("balanced_option".t)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(.appTeal)
                                } else {
                                    Text("\(discrepancy > 0 ? "+" : "")฿\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\(discrepancy > 0 ? "overage_label".t : "shortage_label".t))")
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(discrepancy > 0 ? .appTeal : .appRose)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("closing_notes_label".t)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                TextField("opening_notes_placeholder".t, text: $closingNotes)
                                    .padding(12)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.md)
                                    .textFieldStyle(.plain)
                            }
                            
                            Button(action: closeStaleSession) {
                                Label(localT("reconcile_and_close_btn"), systemImage: "lock.fill")
                                    .apGradientButton(gradient: APGradient.destructive, shadow: APShadow.positiveGlow)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                        .apCard()
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("shift_reconciliation_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        onCancel?()
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }
            }
        }
        .onAppear {
            actualCashString = String(format: "%.2f", expectedCash)
        }
    }
    
    private func closeStaleSession() {
        let closeTime = Date()
        let scope = financialScope(closingAt: closeTime)
        let payments = allPayments.filter {
            !$0.isDeleted && scope.contains($0)
        }
        let captured = payments.filter(\.isCaptured)
        var orderMap: [UUID: Order] = [:]
        for payment in captured {
            if let order = payment.order { orderMap[order.id] = order }
        }
        let orders = orderMap.values.filter(\.isRecognizedSale)
        let refunds = allRefunds.filter {
            !$0.isDeleted && $0.status == "completed" &&
            scope.contains($0)
        }
        let cashRefunds = refunds.filter {
            $0.refundMethod == "cash" || $0.originalPayment?.paymentMethod == "cash"
        }.reduce(0.0) { $0 + $1.refundAmount }
        var tenderValues: [String: (amount: Double, count: Int)] = [:]
        for payment in captured {
            let raw = payment.paymentMethod.lowercased()
            let name = raw == "cash" ? (lm.currentLanguage == .thai ? "เงินสด" : "Cash") : payment.paymentMethod
            let current = tenderValues[name] ?? (0, 0)
            tenderValues[name] = (current.amount + payment.amount, current.count + 1)
        }
        let tenders = tenderValues.map {
            ShiftTenderSummary(method: $0.key, count: $0.value.count, received: $0.value.amount, refunded: 0)
        }.sorted { $0.received > $1.received }

        let actual = Double(actualCashString) ?? 0.0
        let capturedCash = captured
            .filter { $0.paymentMethod.lowercased() == "cash" }
            .reduce(0.0) { $0 + $1.amount }
        let correctedExpectedCash = session.openingCash + capturedCash + cashInAmount - cashOutAmount - cashRefunds
        let discrepancy = actual - correctedExpectedCash
        
        session.closedAt = closeTime
        session.expectedClosingCash = correctedExpectedCash
        session.actualClosingCash = actual
        session.cashDiscrepancy = discrepancy
        session.closedByUserId = users.first?.id ?? UUID()
        session.notes = closingNotes.isEmpty ? nil : closingNotes
        session.isSynced = false
        session.updatedAt = Date()

        let grossSales = orders.reduce(0.0) { $0 + $1.total + $1.discount }
        let discounts = orders.reduce(0.0) { $0 + $1.discount }
        let refundTotal = refunds.reduce(0.0) { $0 + $1.refundAmount }
        let report = ShiftReport(
            registerSession: session,
            reportType: "Z",
            grossSales: grossSales,
            netSales: max(0, grossSales - discounts - refundTotal),
            totalTax: orders.reduce(0.0) { $0 + $1.tax },
            totalDiscounts: discounts,
            totalRefunds: refundTotal,
            cashExpected: correctedExpectedCash,
            cashActual: actual,
            overShort: discrepancy
        )
        modelContext.insert(report)
        AccountingLedgerService.createClosureSnapshot(
            session: session,
            report: report,
            cashIn: cashInAmount,
            cashOut: cashOutAmount,
            transactionCount: captured.count,
            generatedByUserId: session.closedByUserId,
            in: modelContext
        )
        
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
        
        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(session)
            _ = try? await NetworkManager.shared.uploadShiftReportDetailed(report)
            _ = await PrintService.shared.printZReport(
                session: session,
                report: report,
                tenders: tenders,
                receiptCount: orders.count,
                failedPaymentCount: payments.filter { $0.status == "failed" }.count,
                cashMovementsIn: cashInAmount,
                cashMovementsOut: cashOutAmount,
                openedBy: displayName(for: session.openedByUserId),
                closedBy: displayName(for: session.closedByUserId),
                isThai: lm.currentLanguage == .thai
            )
        }
        
        onComplete?()
        dismiss()
    }

    private func displayName(for userId: UUID?) -> String {
        guard let userId, let user = users.first(where: { $0.id == userId }) else { return "" }
        return user.username
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
