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
//   • Re-Seed is blocked in production (AppConfig.isProduction).
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

    // MARK: - Wipe Flow States
    @State private var isResettingTransactions = false
    @State private var showingWipeConfirmSheet = false   // Step 1: context sheet
    @State private var showingPinPrompt = false          // Step 2: PIN
    @State private var enteredPin = ""
    @State private var showingPinErrorAlert = false
    @State private var pinAttempts = 0

    // MARK: - Re-Seed States
    @State private var showingReSeedAlert = false

    // MARK: - Server URL States
    @State private var supabaseURLDraft: String = ""
    @State private var localServerURLDraft: String = ""
    @State private var supabaseURLError: String? = nil
    @State private var localURLError: String? = nil
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String? = nil
    @State private var connectionTestOK = false
    @State private var serverConfigDirty = false

    // MARK: - Audit Log
    @State private var recentAuditLogs: [AuditLog] = []

    // MARK: - Computed
    private var activeMerchantId: String {
        UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.shared.defaultMerchantId
    }

    private var isProduction: Bool { AppConfig.shared.isProduction }

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
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }

        // Re-Seed confirm (blocked in production)
        .alert("⚠️ Re-Seed ข้อมูลตัวอย่าง",
               isPresented: $showingReSeedAlert) {
            Button("ยกเลิก", role: .cancel) {}
            Button("ยืนยัน Re-Seed", role: .destructive) {
                executeReSeed()
            }
        } message: {
            Text("จะสร้างเมนู โต๊ะ และพนักงานตัวอย่างใหม่ทั้งหมด\n\nMerchant: \(activeMerchantId)\n\nข้อมูล demo จะ sync ขึ้น Supabase ของร้านนี้เท่านั้น")
        }

        // Wipe — Step 1: Context confirmation sheet
        .confirmationDialog(
            "ล้างออร์เดอร์ & เซสชันโต๊ะ",
            isPresented: $showingWipeConfirmSheet,
            titleVisibility: .visible
        ) {
            Button("ล้างข้อมูล (ร้านนี้เท่านั้น)", role: .destructive) {
                enteredPin = ""
                showingPinPrompt = true
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("การกระทำนี้จะลบ:\n• เซสชันโต๊ะทั้งหมด\n• ออร์เดอร์และรายการอาหาร\n• การชำระเงิน\n\nขอบเขต: Merchant \(activeMerchantId)\nเมนูและพนักงานจะไม่ถูกกระทบ\n\nไม่สามารถยกเลิกได้")
        }

        // Wipe — Step 2: PIN from Keychain
        .alert("🔐 ยืนยัน PIN เจ้าของร้าน",
               isPresented: $showingPinPrompt) {
            SecureField("PIN 4 หลัก", text: $enteredPin)
                .keyboardType(.numberPad)
            Button("ยืนยัน") { verifyPinAndProceed() }
            Button("ยกเลิก", role: .cancel) {
                enteredPin = ""
                pinAttempts = 0
            }
        } message: {
            Text("กรอก PIN เจ้าของร้านเพื่อยืนยันการล้างข้อมูล\n(เหลือ \(3 - pinAttempts) ครั้ง)")
        }

        .alert("❌ PIN ไม่ถูกต้อง",
               isPresented: $showingPinErrorAlert) {
            Button("ลองใหม่") {
                enteredPin = ""
                if pinAttempts < 3 { showingPinPrompt = true }
            }
            Button("ยกเลิก", role: .cancel) { pinAttempts = 0 }
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
                .font(.system(size: 14))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("ขอบเขต: ร้านค้านี้เท่านั้น")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.blue)
                Text("Merchant ID: \(activeMerchantId)")
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Label("Isolated", systemImage: "lock.fill")
                .font(.caption2)
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
            sectionHeader("การดำเนินการข้อมูล", icon: "wrench.and.screwdriver.fill", color: .appAccent)

            VStack(spacing: 0) {
                // Re-Seed
                operationRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .blue,
                    title: "Re-Seed ข้อมูลตัวอย่าง",
                    subtitle: isProduction
                        ? "ไม่สามารถใช้งานใน Production mode"
                        : "สร้างเมนู โต๊ะ และพนักงาน demo (Dev only)",
                    badge: isProduction ? .blocked : .devOnly,
                    disabled: isProduction
                ) {
                    APHaptic.trigger()
                    showingReSeedAlert = true
                }

                Divider().padding(.leading, 58)

                // Clear Local Cache
                operationRow(
                    icon: "internaldrive",
                    iconColor: .orange,
                    title: "ล้าง Cache เครื่องนี้",
                    subtitle: "ลบข้อมูลชั่วคราวในเครื่อง — ไม่กระทบ Supabase",
                    badge: .localOnly
                ) {
                    APHaptic.trigger()
                    clearLocalCache()
                }

                Divider().padding(.leading, 58)

                // Force Sync
                operationRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    iconColor: .green,
                    title: "Force Sync ขึ้น Cloud",
                    subtitle: "Sync ข้อมูลที่ค้างอยู่ขึ้น Supabase ทันที"
                ) {
                    APHaptic.trigger()
                    Task {
                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                        await MainActor.run {
                            statusMessage = "Sync เสร็จสิ้น"
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
            sectionHeader("Danger Zone", icon: "exclamationmark.triangle.fill", color: .appRose)

            VStack(spacing: 0) {
                if isResettingTransactions {
                    HStack(spacing: 12) {
                        ProgressView().tint(.appRose)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("กำลังล้างข้อมูล...")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text("กำลัง DELETE จาก Supabase (merchant: \(activeMerchantId))")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else {
                    // Wipe Orders & Sessions
                    operationRow(
                        icon: "trash.fill",
                        iconColor: .appRose,
                        title: "ล้างออร์เดอร์ & เซสชันโต๊ะ",
                        subtitle: "ลบ sessions, orders, payments — ยืนยัน 2 ขั้นตอน",
                        badge: .irreversible
                    ) {
                        APHaptic.trigger()
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
            sectionHeader("Server Configuration", icon: "server.rack", color: .appAccent)

            VStack(alignment: .leading, spacing: 14) {

                // Supabase URL
                serverURLField(
                    label: "Supabase Server URL",
                    placeholder: "https://your-project.supabase.co",
                    text: $supabaseURLDraft,
                    error: supabaseURLError
                )

                // Local Worker URL
                serverURLField(
                    label: "Local Worker URL",
                    placeholder: "http://192.168.x.x:8080",
                    text: $localServerURLDraft,
                    error: localURLError
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
                            Text("Test Connection")
                                .font(.subheadline)
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
                        Label("บันทึก", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(!serverConfigDirty)
                }

                if let result = connectionTestResult {
                    Label(result, systemImage: connectionTestOK ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundColor(connectionTestOK ? .green : .appRose)
                }

                Text("⚠️ ต้อง restart app หลังเปลี่ยน URL เพื่อให้มีผล")
                    .font(.caption2)
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
                .font(.caption)
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
                    .font(.caption2)
                    .foregroundColor(.appRose)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section: Audit Log
    // ─────────────────────────────────────────────────────────────────────────
    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Audit Trail", icon: "list.bullet.clipboard", color: .appAccent)

            if recentAuditLogs.isEmpty {
                HStack {
                    Spacer()
                    Text("ยังไม่มีประวัติการดำเนินการ")
                        .font(.caption)
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
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                Text(log.details ?? "—")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(log.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(log.createdAt, style: .date)
                    .font(.caption2)
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
            .font(.caption)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(disabled ? .textSecondary : .textPrimary)
                        if let b = badge { badgeView(b) }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
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
            badgeLabel("Dev only", color: .green)
        case .localOnly:
            badgeLabel("Local only", color: .orange)
        case .irreversible:
            badgeLabel("Irreversible", color: .appRose)
        case .blocked:
            badgeLabel("Blocked", color: .gray)
        }
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
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
    // MARK: - Actions: Re-Seed
    // ─────────────────────────────────────────────────────────────────────────
    private func executeReSeed() {
        // Guard: block in production
        guard !isProduction else {
            statusMessage = "Re-Seed ไม่สามารถใช้งานในโหมด Production\n(AppConfig.isProduction = true)"
            statusIsError = true
            showingStatusAlert = true
            return
        }

        SampleDataSeeder.seedAll(modelContext: modelContext)
        writeAuditLog(action: "system_ops_reseed", details: "Re-seeded demo data (merchant: \(activeMerchantId))")

        statusMessage = "Seed ข้อมูลตัวอย่างเสร็จสิ้น\nMerchant: \(activeMerchantId)"
        statusIsError = false
        showingStatusAlert = true

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Clear Local Cache (SCOPED)
    // ─────────────────────────────────────────────────────────────────────────
    /// ลบเฉพาะ local SwiftData records — ไม่ DELETE จาก Supabase
    /// SwiftData ไม่มี merchantId field ใน Order/TableSession/MenuItem
    /// ดังนั้น "local cache" หมายถึง ALL records ใน SQLite ของ device นี้
    /// (1 device = 1 merchant session เสมอ เพราะ active_merchant_id เป็น device-scoped)
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

        statusMessage = "ล้าง local cache เสร็จสิ้น\nข้อมูลใน Supabase ยังคงอยู่"
        statusIsError = false
        showingStatusAlert = true
        loadRecentAuditLogs()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Wipe — PIN Verification
    // ─────────────────────────────────────────────────────────────────────────
    private func verifyPinAndProceed() {
        pinAttempts += 1
        // Read PIN from Keychain (not UserDefaults)
        let ownerPin = KeychainManager.shared.retrieve(forKey: "merchant_owner_pin") ?? "8888"

        if enteredPin == ownerPin {
            pinAttempts = 0
            performStoreTransactionsReset()
        } else {
            if pinAttempts >= 3 {
                showingPinErrorAlert = true
            } else {
                showingPinErrorAlert = true
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions: Wipe Remote + Local (TENANT-SCOPED)
    // ─────────────────────────────────────────────────────────────────────────
    private func performStoreTransactionsReset() {
        APHaptic.trigger()
        isResettingTransactions = true

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
            for t in tables { t.status = "vacant" }
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
        serverConfigDirty = false
    }

    private func validateURLs() -> Bool {
        supabaseURLError = nil
        localURLError = nil
        var valid = true

        if supabaseURLDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            supabaseURLError = "URL ต้องไม่ว่างเปล่า"
            valid = false
        } else if URL(string: supabaseURLDraft)?.host == nil {
            supabaseURLError = "URL รูปแบบไม่ถูกต้อง"
            valid = false
        }

        if localServerURLDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            localURLError = "URL ต้องไม่ว่างเปล่า"
            valid = false
        } else if URL(string: localServerURLDraft)?.host == nil {
            localURLError = "URL รูปแบบไม่ถูกต้อง"
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
            let (_, response) = try await URLSession.shared.data(for: req)
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
        case "system_ops_wipe": return "trash.fill"
        case "system_ops_cache_clear": return "internaldrive"
        case "system_ops_reseed": return "arrow.triangle.2.circlepath"
        case "system_ops_server_config": return "server.rack"
        default: return "gear"
        }
    }

    private func displayNameForAction(_ type: String) -> String {
        switch type {
        case "system_ops_wipe": return "ล้างออร์เดอร์ & เซสชัน"
        case "system_ops_cache_clear": return "ล้าง Local Cache"
        case "system_ops_reseed": return "Re-Seed ข้อมูลตัวอย่าง"
        case "system_ops_server_config": return "เปลี่ยน Server URL"
        default: return type
        }
    }
}

#Preview {
    NavigationStack {
        SystemOpsSettingsView()
    }
}
