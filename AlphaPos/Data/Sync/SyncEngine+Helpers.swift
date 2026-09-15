import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Helpers
extension SyncEngine {
    // MARK: - Helpers

    /// Alerts derived from local business state. These remain available in the
    /// offline package; only propagation to other devices requires the server.
    func runLocalOperationalChecks(modelContext: ModelContext) async {
        // Local accounting is part of the POS transaction boundary, not a cloud
        // feature. Reconcile idempotently on every operational bootstrap so an
        // offline-only store and legacy rows both have a complete ledger.
        await backfillBusinessContext(modelContext)
        await backfillAccountingLedger(modelContext)

        var descriptor = FetchDescriptor<RegisterSession>(
            predicate: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted }
        )
        descriptor.fetchLimit = 500
        let activeShifts = (try? modelContext.fetch(descriptor)) ?? []
        if let activeShift = activeShifts.first {
            let hoursOpen = Calendar.current.dateComponents(
                [.hour],
                from: activeShift.openedAt,
                to: Date()
            ).hour ?? 0
            if hoursOpen >= 24 {
                triggerStaleShiftNotification(shiftId: activeShift.id, hoursOpen: hoursOpen)
            }
        }

        let activeKeys = Set(activeShifts.map { "stale-shift-\($0.id.uuidString.lowercased())" })
        NotificationStore.shared.resolveStaleShiftConditions(except: activeKeys)

