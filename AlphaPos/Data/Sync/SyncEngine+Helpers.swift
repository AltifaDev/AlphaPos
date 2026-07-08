import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Helpers
extension SyncEngine {
    // MARK: - Helpers

    /// Format Date to ISO8601 string for Supabase (reuses shared static formatter)
    func iso8601Format(_ date: Date) -> String {
        return SyncEngine.iso8601WithFractionals.string(from: date)
    }

    func checkForDelayedOrders(modelContext: ModelContext) async {
        // Pre-filter: only fetch orders older than 10 minutes with relevant statuses
        let cutoff = Date().addingTimeInterval(-600)
        var descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> { $0.createdAt < cutoff }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard var orders = try? modelContext.fetch(descriptor) else { return }

        // Sort by createdAt ascending (FIFO)
        orders.sort(by: { $0.createdAt < $1.createdAt })

        let now = Date()

        // Filter orders that are older than 10 minutes (600 seconds) and not yet delivered/served
        let delayedOrders = orders.filter { order in
            let isOlderThan10Min = now.timeIntervalSince(order.createdAt) >= 600
            
            // CRITICAL FIX: If the order belongs to a table session that is already checked out/inactive, ignore it completely
            if let session = order.tableSession, !session.isActive {
                return false
            }
            
            if order.status == "preparing" {
                let hasActiveItems = order.items.contains(where: { $0.status == "cooking" || $0.status == "alert" })
                return hasActiveItems && isOlderThan10Min
            } else if order.status == "ready" {
                return isOlderThan10Min
            }
            return false
        }

        // If there are any delayed orders, get the oldest one (FIFO priority)
        guard let oldestDelayedOrder = delayedOrders.first else { return }

        let orderId = oldestDelayedOrder.id
        let tableNum = oldestDelayedOrder.tableSession?.table?.tableNumber ?? "1"
        let orderNum = String(oldestDelayedOrder.orderNumber.split(separator: "-").last ?? oldestDelayedOrder.orderNumber.suffix(3))

        // Check if we should trigger the alert (either first time, or 10 minutes passed since last alert for this specific order)
        let shouldAlert: Bool
        if let lastAlert = SyncEngine.getAlertTime(orderId) {
            shouldAlert = now.timeIntervalSince(lastAlert) >= 600
        } else {
            shouldAlert = true
        }

        if shouldAlert {
            SyncEngine.setAlertTime(orderId, now)

            // 1. Create a service request on the server to notify AlphaPos and AlphaPosStaff
            let alertType: String
            if oldestDelayedOrder.status == "ready" {
                alertType = "Delivery Alert: Table \(tableNum) (#\(orderNum)) has been ready but not delivered for over 10 minutes!"
            } else {
                alertType = "Cooking Alert: Table \(tableNum) (#\(orderNum)) has had items cooking for more than 10 minutes!"
            }

            _ = try? await NetworkManager.shared.createServiceRequest(tableNumber: tableNum, type: alertType)

            // 2. แจ้งเตือนในแอป (แทนที่ UNUserNotificationCenter)
            let isReady = oldestDelayedOrder.status == "ready"
            InAppNotificationManager.shared.postCookingAlert(
                tableNumber: tableNum,
                orderNumber: orderNum,
                isReady: isReady
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
}

extension Notification.Name {
    static let openTableNotification = Notification.Name("openTableNotification")
}
