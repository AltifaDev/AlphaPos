import SwiftUI
import SwiftData

struct CashDrawerManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage("logged_in_email") private var loggedInEmail = ""
    @AppStorage("require_manager_override_for_no_sale") private var requireManagerOverrideForNoSale = true
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    // Fetch all non-deleted sessions (active and past)
    @Query(filter: #Predicate<RegisterSession> { !$0.isDeleted }, sort: \RegisterSession.openedAt, order: .reverse)
    private var allSessions: [RegisterSession]

    // Fetch payments and cash movements for calculations
    @Query(sort: \Payment.paidAt, order: .reverse) private var allPayments: [Payment]
    @Query(sort: \CashMovement.updatedAt, order: .reverse) private var allCashMovements: [CashMovement]
    @Query(sort: \User.username) private var users: [User]
    @Query private var employees: [Employee]
    @Query(filter: #Predicate<Branch> { !$0.isDeleted }, sort: \Branch.name) private var branches: [Branch]
    @Query private var allRefunds: [RefundTransaction]
    @Query(filter: #Predicate<ShiftReport> { !$0.isDeleted }, sort: \ShiftReport.createdAt, order: .reverse)
    private var allShiftReports: [ShiftReport]

    @State private var openingCashString = "1000"
    @State private var openingNotes = ""
    @State private var selectedBranchId: UUID? = nil
    @State private var selectedSubTab = 0 // 0: Current Shift, 1: Shift History
    @State private var animateHistory = false

    // Add movement modal states
    @State private var showMovementModal = false
    @State private var movementAmountString = ""
    @State private var movementReason = ""
    @State private var movementType = "paid_in" // "paid_in", "paid_out"
    @State private var isChangeFloatTopUp = false

    // Close shift states (blind count → review)
    @State private var showCloseModal = false
    @State private var closeRevealExpected = false
    @State private var actualCashString = ""
    @State private var closingNotes = ""
    @State private var varianceReasonCode = ""
    @State private var zReportSession: RegisterSession? = nil
    @State private var zReportSnapshot: ShiftCloseSnapshot? = nil
    @State private var operationError: String?
    @State private var localBackupError: String?
    // H-1: No-Sale (manual drawer open)
    @State private var showNoSaleConfirm = false
    @State private var showNoSalePINSheet = false
    @State private var pendingNoSaleReasonCode = ""
    @State private var authorizingManagerUser: User?
    @State private var noSaleError: String?
    @State private var pendingDeleteSession: RegisterSession?
    @State private var showDeleteShiftConfirm = false
    @State private var showDeleteShiftPINSheet = false

    private let varianceReasonOptions: [(code: String, key: String)] = [
        ("counting_error", "cd_var_counting_error"),
        ("unrecorded_payout", "cd_var_unrecorded_payout"),
        ("change_error", "cd_var_change_error"),
        ("other", "cd_var_other")
    ]

    private let noSaleReasonOptions: [(code: String, key: String)] = [
        ("make_change", "no_sale_reason_make_change"),
        ("count_cash", "no_sale_reason_count_cash"),
        ("correction", "no_sale_reason_correction"),
        ("other", "no_sale_reason_other")
    ]

    private var canOpenCashDrawer: Bool {
        sessionManager.can(.cashDrawerOpen) || sessionManager.can(.cashDrawerManage)
    }

    private var activeBranchUUID: UUID? { UUID(uuidString: activeBranchId) }
    /// `active_branch_id` can be empty on devices upgraded from older builds. In that
    /// case the branch selected on this screen is the source of truth.
    private var effectiveBranchUUID: UUID? { activeBranchUUID ?? selectedBranchId }
    private var branchSessions: [RegisterSession] {
        guard let branchId = effectiveBranchUUID else {
            return []
        }
        return allSessions.filter { $0.branch.id == branchId }
    }
    private var branchPayments: [Payment] {
        guard let branchId = effectiveBranchUUID else { return allPayments }
        return allPayments.filter { $0.order?.branch.id == branchId }
    }
    private var branchCashMovements: [CashMovement] {
        guard let branchId = effectiveBranchUUID else { return allCashMovements }
        return allCashMovements.filter { $0.registerSession?.branch.id == branchId }
    }
    private var branchRefunds: [RefundTransaction] {
        guard let branchId = effectiveBranchUUID else { return allRefunds }
        return allRefunds.filter { $0.order?.branch.id == branchId }
    }

    // Active session helper
    private var activeSession: RegisterSession? {
        if let scopedSession = branchSessions.first(where: { $0.closedAt == nil }) {
            return scopedSession
        }

        return nil
    }

    // Financial calculations for active session
    private var cashSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                payment.paymentMethod.lowercased() == "cash" &&
                (payment.registerSessionId == session.id || (payment.registerSessionId == nil && payment.paidAt >= session.openedAt))
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var cashInAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_in" || movement.movementType == "paid_in")
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var cashOutAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchCashMovements
            .filter { movement in
                !movement.isDeleted &&
                movement.registerSession?.id == session.id &&
                (movement.movementType == "cash_out" || movement.movementType == "paid_out")
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var cardSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                ["card", "credit_card", "debit_card"].contains(payment.paymentMethod.lowercased()) &&
                (payment.registerSessionId == session.id || (payment.registerSessionId == nil && payment.paidAt >= session.openedAt))
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var qrSalesAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchPayments
            .filter { payment in
                !payment.isDeleted &&
                payment.status == "completed" &&
                ["qr", "promptpay", "transfer", "bank_transfer"].contains(payment.paymentMethod.lowercased()) &&
                (payment.registerSessionId == session.id || (payment.registerSessionId == nil && payment.paidAt >= session.openedAt))
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var refundsAmount: Double {
        guard let session = activeSession else { return 0.0 }
        return branchRefunds
            .filter { refund in
                !refund.isDeleted &&
                refund.status == "completed" &&
                (refund.registerSessionId == session.id || (refund.registerSessionId == nil && refund.financialEventAt >= session.openedAt))
            }
            .reduce(0.0) { $0 + $1.refundAmount }
    }

    private var cashRefundsAmount: Double {
        guard let session = activeSession else { return 0 }
        return branchRefunds.filter {
            !$0.isDeleted && $0.status == "completed" && ($0.registerSessionId == session.id || ($0.registerSessionId == nil && $0.financialEventAt >= session.openedAt)) &&
            ($0.refundMethod == "cash" || $0.originalPayment?.paymentMethod == "cash")
        }.reduce(0) { $0 + $1.refundAmount }
    }

    private var expectedCash: Double {
        guard let session = activeSession else { return 0.0 }
        return session.openingCash + cashSalesAmount + cashInAmount - cashOutAmount - cashRefundsAmount
    }

    var body: some View {
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
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
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
                .frame(maxWidth: 320)
            }
        }
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
        // H-1: No-Sale — choose reason, then optionally require manager PIN
        .confirmationDialog("no_sale_confirm_title".t, isPresented: $showNoSaleConfirm, titleVisibility: .visible) {
            ForEach(noSaleReasonOptions, id: \.code) { option in
                Button(option.key.t) {
                    pendingNoSaleReasonCode = option.code
                    requestNoSaleAfterReason()
                }
            }
            Button("cancel_btn".t, role: .cancel) {}
        } message: {
            Text("no_sale_confirm_msg".t)
        }
        .sheet(isPresented: $showNoSalePINSheet) {
            ManagerPINVerificationSheet(
                isPresented: $showNoSalePINSheet,
                onSuccess: {},
                onAuthorizedManager: { manager in
                    authorizingManagerUser = manager
                    // Call with the manager directly — AppStorage/state may not flush before onSuccess.
                    performNoSale(
                        reasonCode: pendingNoSaleReasonCode,
                        authorizingManager: manager
                    )
                }
            )
        }
        .confirmationDialog("ลบปิดกะที่ไม่มียอดขาย?", isPresented: $showDeleteShiftConfirm, titleVisibility: .visible) {
            Button("ยืนยันลบ", role: .destructive) { requestDeleteShiftAuthorization() }
            Button("ยกเลิก", role: .cancel) { pendingDeleteSession = nil }
        } message: {
            Text("ลบได้เฉพาะกะที่ตรวจพบว่ายอดขายเป็นศูนย์เท่านั้น")
        }
        .sheet(isPresented: $showDeleteShiftPINSheet) {
            ManagerPINVerificationSheet(isPresented: $showDeleteShiftPINSheet, onSuccess: {}, onAuthorizedManager: { _ in
                deleteVerifiedZeroSalesShift()
            })
        }
        .alert("Unable to Open Shift", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
        .alert("no_sale_denied_title".t, isPresented: Binding(
            get: { noSaleError != nil },
            set: { if !$0 { noSaleError = nil } }
        )) {
            Button("OK", role: .cancel) { noSaleError = nil }
        } message: {
            Text(noSaleError ?? "")
        }
        .alert("ปิดกะแล้ว แต่ Backup ไม่สำเร็จ", isPresented: Binding(
            get: { localBackupError != nil },
            set: { if !$0 { localBackupError = nil } }
        )) {
            Button("ตกลง", role: .cancel) { localBackupError = nil }
        } message: {
            Text(localBackupError ?? "")
        }
    }

    // MARK: - Closed State View
    private var closedSessionView: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.appRose.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(APGradient.destructive)
                    }
                    .padding(.top, 20)

                    Text("cd_open_ceremony_title".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("cd_open_ceremony_sub".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("start_shift_header".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appAccent)

                    // Operator (read-only, resolved)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("cd_operator_label".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        Text(resolveCashDrawerOperatorUser().username)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(10)
                    }

                    // Branch picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("cd_branch_label".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        if branches.isEmpty {
                            Text("cd_no_branch_available".t)
                                .font(.system(size: 12))
                                .foregroundColor(.appAmber)
                        } else {
                            Picker("cd_branch_label".t, selection: $selectedBranchId) {
                                Text("cd_branch_none".t).tag(UUID?.none)
                                ForEach(branches) { branch in
                                    Text(branch.name).tag(Optional(branch.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.system(size: 12))
                        }
                    }

                    // Opening float (required)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("starting_cash_float_label".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        HStack {
                            Text("฿")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("0.00", text: $openingCashString)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("opening_notes_label".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        TextField("opening_notes_placeholder".t, text: $openingNotes)
                            .font(.system(size: 12))
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
                            .textFieldStyle(.plain)
                    }

                    Button(action: openRegisterSession) {
                        Label("open_session_btn".t, systemImage: "lock.open.fill")
                            .font(.system(size: 12, weight: .bold))
                            .apGradientButton(gradient: APGradient.positive, shadow: APShadow.positiveGlow)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenShift)
                    .opacity(canOpenShift ? 1 : 0.5)
                }
                .apCard()
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
            .padding(.bottom, 30)
            .onAppear {
                if selectedBranchId == nil {
                    selectedBranchId = branches.first(where: { $0.id == activeBranchUUID })?.id
                }
            }
        }
    }

    private var canOpenShift: Bool {
        let amount = Double(openingCashString)
        guard let amount, amount >= 0 else { return false }
        if branches.isEmpty { return true } // allow open without branch catalog yet
        return selectedBranchId != nil
    }

    // MARK: - Open State View
    private func openSessionView(_ session: RegisterSession) -> some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // Status + actions
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.appTeal).frame(width: 8, height: 8)
                            Text("shift_running_title".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        Text(LocalizationManager.shared.t("opened_at_template", formatDate(session.openedAt)))
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()

                    Button(action: presentChangeFloatTopUp) {
                        Label("เติมเงินทอน", systemImage: "banknote.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(canOpenCashDrawer ? .appTeal : .textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background((canOpenCashDrawer ? Color.appTeal : Color.textTertiary).opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenCashDrawer)

                    Button(action: {
                        guard canOpenCashDrawer else {
                            noSaleError = "no_sale_permission_denied".t
                            return
                        }
                        showNoSaleConfirm = true
                        APHaptic.trigger()
                    }) {
                        Label("no_sale_btn".t, systemImage: "dollarsign.arrow.circlepath")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(canOpenCashDrawer ? .appAmber : .textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background((canOpenCashDrawer ? Color.appAmber : Color.textTertiary).opacity(0.15))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenCashDrawer)

                    Button(action: {
                        closingNotes = ""
                        varianceReasonCode = ""
                        closeRevealExpected = false
                        actualCashString = "" // blind — do not prefill expected
                        showCloseModal = true
                        APHaptic.trigger()
                    }) {
                        Label("end_shift_btn".t, systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(APGradient.destructive)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top)

                // Metadata strip (cashier / branch / locked float)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        metaChip(title: "cd_meta_opened_by".t, value: displayName(forUserId: session.openedByUserId))
                        metaChip(title: "cd_branch_label".t, value: session.branch.name)
                    }
                    Text("cd_float_locked_hint".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                .padding(.horizontal)

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

                VStack(spacing: 4) {
                    Text("expected_cash_drawer".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                    Text("฿\(expectedCash.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.appTeal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appSurface)
                .cornerRadius(APRadius.lg)
                .overlay(RoundedRectangle(cornerRadius: APRadius.lg).stroke(Color.appBorderSubtle, lineWidth: 1))
                .padding(.horizontal)

                // Audit-style movements
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("cash_movements_log".t)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                        Spacer()
                        Button(action: {
                            movementAmountString = ""
                            movementReason = ""
                            movementType = "paid_in"
                            isChangeFloatTopUp = false
                            showMovementModal = true
                            APHaptic.trigger()
                        }) {
                            Label("add_paid_in_out".t, systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    let sessionMovements = branchCashMovements
                        .filter { !$0.isDeleted && $0.registerSession?.id == session.id }
                        .sorted { $0.updatedAt > $1.updatedAt }

                    if sessionMovements.isEmpty {
                        Text("no_manual_movements".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 0) {
                            HStack {
                                Text("cd_movement_when".t).frame(width: 72, alignment: .leading)
                                Text("Type").frame(maxWidth: .infinity, alignment: .leading)
                                Text("cd_movement_by".t).frame(width: 80, alignment: .leading)
                                Text("amount_baht".t).frame(width: 72, alignment: .trailing)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)

                            ForEach(sessionMovements) { mov in
                                Divider().opacity(0.4)
                                HStack(alignment: .top, spacing: 6) {
                                    Text(mov.updatedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                        .frame(width: 72, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(movementTypeLabel(mov.movementType))
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        Text(mov.reason)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(displayName(forEmployeeId: mov.performedByEmployeeId) ?? "—")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                        .frame(width: 80, alignment: .leading)
                                        .lineLimit(1)

                                    let isNoSale = mov.movementType == "no_sale"
                                    let isPositive = mov.movementType == "paid_in" || mov.movementType == "cash_in"
                                    Text(isNoSale ? "—" : "\(isPositive ? "+" : "-")฿\(mov.amount.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(isNoSale ? .appAmber : (isPositive ? .appTeal : .appRose))
                                        .frame(width: 72, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .apCard()
                .padding(.horizontal)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 30)
        }
    }

    private func metaChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movementTypeLabel(_ type: String) -> String {
        switch type {
        case "no_sale": return "no_sale_btn".t
        case "paid_in", "cash_in": return "paid_in".t
        case "paid_out", "cash_out": return "paid_out".t
        default: return type
        }
    }

    private func reconcileCard(title: String, amount: Double, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)

            Text("฿\(amount.formatted(.number.precision(.fractionLength(2))))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .apCard()
    }

    // MARK: - Add Movement Modal
    private var addMovementModal: some View {
        return NavigationStack {
            Form {
                Section("transaction_details_section".t) {
                    if isChangeFloatTopUp {
                        LabeledContent("ประเภทรายการ", value: "เติมเงินทอนเข้าลิ้นชัก")
                        Text("ยอดนี้จะถูกรวมเป็นเงินรับเข้าระหว่างกะ และเพิ่มยอดเงินสดที่คาดไว้ตอนปิดกะ")
                            .font(.footnote)
                            .foregroundColor(.textSecondary)
                    } else {
                        Picker("movement_type_label".t, selection: $movementType) {
                            Text("paid_in_add_cash".t).tag("paid_in")
                            Text("paid_out_withdraw_cash".t).tag("paid_out")
                        }
                        .pickerStyle(.segmented)
                    }

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
            .navigationTitle(isChangeFloatTopUp ? "เติมเงินทอนระหว่างกะ" : "add_cash_movement_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { showMovementModal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        if saveCashMovement() {
                            showMovementModal = false
                        }
                    }
                    .disabled(!isValidMovementInput)
                }
            }
        }
    }

    // MARK: - Close Shift Modal (blind count → review)
    private var closeShiftModal: some View {
        NavigationStack {
            Form {
                if !closeRevealExpected {
                    Section {
                        Text("cd_blind_count_hint".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    } header: {
                        Text("cd_blind_count_title".t)
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
                    }
                } else {
                    Section("expected_calculated_balance".t) {
                        HStack {
                            Text("expected_cash_label".t)
                            Spacer()
                            Text("฿\(expectedCash.formatted(.number.precision(.fractionLength(2))))")
                                .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                        }
                        HStack {
                            Text("actual_cash_counted_label".t)
                            Spacer()
                            Text("฿\((Double(actualCashString) ?? 0).formatted(.number.precision(.fractionLength(2))))")
                                .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                        }

                        let actual = Double(actualCashString) ?? 0.0
                        let discrepancy = actual - expectedCash
                        HStack {
                            Text("discrepancy_label".t)
                            Spacer()
                            if abs(discrepancy) < 0.005 {
                                Text("balanced_option".t)
                                    .foregroundColor(.appTeal).fontWeight(.bold)
                            } else {
                                Text("\(discrepancy > 0 ? "+" : "")฿\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\(discrepancy > 0 ? "overage_label".t : "shortage_label".t))")
                                    .foregroundColor(discrepancy > 0 ? .appTeal : .appRose).fontWeight(.bold)
                            }
                        }
                    }

                    if abs((Double(actualCashString) ?? 0) - expectedCash) >= 0.005 {
                        Section("cd_variance_reason".t) {
                            Picker("cd_variance_reason".t, selection: $varianceReasonCode) {
                                Text("cd_variance_reason".t).tag("")
                                ForEach(varianceReasonOptions, id: \.code) { option in
                                    Text(option.key.t).tag(option.code)
                                }
                            }
                            Text("cd_variance_required".t)
                                .font(.system(size: 12))
                                .foregroundColor(.appAmber)
                        }
                    }

                    Section {
                        TextField("closing_notes_label".t, text: $closingNotes)
                    }
                }
            }
            .navigationTitle("shift_reconciliation_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        showCloseModal = false
                        closeRevealExpected = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !closeRevealExpected {
                        Button("cd_continue_review".t) {
                            closeRevealExpected = true
                            APHaptic.trigger()
                        }
                        .disabled(Double(actualCashString) == nil)
                    } else {
                        Button("close_register_btn".t) {
                            closeRegisterSession()
                            showCloseModal = false
                            closeRevealExpected = false
                        }
                        .disabled(!canConfirmClose)
                    }
                }
            }
        }
    }

    private var canConfirmClose: Bool {
        guard Double(actualCashString) != nil else { return false }
        let discrepancy = (Double(actualCashString) ?? 0) - expectedCash
        if abs(discrepancy) < 0.005 { return true }
        return !varianceReasonCode.isEmpty
    }

    // MARK: - Z-Report Receipt View Simulation
    private func zReportView(_ session: RegisterSession) -> some View {
        let snapshot = zReportSnapshot ?? makeShiftCloseSnapshot(for: session, closedAt: session.closedAt ?? Date())
        let isThai = lm.currentLanguage == .thai
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let branchName = session.branch.name
        let closedAt = session.closedAt ?? Date()
        let durationMins = max(0, Int(closedAt.timeIntervalSince(session.openedAt) / 60))
        let durationStr = "\(durationMins / 60) \(isThai ? "ชม." : "h") \(durationMins % 60) \(isThai ? "นาที" : "m")"

        let inStoreTenders = snapshot.tenders.filter { !$0.isDelivery }
        let deliveryTenders = snapshot.tenders.filter { $0.isDelivery }
        let inStoreTotal = inStoreTenders.reduce(0) { $0 + $1.net }
        let deliveryTotal = deliveryTenders.reduce(0) { $0 + $1.net }
        let totalReceived = snapshot.tenders.reduce(0) { $0 + $1.net }

        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("z_report_header".t)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.textSecondary)

                    VStack(spacing: 8) {
                        // Header
                        VStack(spacing: 2) {
                            Text(storeName.uppercased())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                            if !branchName.isEmpty {
                                Text("\(isThai ? "สาขา" : "Branch"): \(branchName)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            Text(isThai ? "รายงาน Z (สรุปปิดกะ)" : "Z-REPORT (SHIFT CLOSE)")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .padding(.top, 1)
                        }

                        ReceiptDivider(dashed: false)

                        // Meta info
                        VStack(spacing: 3) {
                            receiptRow(label: isThai ? "รหัสกะ" : "Shift ID", value: session.id.uuidString.prefix(8).uppercased())
                            if !snapshot.closedBy.isEmpty {
                                receiptRow(label: isThai ? "พนักงานปิดกะ" : "Closed By", value: snapshot.closedBy)
                            }
                            receiptRow(label: isThai ? "เปิดเมื่อ" : "Opened At", value: formatDate(session.openedAt))
                            receiptRow(label: isThai ? "ปิดเมื่อ" : "Closed At", value: formatDate(closedAt))
                            receiptRow(label: isThai ? "ระยะเวลากะ" : "Duration", value: durationStr)
                        }
                        .font(.system(size: 10, design: .monospaced))

                        ReceiptDivider(dashed: true)

                        // 1. Sales Summary
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isThai ? "1. สรุปยอดขาย (SALES SUMMARY)" : "1. SALES SUMMARY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            receiptRow(label: isThai ? "ยอดขายรวม" : "Gross Sales", value: String(format: "฿%.2f", snapshot.grossSales))
                            if snapshot.totalDiscounts > 0.005 {
                                receiptRow(label: isThai ? "ส่วนลดรวม" : "Total Discounts", value: String(format: "-฿%.2f", snapshot.totalDiscounts))
                            }
                            if snapshot.totalRefunds > 0.005 {
                                receiptRow(label: isThai ? "คืนเงิน/ยกเลิก" : "Refunds/Voids", value: String(format: "-฿%.2f", snapshot.totalRefunds))
                            }
                            if snapshot.totalTax > 0.005 {
                                receiptRow(label: isThai ? "ภาษี (รวมแล้ว)" : "Tax (included)", value: String(format: "฿%.2f", snapshot.totalTax))
                            }
                            if snapshot.serviceCharge > 0.005 {
                                receiptRow(label: isThai ? "ค่าบริการ" : "Service Charge", value: String(format: "฿%.2f", snapshot.serviceCharge))
                            }
                            ReceiptDivider(dashed: true)
                            HStack {
                                Text(isThai ? "ยอดขายสุทธิ" : "NET SALES")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(String(format: "฿%.2f", snapshot.netSales))
                                    .fontWeight(.bold)
                            }
                            receiptRow(label: isThai ? "จำนวนใบเสร็จ" : "Total Receipts", value: "\(snapshot.receiptCount) \(isThai ? "บิล" : "bills")")
                            if snapshot.failedPaymentCount > 0 {
                                receiptRow(label: isThai ? "ชำระไม่สำเร็จ" : "Failed Payments", value: "\(snapshot.failedPaymentCount)")
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))

                        ReceiptDivider(dashed: true)

                        // 2. Payment Breakdown
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isThai ? "2. สรุปยอดรับชำระ (PAYMENTS)" : "2. PAYMENT BREAKDOWN")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))

                            // In-Store Section
                            if !inStoreTenders.isEmpty {
                                Text(isThai ? "[ หน้าร้าน / ได้รับเงินทันที ]" : "[ In-Store / Immediate ]")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 1)

                                ForEach(inStoreTenders) { tender in
                                    receiptRow(label: "• \(tender.method) (\(tender.count))", value: String(format: "฿%.2f", tender.net))
                                }
                                HStack {
                                    Text(isThai ? "  รวมยอดหน้าร้าน" : "  Subtotal In-Store")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(String(format: "฿%.2f", inStoreTotal))
                                        .fontWeight(.semibold)
                                }
                                .padding(.top, 1)
                            }

                            // Delivery Section
                            if !deliveryTenders.isEmpty {
                                Text(isThai ? "[ เดลิเวอรี่ / รอระบบโอน ]" : "[ Delivery / Pending Settlement ]")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)

                                ForEach(deliveryTenders) { tender in
                                    receiptRow(label: "• \(tender.method) (\(tender.count))", value: String(format: "฿%.2f", tender.net))
                                }
                                HStack {
                                    Text(isThai ? "  รวมเดลิเวอรี่ (รอโอน)" : "  Subtotal Delivery")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(String(format: "฿%.2f", deliveryTotal))
                                        .fontWeight(.semibold)
                                }
                                .padding(.top, 1)
                            }

                            ReceiptDivider(dashed: true)

                            HStack {
                                Text(isThai ? "รวมรับชำระทั้งหมด" : "TOTAL RECEIVED")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(String(format: "฿%.2f", totalReceived))
                                    .fontWeight(.bold)
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))

                        ReceiptDivider(dashed: true)

                        // 3. Cash Drawer Reconciliation
                        let cashTender = snapshot.tenders.first { $0.method == shiftTenderName("cash") }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isThai ? "3. กระทบยอดเงินสด (CASH DRAWER)" : "3. CASH DRAWER")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))

                            receiptRow(label: "(+) " + (isThai ? "เงินเปิดกะ" : "Opening Float"), value: String(format: "฿%.2f", session.openingCash))
                            receiptRow(label: "(+) " + (isThai ? "ยอดขายเงินสด" : "Cash Sales"), value: String(format: "฿%.2f", cashTender?.received ?? 0))
                            if snapshot.cashIn > 0.005 {
                                receiptRow(label: "(+) " + (isThai ? "เงินเข้า" : "Cash In"), value: String(format: "฿%.2f", snapshot.cashIn))
                            }
                            if snapshot.cashOut > 0.005 {
                                receiptRow(label: "(-) " + (isThai ? "เงินออก" : "Cash Out"), value: String(format: "-฿%.2f", snapshot.cashOut))
                            }
                            if (cashTender?.refunded ?? 0) > 0.005 {
                                receiptRow(label: "(-) " + (isThai ? "คืนเงินสด" : "Cash Refunds"), value: String(format: "-฿%.2f", cashTender?.refunded ?? 0))
                            }

                            ReceiptDivider(dashed: true)

                            HStack {
                                Text("(=) " + (isThai ? "เงินสดที่ควรมี" : "Expected Cash"))
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(String(format: "฿%.2f", snapshot.expectedCash))
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text("(=) " + (isThai ? "เงินสดที่นับจริง" : "Actual Cash"))
                                    .fontWeight(.bold)
                                Spacer()
                                Text(String(format: "฿%.2f", session.actualClosingCash))
                                    .fontWeight(.bold)
                            }

                            ReceiptDivider(dashed: true)

                            let diff = session.cashDiscrepancy
                            HStack {
                                Text(isThai ? "ผลต่างเงินสด" : "Discrepancy")
                                    .fontWeight(.bold)
                                Spacer()
                                if abs(diff) < 0.005 {
                                    Text("฿0.00 " + (isThai ? "(ตรง)" : "(Balanced)"))
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                } else {
                                    Text(String(format: "%@฿%.2f %@", diff > 0 ? "+" : "", diff, diff > 0 ? (isThai ? "(เกิน)" : "(Over)") : (isThai ? "(ขาด)" : "(Short)")))
                                        .fontWeight(.bold)
                                        .foregroundColor(diff > 0 ? .green : .red)
                                }
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))

                        if let notes = session.notes, !notes.isEmpty {
                            ReceiptDivider(dashed: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isThai ? "หมายเหตุ:" : "Notes:")
                                    .fontWeight(.bold)
                                Text(notes)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ReceiptDivider(dashed: false)

                        // Signatures
                        VStack(spacing: 6) {
                            HStack {
                                Text(isThai ? "ลายเซ็นแคชเชียร์: ____________________" : "Cashier Sign: ____________________")
                            }
                            HStack {
                                Text(isThai ? "ลายเซ็นผู้จัดการ: ____________________" : "Manager Sign: ____________________")
                            }
                            Text(isThai ? "* สิ้นสุดกะ / รายงาน Z *" : "* END OF SHIFT / Z-REPORT *")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(.top, 2)
                        }
                        .font(.system(size: 9, design: .monospaced))
                    }
                    .padding(18)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .frame(width: 330)

                    Button("print_z_report_btn".t) {
                        APHaptic.trigger()
                        let report = allShiftReports.first { $0.registerSession?.id == session.id } ?? ShiftReport(
                            registerSession: session,
                            reportType: "Z",
                            grossSales: snapshot.grossSales,
                            netSales: snapshot.netSales,
                            totalTax: snapshot.totalTax,
                            totalDiscounts: snapshot.totalDiscounts,
                            totalRefunds: snapshot.totalRefunds,
                            cashExpected: snapshot.expectedCash,
                            cashActual: session.actualClosingCash,
                            overShort: session.cashDiscrepancy
                        )
                        Task {
                            await PrintService.shared.printZReport(
                                session: session,
                                report: report,
                                tenders: snapshot.tenders,
                                receiptCount: snapshot.receiptCount,
                                failedPaymentCount: snapshot.failedPaymentCount,
                                cashMovementsIn: snapshot.cashIn,
                                cashMovementsOut: snapshot.cashOut,
                                openedBy: snapshot.openedBy,
                                closedBy: snapshot.closedBy,
                                isThai: lm.currentLanguage == .thai,
                                respectAutoPrintSetting: false
                            )
                        }
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

    private func receiptRow(label: String, value: String, isBold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .fontWeight(isBold ? .bold : .regular)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(isBold ? .bold : .regular)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions Logic

    private func openRegisterSession() {
        guard activeSession == nil else {
            operationError = "An active shift already exists. Close and reconcile it before opening another shift."
            return
        }
        guard let amount = Double(openingCashString), amount >= 0 else {
            operationError = "cd_float_required".t
            return
        }
        if !branches.isEmpty && selectedBranchId == nil {
            operationError = "cd_branch_required".t
            return
        }

        let operatorUser = resolveCashDrawerOperatorUser()
        guard let branch = branches.first(where: { $0.id == selectedBranchId }) else {
            operationError = BranchContextError.selectionRequired.localizedDescription
            return
        }

        let newSession = RegisterSession(
            openedByUserId: operatorUser.id,
            openedAt: Date(),
            openingCash: amount,
            notes: openingNotes.isEmpty ? nil : openingNotes,
            branch: branch,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )

        modelContext.insert(newSession)
        modelContext.saveWithLogging(label: #function)

        openingNotes = ""
        APHaptic.trigger()

        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(newSession)
        }
    }

    private func resolveCashDrawerOperatorUser() -> User {
        if let sessionEmployeeId = sessionManager.currentStaffSession?.employeeId,
           let user = employees.first(where: { $0.id == sessionEmployeeId })?.user {
            return user
        }
        if let user = users.first(where: { $0.email?.localizedCaseInsensitiveCompare(loggedInEmail) == .orderedSame }) {
            return user
        }
        if let user = users.first(where: { !$0.isDeleted && $0.isActive }) {
            return user
        }

        let roleName = sessionManager.currentStaffSession?.roleName ?? "Store Manager"
        let role = findOrCreateRole(named: roleName)
        let displayName = sessionManager.currentStaffSession?.displayName
            ?? UserDefaults.standard.string(forKey: "logged_in_name")
            ?? "Store Owner"
        let username = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        let user = User(
            username: username.isEmpty ? "store_owner" : username,
            email: loggedInEmail.isEmpty ? nil : loggedInEmail,
            passwordHash: SecurityHelper.sha256(UUID().uuidString),
            role: role,
            isActive: true,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        modelContext.insert(user)
        modelContext.saveWithLogging(label: #function)
        return user
    }

    private func findOrCreateRole(named name: String) -> Role {
        let descriptor = FetchDescriptor<Role>(
            predicate: #Predicate<Role> { $0.name == name }
        )
        if let role = (try? modelContext.fetch(descriptor))?.first {
            return role
        }
        let role = Role(
            name: name,
            roleDescription: "\(name) Privileges",
            permissionKeys: "",
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        modelContext.insert(role)
        return role
    }

    private var isValidMovementInput: Bool {
        guard let amount = Double(movementAmountString), amount > 0 else { return false }
        return !movementReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func presentChangeFloatTopUp() {
        guard activeSession != nil else {
            operationError = "ไม่พบกะที่กำลังเปิดอยู่"
            return
        }
        guard canOpenCashDrawer else {
            operationError = "คุณไม่มีสิทธิ์จัดการเงินในลิ้นชัก"
            return
        }
        movementAmountString = ""
        movementReason = "เติมเงินทอนระหว่างกะ"
        movementType = "paid_in"
        isChangeFloatTopUp = true
        showMovementModal = true
        APHaptic.trigger()
    }

    @discardableResult
    private func saveCashMovement() -> Bool {
        guard let session = activeSession else {
            operationError = "ไม่พบกะที่กำลังเปิดอยู่"
            return false
        }
        guard let amount = Double(movementAmountString), amount > 0 else {
            operationError = "กรุณาระบุจำนวนเงินมากกว่า 0 บาท"
            return false
        }
        let reason = movementReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            operationError = "กรุณาระบุเหตุผลของรายการ"
            return false
        }
        let operatorUser = resolveCashDrawerOperatorUser()
        let employeeId = employees.first(where: { $0.user?.id == operatorUser.id })?.id

        let newMovement = CashMovement(
            registerSession: session,
            movementType: movementType,
            amount: amount,
            reason: reason,
            performedByEmployeeId: employeeId,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )

        modelContext.insert(newMovement)
        AccountingLedgerService.recordCashMovement(newMovement, in: modelContext)
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        Task {
            _ = try? await NetworkManager.shared.uploadCashMovement(newMovement)
        }
        return true
    }

    /// After reason selection: require manager PIN when policy demands it.
    private func requestNoSaleAfterReason() {
        guard canOpenCashDrawer else {
            noSaleError = "no_sale_permission_denied".t
            return
        }
        authorizingManagerUser = nil
        if requireManagerOverrideForNoSale && !sessionManager.can(.managerOverride) {
            showNoSalePINSheet = true
            return
        }
        // Manager/self-authorized — operator is also the approver when they have override.
        if sessionManager.can(.managerOverride) {
            authorizingManagerUser = resolveCashDrawerOperatorUser()
        }
        performNoSale(
            reasonCode: pendingNoSaleReasonCode,
            authorizingManager: authorizingManagerUser
        )
    }

    // H-1: No-Sale — เปิดลิ้นชักเงินสดโดยไม่มีการขาย (ต้องมีสิทธิ์ + บันทึกเหตุผล/ผู้อนุมัติ)
    private func performNoSale(reasonCode: String, authorizingManager: User?) {
        guard let session = activeSession else { return }
        guard canOpenCashDrawer else {
            noSaleError = "no_sale_permission_denied".t
            return
        }

        let operatorUser = resolveCashDrawerOperatorUser()
        let employeeId = employees.first(where: { $0.user?.id == operatorUser.id })?.id
            ?? sessionManager.currentStaffSession?.employeeId
        let reasonLabel = noSaleReasonOptions.first(where: { $0.code == reasonCode })?.key.t
            ?? "no_sale_reason".t
        let approverName = authorizingManager?.username ?? "self"
        let detail = "Cash drawer opened — No Sale | reason=\(reasonCode) | operator=\(operatorUser.username) | approved_by=\(approverName)"

        // 1. CashMovement audit trail
        let movement = CashMovement(
            registerSession: session,
            movementType: "no_sale",
            amount: 0.0,
            reason: reasonLabel,
            performedByEmployeeId: employeeId,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        modelContext.insert(movement)
        AccountingLedgerService.recordCashMovement(movement, in: modelContext)

        // 2. AuditLog with employee + approver details
        let audit = AuditLog(
            employeeId: employeeId,
            actionType: "no_sale",
            details: detail,
            originalValue: 0,
            newValue: 0
        )
        modelContext.insert(audit)
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        // 3. Kick cash drawer via receipt printer pulse
        Task {
            await PrintService.shared.openCashDrawer()
        }

        // 4. Sync
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }

        pendingNoSaleReasonCode = ""
        authorizingManagerUser = nil
    }

    private func closeRegisterSession() {
        guard let session = activeSession else { return }
        // Freeze all financial facts before setting closedAt. Computed active-
        // session properties intentionally stop returning data after closure.
        let closeTime = Date()
        let snapshot = makeShiftCloseSnapshot(for: session, closedAt: closeTime)
        let actual = Double(actualCashString) ?? 0.0
        let discrepancy = actual - snapshot.expectedCash

        let closer = resolveCashDrawerOperatorUser()
        session.closedAt = closeTime
        session.expectedClosingCash = snapshot.expectedCash
        session.actualClosingCash = actual
        session.cashDiscrepancy = discrepancy
        session.closedByUserId = closer.id

        var noteParts: [String] = []
        if abs(discrepancy) >= 0.005, !varianceReasonCode.isEmpty {
            let reasonLabel = varianceReasonOptions.first(where: { $0.code == varianceReasonCode })?.key.t ?? varianceReasonCode
            noteParts.append("Variance: \(reasonLabel)")
        }
        if !closingNotes.isEmpty {
            noteParts.append(closingNotes)
        }
        session.notes = noteParts.isEmpty ? session.notes : noteParts.joined(separator: " | ")
        session.isSynced = false
        session.updatedAt = Date()

        // Create ShiftReport
        let report = ShiftReport(
            registerSession: session,
            reportType: "Z",
            grossSales: snapshot.grossSales,
            netSales: snapshot.netSales,
            totalTax: snapshot.totalTax,
            totalDiscounts: snapshot.totalDiscounts,
            totalRefunds: snapshot.totalRefunds,
            cashExpected: snapshot.expectedCash,
            cashActual: actual,
            overShort: discrepancy,
            generatedByEmployee: employees.first(where: { $0.user?.id == closer.id })
        )
        modelContext.insert(report)
        AccountingLedgerService.createClosureSnapshot(
            session: session,
            report: report,
            serviceCharge: snapshot.serviceCharge,
            cashIn: snapshot.cashIn,
            cashOut: snapshot.cashOut,
            transactionCount: snapshot.receiptCount,
            generatedByUserId: closer.id,
            in: modelContext
        )

        modelContext.saveWithLogging(label: #function)

        // Persist a consistent SwiftData snapshot outside the app container.
        // The selected Files folder survives uninstalling AlphaPos.
        do {
            try LocalExternalBackupManager.shared.createShiftCloseBackup(
                modelContext: modelContext,
                sessionID: session.id,
                closedAt: closeTime
            )
        } catch {
            localBackupError = error.localizedDescription
        }

        // Open Z-Report modal
        zReportSnapshot = snapshot
        zReportSession = session
        APHaptic.trigger()

        // ── Auto-print Z-Report ────────────────────────────────────────
        // พิมพ์อัตโนมัติเฉพาะเมื่อ "print_close_shift" = true ใน Settings
        let capturedSession  = session
        let capturedReport   = report
        Task {
            await PrintService.shared.printZReport(
                session:         capturedSession,
                report:          capturedReport,
                tenders: snapshot.tenders,
                receiptCount: snapshot.receiptCount,
                failedPaymentCount: snapshot.failedPaymentCount,
                cashMovementsIn: snapshot.cashIn,
                cashMovementsOut: snapshot.cashOut,
                openedBy: snapshot.openedBy,
                closedBy: snapshot.closedBy,
                isThai: lm.currentLanguage == .thai
            )
        }

        Task {
            // Ensure parents exist on server (create if missing), then upload report with FKs.
            do {
                let result = try await NetworkManager.shared.uploadShiftReportDetailed(report)
                if result.success {
                    report.isSynced = true
                    modelContext.saveWithLogging(label: #function)
                }
            } catch {
                #if DEBUG
                print("Failed to sync ShiftReport: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func resolvePaymentTenderInfo(_ payment: Payment) -> (name: String, isDelivery: Bool) {
        if let order = payment.order, order.orderType == "delivery" || (order.deliveryBrand != nil && !order.deliveryBrand!.isEmpty) {
            let brand = order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let brand, !brand.isEmpty {
                return (brand, true)
            }
            return (lm.currentLanguage == .thai ? "เดลิเวอรี่" : "Delivery", true)
        }
        let lower = payment.paymentMethod.lowercased()
        let deliveryKeywords = ["delivery", "grab", "line_man", "lineman", "shopee", "foodpanda", "robinhood"]
        if deliveryKeywords.contains(where: { lower.contains($0) }) {
            return (shiftTenderName(payment.paymentMethod), true)
        }
        return (shiftTenderName(payment.paymentMethod), false)
    }

    private func makeShiftCloseSnapshot(for session: RegisterSession, closedAt: Date) -> ShiftCloseSnapshot {
        let payments = branchPayments.filter {
            !$0.isDeleted && ($0.registerSessionId == session.id || ($0.registerSessionId == nil && $0.paidAt >= session.openedAt && $0.paidAt <= closedAt))
        }
        let captured = payments.filter(\.isCaptured)
        var orderMap: [UUID: Order] = [:]
        for payment in captured {
            if let order = payment.order { orderMap[order.id] = order }
        }
        let orders = orderMap.values.filter(\.isRecognizedSale)
        let refunds = branchRefunds.filter {
            !$0.isDeleted && $0.status == "completed" && ($0.registerSessionId == session.id || ($0.registerSessionId == nil && $0.financialEventAt >= session.openedAt && $0.financialEventAt <= closedAt))
        }

        var received: [String: (amount: Double, count: Int, isDelivery: Bool)] = [:]
        for payment in captured where payment.order?.usesGovernmentSupport != true {
            let info = resolvePaymentTenderInfo(payment)
            let current = received[info.name] ?? (0, 0, info.isDelivery)
            received[info.name] = (current.amount + payment.amount, current.count + 1, info.isDelivery)
        }
        let programOrders = orders.filter(\.usesGovernmentSupport)
        if !programOrders.isEmpty {
            received[GovernmentSupportProgram.thaiChuaThaiPlus] = (
                // Refunds are deducted once below, within the selected shift.
                programOrders.reduce(0) { $0 + $1.total },
                programOrders.count,
                false
            )
        }

        var refunded: [String: (amount: Double, isDelivery: Bool)] = [:]
        for refund in refunds {
            let info: (name: String, isDelivery: Bool)
            if refund.order?.usesGovernmentSupport == true {
                info = (GovernmentSupportProgram.thaiChuaThaiPlus, false)
            } else if let original = refund.originalPayment {
                info = resolvePaymentTenderInfo(original)
            } else {
                let lower = refund.refundMethod.lowercased()
                let isDel = ["delivery", "grab", "line_man", "lineman", "shopee", "foodpanda", "robinhood"].contains(where: { lower.contains($0) })
                info = (shiftTenderName(refund.refundMethod), isDel)
            }
            let current = refunded[info.name] ?? (0, info.isDelivery)
            refunded[info.name] = (current.amount + refund.refundAmount, info.isDelivery)
        }

        let allMethods = Set(received.keys).union(refunded.keys)
        let tenders = allMethods.map { method in
            let rec = received[method] ?? (0, 0, false)
            let ref = refunded[method] ?? (0, false)
            let isDel = rec.isDelivery || ref.isDelivery
            return ShiftTenderSummary(
                method: method,
                count: rec.count,
                received: rec.amount,
                refunded: ref.amount,
                isDelivery: isDel
            )
        }.sorted { $0.received > $1.received }

        let movements = branchCashMovements.filter {
            !$0.isDeleted && $0.registerSession?.id == session.id
        }
        let cashIn = movements.filter { $0.movementType == "cash_in" || $0.movementType == "paid_in" }.reduce(0) { $0 + $1.amount }
        let cashOut = movements.filter { $0.movementType == "cash_out" || $0.movementType == "paid_out" }.reduce(0) { $0 + $1.amount }
        let cash = tenders.first { $0.method == shiftTenderName("cash") }
        let expected = session.openingCash + (cash?.received ?? 0) - (cash?.refunded ?? 0) + cashIn - cashOut
        let gross = orders.reduce(0) { $0 + $1.total + $1.discount }
        let discounts = orders.reduce(0) { $0 + $1.discount }
        let totalRefunds = refunds.reduce(0) { $0 + $1.refundAmount }

        return ShiftCloseSnapshot(
            tenders: tenders,
            receiptCount: orders.count,
            failedPaymentCount: payments.filter { $0.status == "failed" }.count,
            grossSales: gross,
            netSales: max(0, gross - discounts - totalRefunds),
            totalTax: orders.reduce(0) { $0 + $1.tax },
            serviceCharge: orders.reduce(0) { $0 + $1.serviceCharge },
            totalDiscounts: discounts,
            totalRefunds: totalRefunds,
            cashIn: cashIn,
            cashOut: cashOut,
            expectedCash: expected,
            openedBy: displayName(forUserId: session.openedByUserId),
            closedBy: displayName(forUserId: resolveCashDrawerOperatorUser().id)
        )
    }

    private func shiftTenderName(_ raw: String) -> String {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "cash": return lm.currentLanguage == .thai ? "เงินสด" : "Cash"
        case "card", "credit_card", "debit_card": return lm.currentLanguage == .thai ? "บัตรเครดิต/เดบิต" : "Card"
        case "qr", "qr_promptpay", "promptpay", "transfer", "bank_transfer": return "PromptPay / QR"
        case "true_money": return "TrueMoney"
        case "original_tender": return lm.currentLanguage == .thai ? "ช่องทางเดิม" : "Original tender"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Formatting Helpers

    private func displayName(forUserId id: UUID) -> String {
        if let user = users.first(where: { $0.id == id }) {
            return user.username
        }
        if let emp = employees.first(where: { $0.user?.id == id }) {
            return [emp.firstName, emp.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return String(id.uuidString.prefix(8)).uppercased()
    }

    private func displayName(forEmployeeId id: UUID?) -> String? {
        guard let id else { return nil }
        if let emp = employees.first(where: { $0.id == id }) {
            let name = [emp.firstName, emp.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? emp.user?.username : name
        }
        return nil
    }

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

    private func isVerifiedZeroSalesShift(_ session: RegisterSession) -> Bool {
        guard let report = allShiftReports.first(where: { $0.registerSession?.id == session.id }) else { return false }
        guard abs(report.grossSales) < 0.005 && abs(report.netSales) < 0.005 else { return false }
        return !branchPayments.contains { !$0.isDeleted && $0.status == "completed" && ($0.registerSessionId == session.id || ($0.registerSessionId == nil && $0.paidAt >= session.openedAt && $0.paidAt <= (session.closedAt ?? Date()))) }
    }

    private func requestDeleteShiftAuthorization() {
        guard pendingDeleteSession != nil else { return }
        if sessionManager.can(.managerOverride) { deleteVerifiedZeroSalesShift() }
        else { showDeleteShiftPINSheet = true }
    }

    private func deleteVerifiedZeroSalesShift() {
        guard let session = pendingDeleteSession, isVerifiedZeroSalesShift(session) else { pendingDeleteSession = nil; return }
        if let report = allShiftReports.first(where: { $0.registerSession?.id == session.id }) {
            report.isDeleted = true; report.isSynced = false; report.updatedAt = Date()
        }
        session.isDeleted = true; session.isSynced = false; session.updatedAt = Date()
        modelContext.saveWithLogging(label: "deleteVerifiedZeroSalesShift")
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
        pendingDeleteSession = nil
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
                                    zReportSnapshot = makeShiftCloseSnapshot(for: session, closedAt: session.closedAt ?? Date())
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

                                if isVerifiedZeroSalesShift(session) {
                                    Button(role: .destructive) {
                                        pendingDeleteSession = session
                                        showDeleteShiftConfirm = true
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("ลบกะที่ไม่มียอดขาย")
                                }
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

private struct ShiftCloseSnapshot {
    let tenders: [ShiftTenderSummary]
    let receiptCount: Int
    let failedPaymentCount: Int
    let grossSales: Double
    let netSales: Double
    let totalTax: Double
    let serviceCharge: Double
    let totalDiscounts: Double
    let totalRefunds: Double
    let cashIn: Double
    let cashOut: Double
    let expectedCash: Double
    let openedBy: String
    let closedBy: String
}

private struct ReceiptDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

private struct ReceiptDivider: View {
    var dashed: Bool = true
    var body: some View {
        if dashed {
            ReceiptDashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.4))
                .padding(.vertical, 2)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }
}