        refreshLiveOperationalAlerts(
            modelContext: modelContext,
            includeCloudRequests: !UserDefaults.standard.bool(forKey: "offline_sync_mode")
        )
        notifyReadyOrders(modelContext)
        await checkForDelayedOrders(modelContext: modelContext)
    }

    /// Format Date to ISO8601 string for Supabase (reuses shared static formatter)
    func iso8601Format(_ date: Date) -> String {
        return SyncEngine.iso8601WithFractionals.string(from: date)
    }

    func checkForDelayedOrders(modelContext: ModelContext) async {
        // Pre-filter old cooking orders; ready orders are timed from readyAt below.
        let cutoff = Date().addingTimeInterval(-600)
        var descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> {
                !$0.isDeleted && (
                    $0.status == "preparing" ||
                    $0.status == "cooking" ||
                    $0.status == "ready"
                )
            }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard var orders = try? modelContext.fetch(descriptor) else { return }

        // Sort by createdAt ascending (FIFO)
        orders.sort(by: { $0.createdAt < $1.createdAt })

        let now = Date()

        // Only table-backed orders can create this table-specific alert.
        let delayedOrders = orders.filter { order in
            guard order.activeTableNumber != nil else { return false }
            let status = order.status.lowercased()
            if status == "preparing" || status == "cooking" {
                let hasActiveItems = order.items.contains(where: { $0.status == "cooking" || $0.status == "alert" })
                return hasActiveItems && order.createdAt < cutoff
            } else if status == "ready" {
                guard order.isOperationalReadyOrder, let readyAt = order.readyAt else { return false }
                return now.timeIntervalSince(readyAt) >= 600
            }
            return false
        }

        // Evaluate every delayed order independently. Selecting only the oldest
        // caused its cooldown to starve every other delayed ticket.
        for delayedOrder in delayedOrders {
            let orderId = delayedOrder.id
            guard let tableNum = delayedOrder.activeTableNumber else { continue }
            let orderNum = String(
                delayedOrder.orderNumber.split(separator: "-").last
                    ?? delayedOrder.orderNumber.suffix(3)
            )
            let shouldAlert = NotificationDeliveryPolicy.shouldDeliverRepeatedAlert(
                lastDeliveredAt: SyncEngine.getAlertTime(orderId),
                now: now
            )
            guard shouldAlert else { continue }

            SyncEngine.setAlertTime(orderId, now)

            // Kitchen-delay events stay in the notification pipeline. They are
            // not encoded as customer service requests, which previously
            // duplicated and misclassified them when pulled back from Supabase.
            InAppNotificationManager.shared.postCookingAlert(
                tableNumber: tableNum,
                orderNumber: orderNum,
                isReady: delayedOrder.status.lowercased() == "ready"
            )
        }
    }

    /// Syncs unsynced Printers to Supabase
    func syncPrinters(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Printer>(
            predicate: #Predicate<Printer> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let printers = try? modelContext.fetch(descriptor), !printers.isEmpty else { return }

        for printer in printers {
            do {
                if printer.isDeleted {
                    _ = try await NetworkManager.shared.deletePrinterOnServer(id: printer.id)
                    modelContext.delete(printer)
                } else {
                    let success = try await NetworkManager.shared.uploadPrinter(printer)
                    if success {
                        printer.isSynced = true
                    }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Printer Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncPrinterPreferences() async {
        guard UserDefaults.standard.bool(forKey: "printer_preferences_dirty") else { return }
        do {
            if try await NetworkManager.shared.uploadPrinterPreferences() {
                UserDefaults.standard.set(false, forKey: "printer_preferences_dirty")
            }
        } catch {
            reportSyncFailure("Printer preferences push: \(error.localizedDescription)", soft: true)
        }
    }

    /// Syncs unsynced PrintRoutingRules to Supabase
    func syncPrintRoutingRules(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<PrintRoutingRule>(
            predicate: #Predicate<PrintRoutingRule> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let rules = try? modelContext.fetch(descriptor), !rules.isEmpty else { return }

        for rule in rules {
            do {
                if rule.isDeleted {
                    _ = try await NetworkManager.shared.deletePrintRoutingRuleOnServer(id: rule.id)
                    modelContext.delete(rule)
                } else {
                    let success = try await NetworkManager.shared.uploadPrintRoutingRule(rule)
                    if success {
                        rule.isSynced = true
                    }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [PrintRoutingRule Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullPrinterSettingsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remotePrinters = try await NetworkManager.shared.fetchPrintersFromSupabase()
            let locals = (try? modelContext.fetch(FetchDescriptor<Printer>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id, $0) })

            for remote in remotePrinters {
                guard let rawId = remote["id"] as? String,
                      let id = UUID(uuidString: rawId) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isRemoteDeleted = remoteBool(remote["is_deleted"])

                if let local = localById[id] {
                    // Never resurrect a printer that was marked deleted locally
                    if local.isDeleted {
                        if isRemoteDeleted {
                            modelContext.delete(local)
                        }
                        continue
                    }
                    if isRemoteDeleted {
                        modelContext.delete(local)
                        continue
                    }

                    guard shouldApplyRemoteUpdate(
                        localIsSynced: local.isSynced,
                        localUpdatedAt: local.updatedAt,
                        remoteUpdatedAt: updatedAt
                    ) == .applyRemote else { continue }
                    local.name = remote["name"] as? String ?? local.name
                    local.connectionType = remote["connection_type"] as? String ?? local.connectionType
                    local.ipAddress = remote["ip_address"] as? String
                    local.port = remoteInt(remote["port"], fallback: 9100)
                    local.bluetoothName = remote["bluetooth_name"] as? String
                    local.paperWidth = remote["paper_width"] as? String ?? local.paperWidth
                    local.status = remote["status"] as? String ?? local.status
                    local.role = remote["role"] as? String ?? local.role
                    local.isActive = remoteBool(remote["is_active"], fallback: true)
                    local.emulation = remote["emulation"] as? String ?? "escpos"
                    local.isDeleted = false
                    local.isSynced = true
                    local.updatedAt = updatedAt
                } else if !isRemoteDeleted {
                    let printer = Printer(
                        id: id,
                        name: remote["name"] as? String ?? "Printer",
                        connectionType: remote["connection_type"] as? String ?? "network",
                        ipAddress: remote["ip_address"] as? String,
                        port: remoteInt(remote["port"], fallback: 9100),
                        bluetoothName: remote["bluetooth_name"] as? String,
                        paperWidth: remote["paper_width"] as? String ?? "80mm",
                        status: remote["status"] as? String ?? "unknown",
                        role: remote["role"] as? String ?? "receipt",
                        isActive: remoteBool(remote["is_active"], fallback: true),
                        emulation: remote["emulation"] as? String ?? "escpos",
                        isSynced: true,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(printer)
                    localById[id] = printer
                }
            }

            let remoteRules = try await NetworkManager.shared.fetchPrintRoutingRulesFromSupabase()
            let rules = (try? modelContext.fetch(FetchDescriptor<PrintRoutingRule>())) ?? []
            var ruleById = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
            for remote in remoteRules {
                guard let rawId = remote["id"] as? String,
                      let id = UUID(uuidString: rawId),
                      let rawPrinterId = remote["printer_id"] as? String,
                      let printerId = UUID(uuidString: rawPrinterId) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isRemoteDeleted = remoteBool(remote["is_deleted"])

                if let local = ruleById[id] {
                    // Never resurrect a routing rule that was marked deleted locally
                    if local.isDeleted {
                        if isRemoteDeleted {
                            modelContext.delete(local)
                        }
                        continue
                    }
                    if isRemoteDeleted {
                        modelContext.delete(local)
                        continue
                    }

                    guard shouldApplyRemoteUpdate(
                        localIsSynced: local.isSynced,
                        localUpdatedAt: local.updatedAt,
                        remoteUpdatedAt: updatedAt
                    ) == .applyRemote else { continue }
                    local.printer = localById[printerId]
                    local.categoryId = remote["category_id"] as? String
                    local.printOnOrder = remoteBool(remote["print_on_order"], fallback: true)
                    local.printOnPayment = remoteBool(remote["print_on_payment"])
                    local.isDeleted = false
                    local.isSynced = true
                    local.updatedAt = updatedAt
                } else if !isRemoteDeleted, let printer = localById[printerId] {
                    let rule = PrintRoutingRule(
                        id: id,
                        printer: printer,
                        categoryId: remote["category_id"] as? String,
                        printOnOrder: remoteBool(remote["print_on_order"], fallback: true),
                        printOnPayment: remoteBool(remote["print_on_payment"]),
                        isSynced: true,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(rule)
                    ruleById[id] = rule
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            reportSyncFailure("Printer settings pull: \(error.localizedDescription)", soft: true)
        }
    }
}

extension SyncEngine {
    /// Decision for applying a remote pull onto a local SwiftData row.
    enum RemoteApplyDecision {
        case applyRemote
        case keepLocal
        case enqueueManual
    }

    /// Wires `conflict_strategy` AppStorage into pull reconciliation.
    /// - master_wins: never overwrite unsynced local edits
    /// - server_wins: always take remote when newer or when local is synced
    /// - newest_wins: compare timestamps only
    /// - manual: keep local unsynced edits and flag for review
    func shouldApplyRemoteUpdate(
        localIsSynced: Bool,
        localUpdatedAt: Date,
        remoteUpdatedAt: Date,
        source: String = #fileID
    ) -> RemoteApplyDecision {
        let strategy = UserDefaults.standard.string(forKey: "conflict_strategy") ?? "master_wins"
        let decision: RemoteApplyDecision
        switch strategy {
        case "server_wins":
            decision = remoteUpdatedAt >= localUpdatedAt || localIsSynced ? .applyRemote : .keepLocal
        case "newest_wins":
            decision = remoteUpdatedAt > localUpdatedAt ? .applyRemote : .keepLocal
        case "manual":
            if !localIsSynced && remoteUpdatedAt > localUpdatedAt {
                decision = .enqueueManual
            } else {
                decision = localIsSynced && remoteUpdatedAt > localUpdatedAt ? .applyRemote : .keepLocal
            }
        default: // master_wins
            decision = !localIsSynced ? .keepLocal : (remoteUpdatedAt > localUpdatedAt ? .applyRemote : .keepLocal)
        }

        // A conflict exists only when an unsynced local mutation meets a
        // different remote revision. Normal pulls are intentionally not logged.
        if !localIsSynced && remoteUpdatedAt != localUpdatedAt {
            let label: String
            switch decision {
            case .applyRemote: label = "remote_applied"
            case .keepLocal: label = "local_kept"
            case .enqueueManual: label = "manual_pending"
            }
            SyncConflictJournal.shared.record(
                source: source, strategy: strategy, decision: label,
                baseAt: lastSyncedAt, localAt: localUpdatedAt, remoteAt: remoteUpdatedAt
            )
        }
        return decision
    }
}

extension Notification.Name {
    static let openTableNotification = Notification.Name("openTableNotification")
    static let openOrderNotification = Notification.Name("openOrderNotification")
    static let openInventoryItemNotification = Notification.Name("openInventoryItemNotification")
    /// Switch main sidebar to Payments hub (enterprise single place for tender config).
    static let openPaymentsNotification = Notification.Name("openPaymentsNotification")
    /// Deep-link: open Menus → Catalog and present First Product Guide.
    static let openFirstProductGuideNotification = Notification.Name("openFirstProductGuideNotification")
    /// Deep-link: open Tables and present Add Table sheet.
    static let openAddFirstTableNotification = Notification.Name("openAddFirstTableNotification")
    /// Switch main sidebar to POS (Orders) tab.
    static let openPOSTabNotification = Notification.Name("openPOSTabNotification")
    /// Re-show store setup checklist banner on Dashboard.
    static let reopenStoreSetupChecklistNotification = Notification.Name("reopenStoreSetupChecklistNotification")
}
