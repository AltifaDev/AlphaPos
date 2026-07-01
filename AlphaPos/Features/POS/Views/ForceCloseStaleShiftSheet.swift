import SwiftUI
import SwiftData

struct ForceCloseStaleShiftSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    
    let session: RegisterSession
    
    @Query(sort: \Payment.paidAt, order: .reverse) private var allPayments: [Payment]
    @Query(sort: \CashMovement.updatedAt, order: .reverse) private var allCashMovements: [CashMovement]
    @Query(sort: \User.username) private var users: [User]
    
    @State private var actualCashString = ""
    @State private var closingNotes = ""
    
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    
    // Financial calculations for this session
    private var cashSalesAmount: Double {
        allPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                payment.paymentMethod.lowercased() == "cash" &&
                payment.paidAt >= session.openedAt
            }
            .reduce(0.0) { $0 + $1.amount }
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
        session.openingCash + cashSalesAmount + cashInAmount - cashOutAmount
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
        let actual = Double(actualCashString) ?? 0.0
        let discrepancy = actual - expectedCash
        
        session.closedAt = Date()
        session.expectedClosingCash = expectedCash
        session.actualClosingCash = actual
        session.cashDiscrepancy = discrepancy
        session.closedByUserId = users.first?.id ?? UUID()
        session.notes = closingNotes.isEmpty ? nil : closingNotes
        session.isSynced = false
        session.updatedAt = Date()
        
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
        
        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(session)
        }
        
        onComplete?()
        dismiss()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
