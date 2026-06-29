import SwiftUI
import SwiftData

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

    private struct QueueGroup: Identifiable {
        let id = UUID()
        let name: String
        let pending: Int
        let deleted: Int
        let icon: String
        let color: Color
    }

    private var groups: [QueueGroup] {
        [
            QueueGroup(name: L.Sync.queueOrders.t, pending: pending(orders), deleted: deleted(orders), icon: "receipt.fill", color: .appAccent),
            QueueGroup(name: L.Sync.queuePayments.t, pending: pending(payments), deleted: deleted(payments), icon: "creditcard.fill", color: .appTeal),
            QueueGroup(name: L.Sync.queueTables.t, pending: pending(tables) + pending(sessions), deleted: deleted(tables) + deleted(sessions), icon: "tablecells.fill", color: Color(hex: "60A5FA")),
            QueueGroup(name: L.Sync.queueMenu.t, pending: pending(menuItems) + pending(categories) + pending(modifiers) + pending(modifierGroups), deleted: deleted(menuItems) + deleted(categories) + deleted(modifiers) + deleted(modifierGroups), icon: "fork.knife", color: Color(hex: "F59E0B")),
            QueueGroup(name: L.Sync.queueInventory.t, pending: pending(inventoryItems), deleted: deleted(inventoryItems), icon: "shippingbox.fill", color: Color(hex: "0EA5E9")),
            QueueGroup(name: L.Sync.queueCustomers.t, pending: pending(customers), deleted: deleted(customers), icon: "person.2.fill", color: Color(hex: "A78BFA")),
            QueueGroup(name: L.Sync.queueLoyalty.t, pending: pending(loyaltyTransactions) + pending(giftCards), deleted: deleted(loyaltyTransactions) + deleted(giftCards), icon: "star.circle.fill", color: Color(hex: "F59E0B")),
            QueueGroup(name: L.Sync.queueFinancial.t, pending: pending(cashMovements) + pending(refundTransactions), deleted: deleted(cashMovements) + deleted(refundTransactions), icon: "banknote.fill", color: .appRose)
        ]
    }

    private var totalPending: Int {
        groups.reduce(0) { $0 + $1.pending }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: APSpacing.lg) {
                    summaryRow
                    queueGrid
                    conflictResolutionLink
                    auditSection
                }
                .padding(APSpacing.lg)
            }
        }
        .navigationTitle(L.Sync.title.t)
        .apNavBar(background: Color.appBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runSyncNow() }
                } label: {
                    Label(isSyncingNow ? L.Sync.statusSyncing.t : L.Sync.syncNowBtn.t, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncingNow)
            }
        }
        .task {
            await checkConnection()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: APSpacing.md) {
            statusCard(title: L.Sync.summaryStatus.t, value: localizedSyncStatusText, icon: syncIcon, color: syncColor)
            statusCard(title: L.Sync.pendingQueue.t, value: "\(totalPending)", icon: totalPending == 0 ? "checkmark.circle.fill" : "tray.full.fill", color: totalPending == 0 ? .appTeal : Color(hex: "F59E0B"))
            statusCard(title: L.Sync.connection.t, value: connectionText, icon: "wifi", color: connectionText == "Online" ? .appTeal : .appRose)
            statusCard(title: L.Sync.lastSynced.t, value: syncEngine.lastSyncedAt?.formatted(date: .omitted, time: .standard) ?? "never".t, icon: "clock.fill", color: .appAccent)

            Button {
                Task { await checkConnection() }
            } label: {
                Image(systemName: isCheckingConnection ? "hourglass" : "arrow.clockwise")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(isCheckingConnection)
        }
    }

    private var queueGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: APSpacing.md)], spacing: APSpacing.md) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: APSpacing.md) {
                    HStack {
                        Image(systemName: group.icon)
                            .foregroundColor(group.color)
                        Text(group.name)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(group.pending)")
                                .font(.title.weight(.bold))
                                .foregroundColor(group.pending == 0 ? .appTeal : Color(hex: "F59E0B"))
                            Text(L.Sync.pendingLabel.t)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(group.deleted)")
                                .font(.headline.weight(.bold))
                                .foregroundColor(group.deleted == 0 ? .textTertiary : .appRose)
                            Text(L.Sync.deletedLabel.t)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .apCard()
            }
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "F59E0B"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("conflict_nav_title".t)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("conflict_nav_desc".t)
                        .font(.system(size: 11))
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
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
            if auditLogs.isEmpty {
                Text(L.Sync.noRecentActivity.t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.appSurface)
                    .cornerRadius(8)
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach(auditLogs.prefix(10)) { log in
                        HStack(spacing: APSpacing.md) {
                            Image(systemName: "list.clipboard.fill")
                                .foregroundColor(.appAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.actionType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.textPrimary)
                                Text(log.details ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(log.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
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
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 160)
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
        case .idle: return .appTeal
        case .syncing: return .appAccent
        case .error: return .appRose
        case .offline: return Color(hex: "9CA3AF")
        }
    }

    private func checkConnection() async {
        isCheckingConnection = true
        NetworkManager.shared.invalidateConnectivityCache()
        connectionText = await NetworkManager.shared.isConnected() ? L.Sync.connOnline.t : L.Sync.connOffline.t
        isCheckingConnection = false
    }

    private func runSyncNow() async {
        isSyncingNow = true
        await SyncEngine.shared.syncAll(modelContext: modelContext)
        await checkConnection()
        isSyncingNow = false
    }

    private func pending<T>(_ values: [T]) -> Int where T: AnyObject {
        values.filter { value in
            (Mirror(reflecting: value).children.first { $0.label == "isSynced" }?.value as? Bool) == false
        }.count
    }

    private func deleted<T>(_ values: [T]) -> Int where T: AnyObject {
        values.filter { value in
            (Mirror(reflecting: value).children.first { $0.label == "isDeleted" }?.value as? Bool) == true
        }.count
    }
}
