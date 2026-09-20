import SwiftUI
import SwiftData

// MARK: - SystemOpsSettingsView
// ─────────────────────────────────────────────────────────────────────────────
// Redesigned with Multi-tenant safety:
//   • All local FetchDescriptor calls are scoped by active_merchant_id via
//     isSynced-path matching (Models don't store merchantId locally — we use
//     NetworkManager's active_merchant_id only for remote DELETE).
//   • wipeRemoteTransactionsAndSessions() now exists in NetworkManager+Orders
//     and always filters by merchant_id.
//   • Owner PIN is read from Keychain (not UserDefaults).
//   • Server URLs are validated and test-connected before saving.
//   • Every destructive action logs to AuditLog model.
// ─────────────────────────────────────────────────────────────────────────────

struct SystemOpsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    // MARK: - Status / Alert States
    @State private var statusMessage = ""
    @State private var showingStatusAlert = false
    @State private var statusIsError = false
    @State private var isRecoveringLocalCache = false

    // MARK: - Wipe Flow States
    @State private var isResettingTransactions = false
    @State private var showingWipeConfirmSheet = false   // Step 1: context sheet
    @State private var showingPinPrompt = false          // Step 2: PIN
    @State private var enteredPin = ""
    @State private var showingPinErrorAlert = false
    @State private var pinAttempts = 0
    @State private var showingSelectiveResetSheet = false
    @State private var selectedResetCategories: Set<OperationalResetCategory> = []
    @State private var pendingSelectiveReset = false

    @State private var supabaseURLDraft: String = ""
    @State private var localServerURLDraft: String = ""
    @State private var customerWebURLDraft: String = ""
    @State private var supabaseURLError: String? = nil
    @State private var localURLError: String? = nil
    @State private var customerWebURLError: String? = nil
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String? = nil
    @State private var connectionTestOK = false
    @State private var serverConfigDirty = false

    // MARK: - Audit Log
    @State private var recentAuditLogs: [AuditLog] = []

    // MARK: - Computed
    private var activeMerchantId: String {
        UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
    }

    private var activeSubscriptionTier: String {
        let tier = MerchantAuthManager.shared.subscriptionTier ?? ""
        return tier.isEmpty ? "ไม่ทราบแพ็กเกจ" : tier
    }

    /// Offline subscriptions must never attempt a cloud delete. Also respect
    /// the effective runtime policy in case an online plan is temporarily put
    /// into offline mode.
    private var usesLocalOnlyStorage: Bool {
        OfflineSyncModeController.isOfflineSubscriptionPlan
            || NetworkPolicy.shared.mode == .offlineOnly
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Body
    // ─────────────────────────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── 1. Tenant Scope Banner ────────────────────────────
                    tenantScopeBanner

                    // ── 2. Data Operations ────────────────────────────────
                    dataOperationsSection

                    // ── 3. Danger Zone ────────────────────────────────────
                    dangerZoneSection

                    // ── 4. Server Configuration ───────────────────────────
                    serverConfigSection

                    // ── 5. Audit Trail ────────────────────────────────────
                    auditLogSection
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.systemOps.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear { loadDrafts(); loadRecentAuditLogs() }

        // ── Alerts & Sheets ──────────────────────────────────────────────
        .alert(statusIsError ? "❌ Error" : "✅ สำเร็จ",
               isPresented: $showingStatusAlert) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text(statusMessage)
        }

        // Wipe — Step 1: Context confirmation sheet
        .confirmationDialog(
            "sysops_wipe_title".t,
            isPresented: $showingWipeConfirmSheet,
            titleVisibility: .visible
        ) {
            Button("sysops_wipe_confirm_btn".t, role: .destructive) {
                enteredPin = ""
                showingPinPrompt = true
            }
            Button("cancel".t, role: .cancel) {}
        } message: {
            Text("การกระทำนี้จะลบ:\n• เซสชันโต๊ะทั้งหมด\n• ออร์เดอร์และรายการอาหาร\n• การชำระเงิน\n\nแพ็กเกจ: \(activeSubscriptionTier)\nขอบเขต: \(usesLocalOnlyStorage ? "SwiftData ในอุปกรณ์นี้เท่านั้น" : "Cloud และ SwiftData ของ Merchant \(activeMerchantId)")\nเมนูและพนักงานจะไม่ถูกกระทบ\n\nไม่สามารถยกเลิกได้")
        }

        // Wipe — Step 2: PIN from Keychain
        .alert("sysops_pin_confirm_title".t,
               isPresented: $showingPinPrompt) {
            SecureField("PIN 4 หลัก", text: $enteredPin)
                .keyboardType(.numberPad)
            Button("sysops_confirm".t) { verifyPinAndProceed() }
            Button("cancel".t, role: .cancel) {
                enteredPin = ""
                pinAttempts = 0
                pendingSelectiveReset = false
            }
        } message: {
            Text("กรอก PIN เจ้าของร้านเพื่อยืนยันการล้างข้อมูล\n(เหลือ \(3 - pinAttempts) ครั้ง)")
        }

        .sheet(isPresented: $showingSelectiveResetSheet) {
            SelectiveOperationalResetSheet(
                isPresented: $showingSelectiveResetSheet,
                selectedCategories: $selectedResetCategories,
                subscriptionTier: activeSubscriptionTier,
                usesLocalOnlyStorage: usesLocalOnlyStorage
            ) {
                pendingSelectiveReset = true
                enteredPin = ""
                showingPinPrompt = true
            }
        }

        .alert("sysops_pin_wrong_title".t,
               isPresented: $showingPinErrorAlert) {
            Button("sysops_try_again".t) {
                enteredPin = ""
                if pinAttempts < 3 { showingPinPrompt = true }
            }
            Button("cancel".t, role: .cancel) {
                pinAttempts = 0
                pendingSelectiveReset = false
            }
        } message: {
            Text(pinAttempts >= 3
                 ? "ลองผิดครบ 3 ครั้ง กรุณาล็อกเอาท์แล้วเข้าสู่ระบบใหม่"
                 : "PIN ที่กรอกไม่ถูกต้อง (\(pinAttempts)/3 ครั้ง)")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Tenant Scope Banner
    // ─────────────────────────────────────────────────────────────────────────
    private var tenantScopeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("sysops_scope_title".t)
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(Color.blue)
                Text("Merchant ID: \(activeMerchantId)")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("แพ็กเกจ: \(activeSubscriptionTier) • \(usesLocalOnlyStorage ? "SwiftData ในเครื่อง" : "Cloud + SwiftData")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(usesLocalOnlyStorage ? .orange : .blue)
            }

            Spacer()

            Label("sysops_isolated".t, systemImage: "lock.fill")
                .font(.system(size: 12))
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Data Operations
    // ─────────────────────────────────────────────────────────────────────────
    private var dataOperationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("sysops_data_ops".t, icon: "wrench.and.screwdriver.fill", color: .appAccent)

            VStack(spacing: 0) {
                // Clear Local Cache
                operationRow(
                    icon: "internaldrive",
                    iconColor: .orange,
                    title: "sysops_clear_cache_title".t,
                    subtitle: "sysops_clear_cache_sub".t,
                    badge: .localOnly
                ) {
                    APHaptic.trigger()
                    startCacheRecovery()
                }

                Divider().padding(.leading, 58)

                // Force Sync
                operationRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    iconColor: .green,
                    title: "sysops_force_sync_title".t,
                    subtitle: "sysops_force_sync_sub".t
                ) {
                    APHaptic.trigger()
                    Task {
                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                        await MainActor.run {
                            statusMessage = "sysops_sync_done".t
                            statusIsError = false
                            showingStatusAlert = true
                        }
                    }
                }
            }
            .apCard()
        }
        .padding(.horizontal)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Danger Zone
    // ─────────────────────────────────────────────────────────────────────────
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("sysops_danger_zone".t, icon: "exclamationmark.triangle.fill", color: .appRose)

            VStack(spacing: 0) {
                if isResettingTransactions {
                    HStack(spacing: 12) {
                        ProgressView().tint(.appRose)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("sysops_wiping".t)
                                .font(.system(size: 12))
                                .foregroundColor(.textPrimary)
                            Text(LocalizationManager.shared.t("sysops_wiping_remote", activeMerchantId))
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else {
                    operationRow(
                        icon: "checklist",
                        iconColor: .orange,
                        title: "ล้างข้อมูลทดสอบแบบเลือกประเภท",
                        subtitle: "เลือกเฉพาะออร์เดอร์ การชำระเงิน เซสชันโต๊ะ หรือกะเงินสด",
                        badge: .irreversible
                    ) {
                        APHaptic.trigger()
                        selectedResetCategories = []
                        showingSelectiveResetSheet = true
                    }

                    Divider().padding(.leading, 58)

                    // Wipe Orders & Sessions
                    operationRow(
                        icon: "trash.fill",
                        iconColor: .appRose,
                        title: "sysops_wipe_title".t,
                        subtitle: "sysops_wipe_sub".t,
                        badge: .irreversible
                    ) {
                        APHaptic.trigger()
                        pendingSelectiveReset = false
                        showingWipeConfirmSheet = true
                    }
                }
            }
            .apCard()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appRose.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Server Configuration
    // ─────────────────────────────────────────────────────────────────────────
    private var serverConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("sysops_server_config".t, icon: "server.rack", color: .appAccent)

            VStack(alignment: .leading, spacing: 14) {

                // Supabase URL
                serverURLField(
                    label: "sysops_supabase_url".t,
                    placeholder: "https://api.alphaposweb.com",
                    text: $supabaseURLDraft,
                    error: supabaseURLError
                )

                // Local Worker URL
                serverURLField(
                    label: "sysops_local_worker_url".t,
                    placeholder: "http://192.168.x.x:8080",
                    text: $localServerURLDraft,
                    error: localURLError
                )

                // Customer Web URL
                serverURLField(
                    label: "sysops_customer_web_url".t,
                    placeholder: "https://sync.alphaposweb.com",
                    text: $customerWebURLDraft,
                    error: customerWebURLError
                )

                // Test + Save buttons
                HStack(spacing: 10) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingConnection {
                                ProgressView().scaleEffect(0.75).tint(.appAccent)
                            } else {
                                Image(systemName: connectionTestOK ? "checkmark.circle.fill" : "wifi")
                                    .foregroundColor(connectionTestOK ? .green : .appAccent)
                            }
                            Text("printer_test_connection".t)
                                .font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)
                    .disabled(isTestingConnection)

                    Button {
                        saveServerURLs()
                    } label: {
                        Label("save".t, systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(!serverConfigDirty)
                }

                if let result = connectionTestResult {
                    Label(result, systemImage: connectionTestOK ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(connectionTestOK ? .green : .appRose)
                }

                Text("sysops_restart_hint".t)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .italic()
            }
            .apCard()
        }
        .padding(.horizontal)
    }

    private func serverURLField(label: String, placeholder: String,
                                text: Binding<String>, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .fontWeight(.medium)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .foregroundColor(.textPrimary)
                .onChange(of: text.wrappedValue) { _, _ in
                    serverConfigDirty = true
                    connectionTestResult = nil
                    connectionTestOK = false
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(error != nil ? Color.appRose : Color.clear, lineWidth: 1.5)
                )
            if let err = error {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.appRose)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Audit Log
    // ─────────────────────────────────────────────────────────────────────────
    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("sysops_audit_trail".t, icon: "list.bullet.clipboard", color: .appAccent)

            if recentAuditLogs.isEmpty {
                HStack {
                    Spacer()
                    Text("sysops_audit_empty".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 16)
                .apCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(recentAuditLogs.prefix(5)) { log in
                        auditLogRow(log)
                        if log.id != recentAuditLogs.prefix(5).last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .apCard()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func auditLogRow(_ log: AuditLog) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForActionType(log.actionType))
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .frame(width: 28, height: 28)
                .background(Color.textSecondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameForAction(log.actionType))
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary)
                Text(log.details ?? "—")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(log.createdAt, style: .time)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                Text(log.createdAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Reusable Sub-Views
    // ─────────────────────────────────────────────────────────────────────────

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12))
            .fontWeight(.bold)
            .foregroundColor(color)
            .tracking(0.8)
    }

    enum OperationBadge { case devOnly, localOnly, irreversible, blocked }

    private func operationRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        badge: OperationBadge? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(disabled ? .textSecondary : .textPrimary)
                        if let b = badge { badgeView(b) }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(.systemFill).opacity(0.6))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func badgeView(_ badge: OperationBadge) -> some View {
        switch badge {
        case .devOnly:
            badgeLabel("sysops_badge_dev".t, color: .green)
        case .localOnly:
            badgeLabel("sysops_badge_local".t, color: .orange)
        case .irreversible:
            badgeLabel("sysops_badge_irreversible".t, color: .appRose)
        case .blocked:
            badgeLabel("sysops_badge_blocked".t, color: .gray)
        }
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .overlay(
                Capsule().stroke(color.opacity(0.3), lineWidth: 0.75)
            )
            .clipShape(Capsule())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Clear Local Cache (SCOPED)
    // ─────────────────────────────────────────────────────────────────────────
    /// ลบเฉพาะ local SwiftData records — ไม่ DELETE จาก Supabase
    /// SwiftData ไม่มี merchantId field ใน Order/TableSession/MenuItem
    /// ดังนั้น "local cache" หมายถึง ALL records ใน SQLite ของ device นี้
    /// (1 device = 1 merchant session เสมอ เพราะ active_merchant_id เป็น device-scoped)
    private func startCacheRecovery() {
        guard !isRecoveringLocalCache else { return }
        isRecoveringLocalCache = true
        statusMessage = "กำลังล้างและกู้ข้อมูลจาก Cloud…"
        statusIsError = false

        Task { @MainActor in
            clearLocalCache()

            // Online devices must hydrate the records again before reporting
            // success. Without this, TableView observes an empty SwiftData
            // store and incorrectly renders the first-table empty state.
            if !usesLocalOnlyStorage,
               TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
               MerchantAuthManager.shared.isAuthenticated {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }

            isRecoveringLocalCache = false
            statusMessage = usesLocalOnlyStorage
                ? "ล้าง local cache เสร็จสิ้น\nข้อมูลแบบ Offline จะถูกสร้างใหม่เมื่อมีการเพิ่มข้อมูล"
                : "ล้าง local cache และกู้ข้อมูลจาก Cloud เสร็จสิ้น"
            statusIsError = SyncEngine.shared.syncStatus == .error
            showingStatusAlert = true
            loadRecentAuditLogs()
        }
    }

    private func clearLocalCache() {
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for t in tables { modelContext.delete(t) }
        }
        if let sessions = try? modelContext.fetch(FetchDescriptor<TableSession>()) {
            for s in sessions { modelContext.delete(s) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for o in orders { modelContext.delete(o) }
        }
        if let categories = try? modelContext.fetch(FetchDescriptor<Category>()) {
            for c in categories { modelContext.delete(c) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<MenuItem>()) {
            for i in items { modelContext.delete(i) }
        }
        modelContext.saveWithLogging(label: #function)

        writeAuditLog(action: "system_ops_cache_clear", details: "Cleared local SwiftData cache (device-scoped)")

        // Completion UI is intentionally handled by startCacheRecovery() after
        // the online rehydration has finished.
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Wipe — PIN Verification
    // ─────────────────────────────────────────────────────────────────────────
    private func verifyPinAndProceed() {
        pinAttempts += 1
        if KeychainManager.shared.verifyOwnerPin(enteredPin) {
            pinAttempts = 0
            if pendingSelectiveReset {
                pendingSelectiveReset = false
                performSelectiveOperationalReset()
            } else {
                performStoreTransactionsReset()
            }
        } else {
            if pinAttempts >= 3 {
                showingPinErrorAlert = true
            } else {
                showingPinErrorAlert = true
            }
        }
    }

    private func performSelectiveOperationalReset() {
        let categories = OperationalResetCategory.normalized(selectedResetCategories)
        guard !categories.isEmpty else { return }
        APHaptic.trigger()
        isResettingTransactions = true

        if usesLocalOnlyStorage {
            wipeLocalOperationalData(categories: categories)
            let labels = categories.sorted { $0.sortOrder < $1.sortOrder }.map(\.title).joined(separator: ", ")
            writeAuditLog(
                action: "system_ops_selective_wipe",
                details: "Selective local SwiftData reset: \(labels) (plan: \(activeSubscriptionTier), merchant: \(activeMerchantId))"
            )
            isResettingTransactions = false
            statusMessage = "ล้างข้อมูล SwiftData ในเครื่องเรียบร้อย\n\(labels)\nแพ็กเกจ: \(activeSubscriptionTier) — ไม่มีการเชื่อมต่อหรือลบข้อมูล Cloud"
            statusIsError = false
            showingStatusAlert = true
            loadRecentAuditLogs()
            return
        }

        Task {
            do {
                _ = try await NetworkManager.shared.wipeRemoteOperationalData(
                    categories: categories.map(\.rawValue)
                )
                await MainActor.run {
                    wipeLocalOperationalData(categories: categories)
                    let labels = categories.sorted { $0.sortOrder < $1.sortOrder }.map(\.title).joined(separator: ", ")
                    writeAuditLog(
                        action: "system_ops_selective_wipe",
                        details: "Selective operational reset: \(labels) (merchant: \(activeMerchantId))"
                    )
                    isResettingTransactions = false
                    statusMessage = "ล้างข้อมูลที่เลือกเรียบร้อย\n\(labels)\nเมนู สินค้า พนักงาน และการตั้งค่าร้านยังคงอยู่"
                    statusIsError = false
                    showingStatusAlert = true
                    loadRecentAuditLogs()
                }
            } catch {
                await MainActor.run {
                    isResettingTransactions = false
                    statusMessage = "ล้างข้อมูลล้มเหลว: \(error.localizedDescription)"
                    statusIsError = true
                    showingStatusAlert = true
                }
            }
        }
    }

    private func wipeLocalOperationalData(categories: Set<OperationalResetCategory>) {
        if categories.contains(.payments) {
            deleteAll(PaymentAttempt.self)
            deleteAll(CheckoutSession.self)
            deleteAll(Payment.self)
        }
        if categories.contains(.orders) {
            deleteAll(PrintJobRecord.self)
            deleteAll(Order.self)
        }
        if categories.contains(.tableSessions) {
            deleteAll(TableSession.self)
            if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
                for table in tables {
                    table.status = "vacant"
                    table.isSynced = false
                    table.updatedAt = Date()
                }
            }
        }
        if categories.contains(.registers) {
            deleteAll(CashMovement.self)
            deleteAll(RegisterSession.self)
        }
        modelContext.saveWithLogging(label: #function)
        SyncEngine.shared.resetNotificationRuntimeState()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        if let rows = try? modelContext.fetch(FetchDescriptor<T>()) {
            for row in rows { modelContext.delete(row) }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Wipe Remote + Local (TENANT-SCOPED)
    // ─────────────────────────────────────────────────────────────────────────
    private func performStoreTransactionsReset() {
        APHaptic.trigger()
        isResettingTransactions = true

        if usesLocalOnlyStorage {
            wipeLocalTransactionsAndSessions()
            writeAuditLog(
                action: "system_ops_wipe",
                details: "Wiped local SwiftData sessions/orders/payments (plan: \(activeSubscriptionTier), merchant: \(activeMerchantId))"
            )
            isResettingTransactions = false
            statusMessage = "ล้างข้อมูล SwiftData ในเครื่องเรียบร้อย\nเซสชัน ออร์เดอร์ และการชำระเงินถูกลบแล้ว\nแพ็กเกจ: \(activeSubscriptionTier) — ไม่มีการเชื่อมต่อ Cloud"
            statusIsError = false
            showingStatusAlert = true
            loadRecentAuditLogs()
            return
        }

        Task {
            do {
                // Step 1: DELETE from Supabase — filtered by merchant_id
                _ = try await NetworkManager.shared.wipeRemoteTransactionsAndSessions()

                // Step 2: Wipe local SwiftData
                await MainActor.run {
                    wipeLocalTransactionsAndSessions()
                    writeAuditLog(
                        action: "system_ops_wipe",
                        details: "Wiped all sessions/orders/payments (merchant: \(activeMerchantId))"
                    )
                    isResettingTransactions = false
                    statusMessage = "ล้างข้อมูลเสร็จสิ้น\nเซสชัน ออร์เดอร์ และการชำระเงินถูกลบแล้ว\nMerchant: \(activeMerchantId)"
                    statusIsError = false
                    showingStatusAlert = true
                    loadRecentAuditLogs()
                }
            } catch {
                await MainActor.run {
                    isResettingTransactions = false
                    statusMessage = "ล้างข้อมูลล้มเหลว: \(error.localizedDescription)"
                    statusIsError = true
                    showingStatusAlert = true
                }
            }
        }
    }

    private func wipeLocalTransactionsAndSessions() {
        if let sessions = try? modelContext.fetch(FetchDescriptor<TableSession>()) {
            for s in sessions { modelContext.delete(s) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for o in orders { modelContext.delete(o) }
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<Payment>()) {
            for p in payments { modelContext.delete(p) }
        }
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for t in tables {
                t.status = "vacant"
                t.isSynced = false
                t.updatedAt = Date()
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Server URL
    // ─────────────────────────────────────────────────────────────────────────
    private func loadDrafts() {
        supabaseURLDraft = UserDefaults.standard.string(forKey: "dynamic_supabase_url")
            ?? AppConfig.shared.supabaseURL.absoluteString
        localServerURLDraft = UserDefaults.standard.string(forKey: "dynamic_local_server_url")
            ?? AppConfig.shared.localServerURL
        customerWebURLDraft = UserDefaults.standard.string(forKey: "dynamic_customer_web_url")
            ?? "https://sync.alphaposweb.com"
        serverConfigDirty = false
    }

    private func validateURLs() -> Bool {
        supabaseURLError = nil
        localURLError = nil
        customerWebURLError = nil
        var valid = true

        if supabaseURLDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            supabaseURLError = "URL ต้องไม่ว่างเปล่า"
            valid = false
        } else if URL(string: supabaseURLDraft)?.host == nil {
            supabaseURLError = "URL รูปแบบไม่ถูกต้อง"
            valid = false
        } else if let host = URL(string: supabaseURLDraft)?.host,
                  host == "supabase.co" || host.hasSuffix(".supabase.co") {
            supabaseURLError = "รองรับเฉพาะ Supabase VPS แบบ self-hosted"
            valid = false
        }

        if localServerURLDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            localURLError = "URL ต้องไม่ว่างเปล่า"
            valid = false
        } else if URL(string: localServerURLDraft)?.host == nil {
            localURLError = "URL รูปแบบไม่ถูกต้อง"
            valid = false
        }

        if customerWebURLDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            customerWebURLError = "URL ต้องไม่ว่างเปล่า"
            valid = false
        } else if URL(string: customerWebURLDraft)?.host == nil {
            customerWebURLError = "URL รูปแบบไม่ถูกต้อง"
            valid = false
        }

        return valid
    }

    private func testConnection() async {
        guard validateURLs() else { return }

        await MainActor.run {
            isTestingConnection = true
            connectionTestResult = nil
            connectionTestOK = false
        }

        do {
            // Ping Supabase REST endpoint
            guard let url = URL(string: supabaseURLDraft + "/rest/v1/") else {
                throw URLError(.badURL)
            }
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue(AppConfig.shared.supabaseAnonKey, forHTTPHeaderField: "apikey")
            let (_, response) = try await AppNetworkTransport.data(for: req, purpose: .connectivityProbe)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0

            await MainActor.run {
                isTestingConnection = false
                if (200...299).contains(code) || code == 404 {
                    // 404 is fine — means Supabase is responding (path not found, not server down)
                    connectionTestOK = true
                    connectionTestResult = "✓ เชื่อมต่อสำเร็จ (HTTP \(code))"
                } else {
                    connectionTestOK = false
                    connectionTestResult = "✗ ไม่สามารถเชื่อมต่อได้ (HTTP \(code))"
                }
            }
        } catch {
            await MainActor.run {
                isTestingConnection = false
                connectionTestOK = false
                connectionTestResult = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func saveServerURLs() {
        guard validateURLs() else { return }
        UserDefaults.standard.set(supabaseURLDraft, forKey: "dynamic_supabase_url")
        UserDefaults.standard.set(localServerURLDraft, forKey: "dynamic_local_server_url")
        UserDefaults.standard.set(customerWebURLDraft, forKey: "dynamic_customer_web_url")
        serverConfigDirty = false
        writeAuditLog(action: "system_ops_server_config",
                      details: "Updated server URLs: \(supabaseURLDraft)")
        statusMessage = "บันทึก URL เรียบร้อย\nต้อง restart app เพื่อให้มีผล"
        statusIsError = false
        showingStatusAlert = true
        loadRecentAuditLogs()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Audit Log Helpers
    // ─────────────────────────────────────────────────────────────────────────
    private func writeAuditLog(action: String, details: String) {
        let log = AuditLog(
            actionType: action,
            details: details,
            createdAt: Date()
        )
        modelContext.insert(log)
        modelContext.saveWithLogging(label: #function)
    }

    private func loadRecentAuditLogs() {
        var desc = FetchDescriptor<AuditLog>(
            predicate: #Predicate { log in
                log.actionType.starts(with: "system_ops")
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        desc.fetchLimit = 10
        recentAuditLogs = (try? modelContext.fetch(desc)) ?? []
    }

    private func iconForActionType(_ type: String) -> String {
        switch type {
        case "system_ops_selective_wipe": return "checklist"
        case "system_ops_wipe": return "trash.fill"
        case "system_ops_cache_clear": return "internaldrive"
        case "system_ops_server_config": return "server.rack"
        default: return "gear"
        }
    }

    private func displayNameForAction(_ type: String) -> String {
        switch type {
        case "system_ops_selective_wipe": return "ล้างข้อมูลแบบเลือกประเภท"
        case "system_ops_wipe": return "ล้างออร์เดอร์ & เซสชัน"
        case "system_ops_cache_clear": return "ล้าง Local Cache"
        case "system_ops_server_config": return "เปลี่ยน Server URL"
        default: return type
        }
    }
}

enum OperationalResetCategory: String, CaseIterable, Identifiable, Hashable {
    case orders = "orders"
    case payments = "payments"
    case tableSessions = "table_sessions"
    case registers = "registers"

    var id: String { rawValue }
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    var title: String {
        switch self {
        case .orders: return "ออร์เดอร์และรายการที่สั่ง"
        case .payments: return "การชำระเงินและขั้นตอนเช็กเอาต์"
        case .tableSessions: return "เซสชันโต๊ะและคำขอบริการ"
        case .registers: return "กะเครื่องคิดเงินและเงินเข้า–ออก"
        }
    }

    var detail: String {
        switch self {
        case .orders: return "ประวัติออร์เดอร์ รายการอาหาร ส่วนลด ภาษี ทิป คืนเงิน และประวัติการพิมพ์"
        case .payments: return "วิธีชำระ ยอดชำระ payment attempts และ checkout sessions"
        case .tableSessions: return "เซสชันโต๊ะและคำขอบริการ พร้อมคืนสถานะโต๊ะเป็นว่าง"
        case .registers: return "ประวัติเปิด–ปิดกะและรายการนำเงินเข้า/ออกลิ้นชัก"
        }
    }

    var icon: String {
        switch self {
        case .orders: return "doc.text.fill"
        case .payments: return "creditcard.fill"
        case .tableSessions: return "tablecells.fill"
        case .registers: return "cashregister.fill"
        }
    }

    static func normalized(_ selection: Set<Self>) -> Set<Self> {
        var result = selection
        // Orders cannot be removed remotely while captured payments still
        // reference them. Include the financial lifecycle automatically.
        if result.contains(.orders) { result.insert(.payments) }
        return result
    }
}

private struct SelectiveOperationalResetSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedCategories: Set<OperationalResetCategory>
    let subscriptionTier: String
    let usesLocalOnlyStorage: Bool
    let onContinue: () -> Void

    private var normalized: Set<OperationalResetCategory> {
        OperationalResetCategory.normalized(selectedCategories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: usesLocalOnlyStorage ? "internaldrive.fill" : "icloud.and.arrow.down.fill")
                            .foregroundColor(usesLocalOnlyStorage ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("แพ็กเกจ: \(subscriptionTier)")
                                .font(.system(size: 12, weight: .bold))
                            Text(usesLocalOnlyStorage
                                 ? "โหมดออฟไลน์ — ลบเฉพาะฐานข้อมูล SwiftData ในเครื่อง"
                                 : "โหมดออนไลน์ — ลบทั้ง Cloud และ SwiftData ในเครื่อง")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((usesLocalOnlyStorage ? Color.orange : Color.blue).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("เลือกเฉพาะข้อมูลทดสอบที่ต้องการล้าง ข้อมูลเมนู สินค้า พนักงาน ลูกค้า และการตั้งค่าร้านจะไม่ถูกลบ")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(OperationalResetCategory.allCases) { category in
                            let selected = normalized.contains(category)
                            Button {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                                APHaptic.trigger()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: category.icon)
                                        .foregroundColor(selected ? .appRose : .textSecondary)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(category.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        Text(category.detail)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if category == .payments,
                                           selected,
                                           !selectedCategories.contains(.payments) {
                                            Text("จำเป็นสำหรับการลบออร์เดอร์")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selected ? .appRose : .textTertiary)
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            if category != OperationalResetCategory.allCases.last {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .apCard()

                    Text(usesLocalOnlyStorage
                         ? "รายการนี้ลบเฉพาะ SwiftData บนอุปกรณ์นี้ และไม่สามารถย้อนกลับได้"
                         : "รายการนี้ลบจากร้านปัจจุบันทั้งบนเซิร์ฟเวอร์และอุปกรณ์ และไม่สามารถย้อนกลับได้")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appRose)
                }
                .padding()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("ล้างข้อมูลทดสอบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ดำเนินการต่อ") {
                        isPresented = false
                        onContinue()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.appRose)
                    .disabled(normalized.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SystemOpsSettingsView()
    }
}
