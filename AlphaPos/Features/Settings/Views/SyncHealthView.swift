import SwiftUI
import SwiftData
import UIKit

struct SyncHealthView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncEngine = SyncEngine.shared

    @Query private var orders: [Order]
    @Query private var payments: [Payment]
    @Query private var tables: [RestaurantTable]
    @Query private var sessions: [TableSession]
    @Query private var menuItems: [MenuItem]
    @Query private var categories: [Category]
    @Query private var inventoryItems: [InventoryItem]
    @Query private var modifiers: [Modifier]
    @Query private var modifierGroups: [ModifierGroup]
    @Query private var customers: [Customer]
    @Query private var loyaltyTransactions: [LoyaltyTransaction]
    @Query private var giftCards: [GiftCard]
    @Query private var cashMovements: [CashMovement]
    @Query private var refundTransactions: [RefundTransaction]
    @Query(sort: \AuditLog.updatedAt, order: .reverse) private var auditLogs: [AuditLog]

    private let accent = Color(hex: "0F766E")

    private var localizedSyncStatusText: String {
        switch syncEngine.syncStatus {
        case .idle: return L.Sync.statusSynced.t
        case .syncing: return L.Sync.statusSyncing.t
        case .error: return L.Sync.statusError.t
        case .offline: return L.Sync.statusOffline.t
        }
    }

    @State private var isCheckingConnection = false
    @State private var connectionText = "connection_status_unchecked".t
    @State private var isSyncingNow = false

    @State private var isOptimizing = false
    @State private var showingOptimizeAlert = false
    @State private var optimizeAlertMessage = ""

    private struct QueueGroup: Identifiable {
        let id: String
        let name: String
        let pending: Int
        let deleted: Int
        let localTotal: Int
        let cloudKey: String?
        let icon: String
        let color: Color
    }

    private var groups: [QueueGroup] {
        let rawGroups = [
            QueueGroup(
                id: "orders",
                name: L.Sync.queueOrders.t,
                pending: orders.filter { !$0.isSynced }.count,
                deleted: orders.filter(\.isDeleted).count,
                localTotal: orders.count,
                cloudKey: "orders",
                icon: "receipt.fill",
                color: accent
            ),
            QueueGroup(
                id: "payments",
                name: L.Sync.queuePayments.t,
                pending: payments.filter { !$0.isSynced }.count,
                deleted: payments.filter(\.isDeleted).count,
                localTotal: payments.count,
                cloudKey: "payments",
                icon: "creditcard.fill",
                color: .appTeal
            ),
            QueueGroup(
                id: "tables",
                name: L.Sync.queueTables.t,
                pending: tables.filter { !$0.isSynced }.count + sessions.filter { !$0.isSynced }.count,
                deleted: tables.filter(\.isDeleted).count + sessions.filter(\.isDeleted).count,
                localTotal: tables.count,
                cloudKey: "restaurant_tables",
                icon: "tablecells.fill",
                color: Color(hex: "60A5FA")
            ),
            QueueGroup(
                id: "menu",
                name: L.Sync.queueMenu.t,
                pending: menuItems.filter { !$0.isSynced }.count
                    + categories.filter { !$0.isSynced }.count
                    + modifiers.filter { !$0.isSynced }.count
                    + modifierGroups.filter { !$0.isSynced }.count,
                deleted: menuItems.filter(\.isDeleted).count
                    + categories.filter(\.isDeleted).count
                    + modifiers.filter(\.isDeleted).count
                    + modifierGroups.filter(\.isDeleted).count,
                localTotal: menuItems.count,
                cloudKey: "menu_items",
                icon: "fork.knife",
                color: Color(hex: "F59E0B")
            ),
            QueueGroup(
                id: "inventory",
                name: L.Sync.queueInventory.t,
                pending: inventoryItems.filter { !$0.isSynced }.count,
                deleted: inventoryItems.filter(\.isDeleted).count,
                localTotal: inventoryItems.count,
                cloudKey: "inventory_items",
                icon: "shippingbox.fill",
                color: Color(hex: "0EA5E9")
            ),
            QueueGroup(
                id: "customers",
                name: L.Sync.queueCustomers.t,
                pending: customers.filter { !$0.isSynced }.count,
                deleted: customers.filter(\.isDeleted).count,
                localTotal: customers.count,
                cloudKey: "customers",
                icon: "person.2.fill",
                color: Color(hex: "A78BFA")
            ),
            QueueGroup(
                id: "loyalty",
                name: L.Sync.queueLoyalty.t,
                pending: loyaltyTransactions.filter { !$0.isSynced }.count
                    + giftCards.filter { !$0.isSynced }.count,
                deleted: loyaltyTransactions.filter(\.isDeleted).count
                    + giftCards.filter(\.isDeleted).count,
                localTotal: loyaltyTransactions.count + giftCards.count,
                cloudKey: "loyalty_transactions",
                icon: "star.circle.fill",
                color: Color(hex: "F59E0B")
            ),
            QueueGroup(
                id: "financial",
                name: L.Sync.queueFinancial.t,
                pending: cashMovements.filter { !$0.isSynced }.count
                    + refundTransactions.filter { !$0.isSynced }.count,
                deleted: cashMovements.filter(\.isDeleted).count
                    + refundTransactions.filter(\.isDeleted).count,
                localTotal: cashMovements.count + refundTransactions.count,
                cloudKey: "cash_movements",
                icon: "banknote.fill",
                color: .appRose
            )
        ]
        guard NetworkPolicy.shared.mode == .offlineOnly else { return rawGroups }
        return rawGroups.map {
            QueueGroup(
                id: $0.id, name: $0.name, pending: 0, deleted: $0.deleted,
                localTotal: $0.localTotal, cloudKey: $0.cloudKey,
                icon: $0.icon, color: $0.color
            )
        }
    }

    private var totalPending: Int {
        groups.reduce(0) { $0 + $1.pending }
    }

    private var isConnectionOnline: Bool {
        connectionText == L.Sync.connOnline.t
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: APSpacing.lg) {
                    summaryRow
                    hubOutboxCard
                    deviceQueueSection
                    conflictResolutionLink
                    cacheOptimizationCard
                    auditSection
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.top, 0)
                .padding(.bottom, APSpacing.lg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(L.Sync.title.t)
        .toolbar(.visible, for: .navigationBar)
        .apNavBar(background: Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                workspaceHeader
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runSyncNow() }
                } label: {
                    Label(
                        isSyncingNow ? L.Sync.statusSyncing.t : L.Sync.syncNowBtn.t,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(isSyncingNow)
            }
        }
        .task {
            await refreshAll(pullAudits: true)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await refreshAll(pullAudits: false)
            }
        }
        .alert("sync_optimize_alert_title".t, isPresented: $showingOptimizeAlert) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text(optimizeAlertMessage)
        }
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        Button {
            Task { await refreshAll(pullAudits: true) }
        } label: {
            Image(systemName: (isCheckingConnection || syncEngine.isRefreshingOnlineHealth) ? "hourglass" : "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isCheckingConnection || syncEngine.isRefreshingOnlineHealth)
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack(spacing: APSpacing.md) {
                statusCard(
                    title: L.Sync.summaryStatus.t,
                    value: localizedSyncStatusText,
                    icon: syncIcon,
                    color: syncColor
                )
                statusCard(
                    title: "sync_device_queue".t,
                    value: "\(totalPending)",
                    icon: totalPending == 0 ? "checkmark.circle.fill" : "tray.full.fill",
                    color: totalPending == 0 ? accent : Color(hex: "F59E0B")
                )
                statusCard(
                    title: L.Sync.connection.t,
                    value: connectionText,
                    icon: isConnectionOnline ? "wifi" : "wifi.slash",
                    color: isConnectionOnline ? accent : .appRose
                )
                statusCard(
                    title: L.Sync.lastSynced.t,
                    value: syncEngine.lastSyncedAt?.formatted(date: .omitted, time: .standard) ?? "never".t,
                    icon: "clock.fill",
                    color: accent
                )
            }

            if syncEngine.syncStatus == .error
                || syncEngine.hadSoftSyncFailures
                || !syncEngine.lastSyncFailureDetails.isEmpty {
                SyncFailureBanner(
                    isCritical: syncEngine.syncStatus == .error,
                    rawLines: syncEngine.lastSyncFailureDetails.isEmpty
                        ? [syncEngine.lastSyncErrorSummary].compactMap { $0 }
                        : syncEngine.lastSyncFailureDetails,
                    accent: accent
                )
            }
        }
    }

    private var hubOutboxCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundColor(accent)
                Text("sync_hub_outbox".t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if syncEngine.isRefreshingOnlineHealth {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = syncEngine.hubHealthError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.appRose)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sync_hub_unavailable".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appRose.opacity(0.08))
                .cornerRadius(10)
            }

            HStack(spacing: APSpacing.lg) {
                statusCard(
                    title: "sync_pending_label".t,
                    value: "\(syncEngine.hubPending)",
                    icon: "tray.full.fill",
                    color: syncEngine.hubPending == 0 ? accent : Color(hex: "F59E0B")
                )
                statusCard(
                    title: "sync_failed_label".t,
                    value: "\(syncEngine.hubFailed)",
                    icon: "exclamationmark.triangle.fill",
                    color: syncEngine.hubFailed == 0 ? accent : .appRose
                )
                statusCard(
                    title: "sync_processing_label".t,
                    value: "\(syncEngine.hubProcessing)",
                    icon: "arrow.triangle.2.circlepath",
                    color: syncEngine.hubProcessing == 0 ? .textTertiary : .appAccent
                )
                statusCard(
                    title: "sync_oldest_label".t,
                    value: syncEngine.hubOldestLabel,
                    icon: "clock.fill",
                    color: accent
                )
            }

            if !syncEngine.hubByJobType.isEmpty {
                FlowJobTypeChips(items: syncEngine.hubByJobType, accent: accent)
            }

            Text("sync_hub_outbox_desc".t)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .padding()
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var deviceQueueSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("sync_device_queue_title".t)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: APSpacing.md)], spacing: APSpacing.md) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: APSpacing.md) {
                        HStack {
                            Image(systemName: group.icon)
                                .foregroundColor(group.color)
                            Text(group.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if let key = group.cloudKey, let cloud = syncEngine.cloudEntityCounts[key] {
                                Label("\(cloud)", systemImage: "icloud.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(accent.opacity(0.10))
                                    .clipShape(Capsule())
                                    .accessibilityLabel("sync_cloud_total".t + " \(cloud)")
                            }
                        }

                        HStack {
                            metricColumn(
                                value: "\(group.pending)",
                                label: L.Sync.pendingLabel.t,
                                color: group.pending == 0 ? accent : Color(hex: "F59E0B")
                            )
                            Spacer()
                            metricColumn(
                                value: "\(group.localTotal)",
                                label: "sync_local_total".t,
                                color: .textPrimary
                            )
                            Spacer()
                            metricColumn(
                                value: "\(group.deleted)",
                                label: L.Sync.deletedLabel.t,
                                color: group.deleted == 0 ? .textTertiary : .appRose
                            )
                        }
                    }
                    .apCard()
                }
            }
        }
    }

    private func metricColumn(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
    }

    private var conflictResolutionLink: some View {
        NavigationLink(destination: SyncConflictView()) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "F59E0B").opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "F59E0B"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("conflict_nav_title".t)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("conflict_nav_desc".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "F59E0B").opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Sync.recentActivity.t)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)
            if auditLogs.isEmpty {
                Text(L.Sync.noRecentActivity.t)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.appSurface)
                    .cornerRadius(8)
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach(auditLogs.prefix(12)) { log in
                        HStack(spacing: APSpacing.md) {
                            Image(systemName: "list.clipboard.fill")
                                .foregroundColor(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.actionType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(log.details ?? "-")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(log.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 140)
        .background(Color.appSurfaceHigh)
        .cornerRadius(8)
    }

    private var syncIcon: String {
        switch syncEngine.syncStatus {
        case .idle: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    private var syncColor: Color {
        switch syncEngine.syncStatus {
        case .idle: return accent
        case .syncing: return .appAccent
        case .error: return .appRose
        case .offline: return Color(hex: "9CA3AF")
        }
    }

    // MARK: - Actions

    private func refreshAll(pullAudits: Bool) async {
        await checkConnection()
        if pullAudits {
            await SyncEngine.shared.pullAuditLogs(modelContext, limit: 40)
        }
        await syncEngine.refreshOnlineSyncHealth()
    }

    private func checkConnection() async {
        isCheckingConnection = true
        NetworkManager.shared.invalidateConnectivityCache()
        let online = await NetworkManager.shared.isConnected()
        connectionText = online ? L.Sync.connOnline.t : L.Sync.connOffline.t
        isCheckingConnection = false
    }

    private func runSyncNow() async {
        isSyncingNow = true
        await SyncEngine.shared.syncAll(modelContext: modelContext)
        await refreshAll(pullAudits: true)
        isSyncingNow = false
    }

    private var cacheOptimizationCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(accent)
                Text("sync_optimize_title".t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            Text("sync_optimize_desc".t)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            Button {
                isOptimizing = true
                Task {
                    let (_, msg) = await syncEngine.optimizeDatabase(modelContext: modelContext)
                    optimizeAlertMessage = msg
                    isOptimizing = false
                    showingOptimizeAlert = true
                }
            } label: {
                HStack {
                    if isOptimizing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text("sync_optimize_cta".t)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accent)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isOptimizing)
        }
        .padding()
        .background(Color.appSurfaceHigh)
        .cornerRadius(APRadius.md)
    }
}

// MARK: - Job type chips

private struct FlowJobTypeChips: View {
    let items: [(type: String, count: Int)]
    let accent: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("\(item.type) · \(item.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Progressive disclosure banner (admin-friendly + expandable tech log)

private struct SyncFailureBanner: View {
    let isCritical: Bool
    let rawLines: [String]
    let accent: Color

    @State private var isExpanded = false
    @State private var copied = false

    private var presentation: SyncFailureClassifier.Presentation {
        SyncFailureClassifier.present(rawLines: rawLines, isCritical: isCritical)
    }

    private var tone: Color {
        isCritical ? Color.appRose : Color(hex: "F59E0B")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tone)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.headline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text(presentation.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(presentation.issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.kind.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(tone)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(issue.body)
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(accent)
                        Text(presentation.action)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("sync_tech_details_hint".t)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)

                    ForEach(Array(presentation.technicalLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if presentation.technicalLog.isEmpty {
                        Text("sync_tech_details_empty".t)
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                    }

                    Button {
                        let payload = presentation.technicalLog.joined(separator: "\n")
                        UIPasteboard.general.string = payload
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Label(
                            copied ? "sync_tech_copied".t : "sync_tech_copy".t,
                            systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(presentation.technicalLog.isEmpty)
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text(isExpanded ? "sync_tech_hide".t : "sync_tech_show".t)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("sync_tech_for_support".t)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tone.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}
