import SwiftUI
import SwiftData

struct CashDrawerManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    
    // Fetch all non-deleted sessions (active and past)
    @Query(filter: #Predicate<RegisterSession> { !$0.isDeleted }, sort: \RegisterSession.openedAt, order: .reverse)
    private var allSessions: [RegisterSession]
    
    // Fetch payments and cash movements for calculations
    @Query(sort: \Payment.paidAt, order: .reverse) private var allPayments: [Payment]
    @Query(sort: \CashMovement.updatedAt, order: .reverse) private var allCashMovements: [CashMovement]
    @Query(sort: \User.username) private var users: [User]
    @Query private var employees: [Employee]
    @Query private var allRefunds: [RefundTransaction]
    
    @State private var openingCashString = "1000"
    @State private var openingNotes = ""
    @State private var selectedSubTab = 0 // 0: Current Shift, 1: Shift History
    @State private var animateHistory = false
    
    // Add movement modal states
    @State private var showMovementModal = false
    @State private var movementAmountString = ""
    @State private var movementReason = ""
    @State private var movementType = "paid_in" // "paid_in", "paid_out"
    
    // Close shift states
    @State private var showCloseModal = false
    @State private var actualCashString = ""
    @State private var closingNotes = ""
    @State private var zReportSession: RegisterSession? = nil
    
    // Active session helper
    private var activeSession: RegisterSession? {
        allSessions.first { $0.closedAt == nil }
    }
    
    // Financial calculations for active session
    private var cashSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                payment.paymentMethod.lowercased() == "cash" &&
                payment.paidAt >= session.openedAt
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var cashInAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_in" || movement.movementType == "paid_in")
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var cashOutAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_out" || movement.movementType == "paid_out")
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var cardSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                ["card", "credit_card", "debit_card"].contains(payment.paymentMethod.lowercased()) &&
                payment.paidAt >= session.openedAt
            }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    private var qrSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                ["qr", "promptpay", "transfer", "bank_transfer"].contains(payment.paymentMethod.lowercased()) &&
                payment.paidAt >= session.openedAt
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var refundsAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return allRefunds
            .filter { refund in
                !refund.isDeleted &&
                refund.status == "completed" &&
                refund.updatedAt >= session.openedAt
            }
            .reduce(0.0) { $0 + $1.refundAmount }
    }
    
    private var expectedCash: Double {
        guard let session = activeSession else { return 0.0 }
        return session.openingCash + cashSalesAmount + cashInAmount - cashOutAmount
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { selectedSubTab },
                set: { val in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        selectedSubTab = val
                    }
                }
            )) {
                Text(localT("current_shift_tab")).tag(0)
                Text(localT("shift_history_tab")).tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                Group {
                    if selectedSubTab == 0 {
                        Group {
                            if let session = activeSession {
                                openSessionView(session)
                            } else {
                                closedSessionView
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    } else {
                        shiftHistoryView
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("cash_drawer_shifts_title".t)
        .apNavBar()
        .sheet(isPresented: $showMovementModal) {
            addMovementModal
        }
        .sheet(isPresented: $showCloseModal) {
            closeShiftModal
        }
        .sheet(item: $zReportSession) { session in
            zReportView(session)
        }
    }
    
    // MARK: - Closed State View
    private var closedSessionView: some View {
        ScrollView {
            VStack(spacing: APSpacing.xl) {
                // Lock Icon header
                VStack(spacing: APSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.appRose.opacity(0.12), Color.appRose.opacity(0.01)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .fill(Color.appSurface)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.appRose.opacity(0.18), radius: 12, x: 0, y: 6)
                            .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(APGradient.destructive)
                    }
                    .padding(.top, 30)
                    
                    Text("drawer_locked_title".t)
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("drawer_locked_subtitle".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                }
                
                // Open Shift Form
                VStack(alignment: .leading, spacing: 20) {
                    Text("start_shift_header".t)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.appAccent)
                        .tracking(1.0)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("starting_cash_float_label".t)
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        
                        HStack {
                            Text("฿")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.textSecondary)
                            TextField("0.00", text: $openingCashString)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                        }
                        .padding(14)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("opening_notes_label".t)
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        
                        TextField("opening_notes_placeholder".t, text: $openingNotes)
                            .padding(14)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                            .textFieldStyle(.plain)
                    }
                    
                    Button(action: openRegisterSession) {
                        Label("open_session_btn".t, systemImage: "lock.open.fill")
                            .apGradientButton(gradient: APGradient.positive, shadow: APShadow.positiveGlow)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .apCard()
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - Open State View
    private func openSessionView(_ session: RegisterSession) -> some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // Header status
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.appTeal).frame(width: 8, height: 8)
                            Text("shift_running_title".t)
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                        }
                        Text(LocalizationManager.shared.t("opened_at_template", formatDate(session.openedAt)))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    
                    Button(action: {
                        closingNotes = ""
                        actualCashString = String(format: "%.2f", expectedCash)
                        showCloseModal = true
                        APHaptic.trigger()
                    }) {
                        Label("end_shift_btn".t, systemImage: "lock.fill")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(APGradient.destructive)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Reconciliation figures Grid
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        reconcileCard(title: "starting_float_label".t, amount: session.openingCash, subtitle: "cash_float_sub".t, color: .textPrimary)
                        reconcileCard(title: "cash_sales_label".t, amount: cashSalesAmount, subtitle: "completed_orders_sub".t, color: .appTeal)
                    }
                    GridRow {
                        reconcileCard(title: "cash_in_label".t, amount: cashInAmount, subtitle: "paid_in_sub".t, color: .appAccent)
                        reconcileCard(title: "cash_out_label".t, amount: cashOutAmount, subtitle: "paid_out_sub".t, color: .appRose)
                    }
                }
                .padding(.horizontal)
                
                // Expected Cash Highlight
                VStack(spacing: 4) {
                    Text("expected_cash_drawer".t)
                        .font(.caption2).fontWeight(.black)
                        .foregroundColor(.textSecondary)
                        .tracking(1.0)
                    
                    Text("฿\(expectedCash.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(.appTeal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.appSurface)
                .cornerRadius(APRadius.lg)
                .overlay(RoundedRectangle(cornerRadius: APRadius.lg).stroke(Color.appBorderSubtle, lineWidth: 1))
                .padding(.horizontal)
                
                // Cash Movements list
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("cash_movements_log".t)
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        Spacer()
                        
                        Button(action: {
                            movementAmountString = ""
                            movementReason = ""
                            movementType = "paid_in"
                            showMovementModal = true
                            APHaptic.trigger()
                        }) {
                            Label("add_paid_in_out".t, systemImage: "plus.circle.fill")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    let sessionMovements = allCashMovements.filter { !$0.isDeleted && $0.registerSession?.id == session.id }
                    
                    if sessionMovements.isEmpty {
                        Text("no_manual_movements".t)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sessionMovements) { mov in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mov.reason)
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.textPrimary)
                                        Text(mov.movementType == "paid_in" || mov.movementType == "cash_in" ? "paid_in".t : "paid_out".t)
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    
                                    let isPositive = mov.movementType == "paid_in" || mov.movementType == "cash_in"
                                    Text("\(isPositive ? "+" : "-")฿\(mov.amount.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                                        .foregroundColor(isPositive ? .appTeal : .appRose)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.appSurfaceHigh.opacity(0.4))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .apCard()
                .padding(.horizontal)
            }
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 30)
        }
    }
    
    private func reconcileCard(title: String, amount: Double, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textSecondary)
                .tracking(0.5)
            
            Text("฿\(amount.formatted(.number.precision(.fractionLength(2))))")
                .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .apCard()
    }
    
    // MARK: - Add Movement Modal
    private var addMovementModal: some View {
        NavigationStack {
            Form {
                Section("transaction_details_section".t) {
                    Picker("movement_type_label".t, selection: $movementType) {
                        Text("paid_in_add_cash".t).tag("paid_in")
                        Text("paid_out_withdraw_cash".t).tag("paid_out")
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("amount_baht".t).foregroundColor(.textSecondary)
                        Spacer()
                        TextField("0.00", text: $movementAmountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    TextField("reason_description_placeholder".t, text: $movementReason)
                }
            }
            .navigationTitle("add_cash_movement_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { showMovementModal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        saveCashMovement()
                        showMovementModal = false
                    }
                    .disabled(movementAmountString.isEmpty || movementReason.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Close Shift Modal
    private var closeShiftModal: some View {
        NavigationStack {
            Form {
                Section("expected_calculated_balance".t) {
                    HStack {
                        Text("expected_cash_label".t)
                        Spacer()
                        Text("฿\(expectedCash.formatted(.number.precision(.fractionLength(2))))")
                            .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    }
                }
                
                Section("physical_cash_count".t) {
                    HStack {
                        Text("actual_cash_counted_label".t)
                        Spacer()
                        TextField("0.00", text: $actualCashString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    }
                    
                    // Live Discrepancy indicator
                    let actual = Double(actualCashString) ?? 0.0
                    let discrepancy = actual - expectedCash
                    HStack {
                        Text("discrepancy_label".t)
                        Spacer()
                        if discrepancy == 0.0 {
                            Text("balanced_option".t)
                                .foregroundColor(.appTeal).fontWeight(.bold)
                        } else {
                            Text("\(discrepancy > 0 ? "+" : "")฿\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\(discrepancy > 0 ? "overage_label".t : "shortage_label".t))")
                                .foregroundColor(discrepancy > 0 ? .appTeal : .appRose).fontWeight(.bold)
                        }
                    }
                    
                    TextField("closing_notes_label".t, text: $closingNotes)
                }
            }
            .navigationTitle("shift_reconciliation_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { showCloseModal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("close_register_btn".t) {
                        closeRegisterSession()
                        showCloseModal = false
                    }
                }
            }
        }
    }
    
    // MARK: - Z-Report Receipt View Simulation
    private func zReportView(_ session: RegisterSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("z_report_header".t)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                    
                    VStack(spacing: 8) {
                        Text("z_report_title".t)
                            .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                        
                        Text("----------------------------------------")
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("shift_id_label".t)
                                Spacer()
                                Text(session.id.uuidString.prefix(8).uppercased())
                            }
                            HStack {
                                Text("opened_at_label".t)
                                Spacer()
                                Text(formatDate(session.openedAt))
                            }
                            HStack {
                                Text("closed_at_label".t)
                                Spacer()
                                Text(formatDate(session.closedAt ?? Date()))
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))
                        
                        Text("----------------------------------------")
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text("opening_float_label".t)
                                Spacer()
                                Text(String(format: "฿%.2f", session.openingCash))
                            }
                            HStack {
                                Text("cash_sales_label_colon".t)
                                Spacer()
                                Text(String(format: "฿%.2f", cashSalesAmount))
                            }
                            HStack {
                                Text("cash_in_label_colon".t)
                                Spacer()
                                Text(String(format: "฿%.2f", cashInAmount))
                            }
                            HStack {
                                Text("cash_out_label_colon".t)
                                Spacer()
                                Text(String(format: "฿%.2f", cashOutAmount))
                            }
                            HStack {
                                Text("expected_cash_label".t)
                                Spacer()
                                Text(String(format: "฿%.2f", expectedCash))
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        
                        Text("----------------------------------------")
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text("actual_cash_counted_label_colon".t)
                                Spacer()
                                Text(String(format: "฿%.2f", session.actualClosingCash))
                                    .fontWeight(.bold)
                            }
                            HStack {
                                Text("discrepancy_label_colon".t)
                                Spacer()
                                Text(String(format: "%@฿%.2f", session.cashDiscrepancy >= 0 ? "+" : "", session.cashDiscrepancy))
                                    .fontWeight(.bold)
                                    .foregroundColor(session.cashDiscrepancy >= 0 ? .green : .red)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        
                        if let notes = session.notes, !notes.isEmpty {
                            Text("----------------------------------------")
                                .foregroundColor(.gray)
                            Text("\("notes_field".t): \(notes)")
                                .font(.system(size: 9, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .frame(width: 320)
                    
                    Button("print_z_report_btn".t) {
                        APHaptic.trigger()
                    }
                    .apGradientButton()
                    .padding(.horizontal, 40)
                }
                .padding()
            }
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done".t) {
                        zReportSession = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Actions Logic
    
    private func openRegisterSession() {
        let amount = Double(openingCashString) ?? 0.0
        // Use the first active user; fall back to a random UUID if not available to prevent silent failure on iPad
        let userId = users.first?.id ?? UUID()

        // Auto-close any other active sessions to prevent duplicate open shifts
        let descriptor = FetchDescriptor<RegisterSession>(
            predicate: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted }
        )
        if let activeSessions = try? modelContext.fetch(descriptor) {
            for session in activeSessions {
                session.closedAt = Date()
                session.expectedClosingCash = session.openingCash
                session.actualClosingCash = session.openingCash
                session.cashDiscrepancy = 0.0
                session.closedByUserId = userId
                session.isSynced = false
                session.updatedAt = Date()
                
                let sessionToUpload = session
                Task {
                    _ = try? await NetworkManager.shared.uploadRegisterSession(sessionToUpload)
                }
            }
        }

        let newSession = RegisterSession(
            openedByUserId: userId,
            openedAt: Date(),
            openingCash: amount,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        newSession.notes = openingNotes.isEmpty ? nil : openingNotes
        
        modelContext.insert(newSession)
        try? modelContext.save()
        APHaptic.trigger()
        
        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(newSession)
        }
    }
    
    private func saveCashMovement() {
        guard let session = activeSession else { return }
        let amount = Double(movementAmountString) ?? 0.0
        
        let newMovement = CashMovement(
            registerSession: session,
            movementType: movementType,
            amount: amount,
            reason: movementReason,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        
        modelContext.insert(newMovement)
        try? modelContext.save()
        APHaptic.trigger()
        
        Task {
            _ = try? await NetworkManager.shared.uploadCashMovement(newMovement)
        }
    }
    
    private func closeRegisterSession() {
        guard let session = activeSession else { return }
        let actual = Double(actualCashString) ?? 0.0
        let discrepancy = actual - expectedCash
        
        session.closedAt = Date()
        session.expectedClosingCash = expectedCash
        session.actualClosingCash = actual
        session.cashDiscrepancy = discrepancy
        // Only set closedByUserId if a user exists to avoid FK violation
        session.closedByUserId = users.first?.id
        session.notes = closingNotes.isEmpty ? nil : closingNotes
        session.isSynced = false
        session.updatedAt = Date()
        
        // Create ShiftReport
        let report = ShiftReport(
            registerSession: session,
            reportType: "Z",
            grossSales: cashSalesAmount + cardSalesAmount + qrSalesAmount,
            netSales: cashSalesAmount + cardSalesAmount + qrSalesAmount - refundsAmount,
            totalTax: 0,
            totalDiscounts: 0,
            totalRefunds: refundsAmount,
            cashExpected: expectedCash,
            cashActual: actual,
            overShort: discrepancy,
            generatedByEmployee: employees.first(where: { $0.user?.id == session.closedByUserId })
        )
        modelContext.insert(report)
        
        try? modelContext.save()
        
        // Open Z-Report modal
        zReportSession = session
        APHaptic.trigger()
        
        // ── Auto-print Z-Report ────────────────────────────────────────
        // พิมพ์อัตโนมัติเฉพาะเมื่อ "print_close_shift" = true ใน Settings
        let capturedSession  = session
        let capturedReport   = report
        let capturedCashSales = cashSalesAmount
        let capturedCardSales = cardSalesAmount
        let capturedQRSales   = qrSalesAmount
        let capturedRefunds   = refundsAmount
        let capturedCashIn   = cashInAmount
        let capturedCashOut  = cashOutAmount
        Task {
            await PrintService.shared.printZReport(
                session:         capturedSession,
                report:          capturedReport,
                cashSales:       capturedCashSales,
                cardSales:       capturedCardSales,
                qrSales:         capturedQRSales,
                totalRefunds:    capturedRefunds,
                cashMovementsIn:  capturedCashIn,
                cashMovementsOut: capturedCashOut
            )
        }

        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(session)
            do {
                let success = try await NetworkManager.shared.uploadShiftReport(report)
                if success {
                    report.isSynced = true
                    try? modelContext.save()
                }
            } catch {
                #if DEBUG
                print("Failed to sync ShiftReport: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDateRange(opened: Date, closed: Date?) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let openedStr = df.string(from: opened)
        if let closed = closed {
            df.dateStyle = .none
            df.timeStyle = .short
            let closedStr = df.string(from: closed)
            return "\(openedStr) - \(closedStr)"
        }
        return openedStr
    }
    
    private func localT(_ key: String) -> String {
        let isThai = lm.currentLanguage == .thai
        switch key {
        case "current_shift_tab":
            return isThai ? "กะปัจจุบัน" : "Current Shift"
        case "shift_history_tab":
            return isThai ? "ประวัติกะย้อนหลัง" : "Shift History"
        case "no_shift_history":
            return isThai ? "ไม่มีประวัติกะทำงานก่อนหน้านี้" : "No past shifts recorded."
        case "opened_by":
            return isThai ? "เปิดโดย" : "Opened By"
        case "closed_by":
            return isThai ? "ปิดโดย" : "Closed By"
        case "discrepancy":
            return isThai ? "ผลต่าง" : "Discrepancy"
        case "status":
            return isThai ? "สถานะ" : "Status"
        case "synced":
            return isThai ? "ซิงค์แล้ว" : "Synced"
        case "unsynced":
            return isThai ? "ยังไม่ซิงค์" : "Unsynced"
        case "shift_running":
            return isThai ? "กำลังทำงานอยู่" : "Active"
        case "shift_closed":
            return isThai ? "ปิดกะแล้ว" : "Closed"
        default:
            return key
        }
    }
    
    private var shiftHistoryView: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                let pastSessions = allSessions.filter { $0.closedAt != nil }
                
                if pastSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                            .padding(.top, 40)
                        Text(localT("no_shift_history"))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(pastSessions.enumerated()), id: \.element.id) { index, session in
                        VStack(alignment: .leading, spacing: 12) {
                            // Header: Time and ID
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDateRange(opened: session.openedAt, closed: session.closedAt))
                                        .font(.headline).fontWeight(.bold)
                                        .foregroundColor(.textPrimary)
                                    Text("Shift ID: \(session.id.uuidString.prefix(8).uppercased())")
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                
                                // Sync Icon
                                HStack(spacing: 4) {
                                    Image(systemName: session.isSynced ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                                        .font(.caption)
                                        .foregroundColor(session.isSynced ? .appTeal : .appRose)
                                    Text(session.isSynced ? localT("synced") : localT("unsynced"))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(session.isSynced ? .appTeal : .appRose)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(6)
                            }
                            
                            Divider().background(Color.appDivider)
                            
                            // Cash Details Row
                            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    VStack(alignment: .leading) {
                                        Text(L.Nav.tabCashDrawer.t.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                        Text("฿\(session.openingCash.formatted(.number.precision(.fractionLength(2))))")
                                            .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("expected_cash_label".t.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                        Text("฿\(session.expectedClosingCash.formatted(.number.precision(.fractionLength(2))))")
                                            .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("actual_cash_counted_label".t.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                        Text("฿\(session.actualClosingCash.formatted(.number.precision(.fractionLength(2))))")
                                            .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                                    }
                                }
                            }
                            
                            Divider().background(Color.appDivider)
                            
                            // Discrepancy & Staff
                            HStack {
                                let discrepancy = session.cashDiscrepancy
                                HStack(spacing: 4) {
                                    Text("\(localT("discrepancy")): ")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                    if discrepancy == 0.0 {
                                        Text("balanced_option".t)
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundColor(.appTeal)
                                    } else {
                                        Text("\(discrepancy > 0 ? "+" : "")฿\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\(discrepancy > 0 ? "overage_label".t : "shortage_label".t))")
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundColor(discrepancy > 0 ? .appTeal : .appRose)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    zReportSession = session
                                    APHaptic.trigger()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text.viewfinder")
                                        Text("z_report_header".t)
                                    }
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let notes = session.notes, !notes.isEmpty {
                                Text("\("notes_field".t): \(notes)")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                    .padding(.top, 4)
                            }
                        }
                        .apCard()
                        .padding(.horizontal)
                        .offset(y: animateHistory ? 0 : 40)
                        .opacity(animateHistory ? 1.0 : 0.0)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.8)
                            .delay(Double(index) * 0.06),
                            value: animateHistory
                        )
                    }
                }
            }
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical)
            .onAppear {
                withAnimation {
                    animateHistory = true
                }
            }
            .onDisappear {
                animateHistory = false
            }
        }
    }
}
