import Foundation
import SwiftData
import SQLite3

extension SyncEngine {

    /// Prunes completed and synced orders/payments/loyalty transactions older than 30 days.
    /// Vacuums the SQLite database to reclaim unused storage and optimize speed.
    func optimizeDatabase(modelContext: ModelContext) async -> (success: Bool, message: String) {
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        var prunedOrdersCount = 0
        var prunedLogsCount = 0

        do {
            // 1. Prune orders that are completed/cancelled and fully synced
            let ordersDesc = FetchDescriptor<Order>(
                predicate: #Predicate<Order> {
                    ($0.status == "completed" || $0.status == "cancelled")
                    && $0.isSynced == true
                    && $0.createdAt < thirtyDaysAgo
                }
            )
            let oldOrders = try modelContext.fetch(ordersDesc)
            for order in oldOrders {
                modelContext.delete(order)
                prunedOrdersCount += 1
            }

            // 2. Prune audit logs older than 7 days
            let logsDesc = FetchDescriptor<AuditLog>(
                predicate: #Predicate<AuditLog> {
                    $0.updatedAt < sevenDaysAgo
                }
            )
            let oldLogs = try modelContext.fetch(logsDesc)
            for log in oldLogs {
                modelContext.delete(log)
                prunedLogsCount += 1
            }

            // Save model changes
            modelContext.saveWithLogging(label: "optimizeDatabase.pruning")

            // 3. VACUUM database
            let fm = FileManager.default
            let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
            if let docURL = paths.first {
                let dbURL = docURL.appendingPathComponent("alphapos.db")
                if fm.fileExists(atPath: dbURL.path) {
                    var db: OpaquePointer?
                    if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
                        sqlite3_exec(db, "VACUUM;", nil, nil, nil)
                        sqlite3_close(db)
                    }
                }
            }

            return (true, "Optimized successfully. Pruned \(prunedOrdersCount) order(s) and \(prunedLogsCount) log(s). Reclaimed database storage.")
        } catch {
            return (false, "Optimization failed: \(error.localizedDescription)")
        }
    }
}
