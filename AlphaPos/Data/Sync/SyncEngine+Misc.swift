import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Miscellaneous Sync (ShiftReport, OrderItemModifier, PromotionBundleItem)
// These models link to other entities and complete the sync coverage.
extension SyncEngine {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - ShiftReport
    // ──────────────────────────────────────────────────────────────────────

    func syncShiftReports(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<ShiftReport>(
            predicate: #Predicate<ShiftReport> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let reports = try? modelContext.fetch(descriptor), !reports.isEmpty else { return }

        for report in reports {
            do {
                if report.isDeleted {
                    if try await NetworkManager.shared.deleteShiftReportOnServer(id: report.id) {
                        modelContext.delete(report)
                    }
                } else if try await NetworkManager.shared.uploadShiftReport(report) {
                    report.isSynced = true
                    report.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [ShiftReport Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullShiftReportsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteReports = try await NetworkManager.shared.fetchShiftReportsFromSupabase()
            guard !remoteReports.isEmpty else { return }

            var __desclocals = FetchDescriptor<ShiftReport>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            // Pre-fetch register sessions and employees
            let allSessions = (try? modelContext.fetch(FetchDescriptor<RegisterSession>())) ?? []
            let sessionMap = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id.uuidString.lowercased(), $0) })
            let allEmployees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
            let employeeMap = Dictionary(uniqueKeysWithValues: allEmployees.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteReports {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeletedRemote {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    if local.isDeleted { continue }
                    if let sid = remote["register_session_id"] as? String { local.registerSession = sessionMap[sid.lowercased()] }
                    local.reportType = remote["report_type"] as? String ?? local.reportType
                    local.grossSales = remoteDouble(remote["gross_sales"])
                    local.netSales = remoteDouble(remote["net_sales"])
                    local.totalTax = remoteDouble(remote["total_tax"])
                    local.totalDiscounts = remoteDouble(remote["total_discounts"])
                    local.totalRefunds = remoteDouble(remote["total_refunds"])
                    local.cashExpected = remoteDouble(remote["cash_expected"])
                    local.cashActual = remoteDouble(remote["cash_actual"])
                    local.overShort = remoteDouble(remote["over_short"])
                    if let eid = remote["generated_by_employee_id"] as? String { local.generatedByEmployee = employeeMap[eid.lowercased()] }
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeletedRemote { continue }
                    var session: RegisterSession? = nil
                    if let sid = remote["register_session_id"] as? String { session = sessionMap[sid.lowercased()] }
                    var employee: Employee? = nil
                    if let eid = remote["generated_by_employee_id"] as? String { employee = employeeMap[eid.lowercased()] }

                    let report = ShiftReport(
                        id: id,
                        registerSession: session,
                        reportType: remote["report_type"] as? String ?? "Z",
                        grossSales: remoteDouble(remote["gross_sales"]),
                        netSales: remoteDouble(remote["net_sales"]),
                        totalTax: remoteDouble(remote["total_tax"]),
                        totalDiscounts: remoteDouble(remote["total_discounts"]),
                        totalRefunds: remoteDouble(remote["total_refunds"]),
                        cashExpected: remoteDouble(remote["cash_expected"]),
                        cashActual: remoteDouble(remote["cash_actual"]),
                        overShort: remoteDouble(remote["over_short"]),
                        generatedByEmployee: employee,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(report)
                    localById[idStr.lowercased()] = report
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [ShiftReport Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - OrderItemModifier
    // ──────────────────────────────────────────────────────────────────────

    func syncOrderItemModifiers(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<OrderItemModifier>(
            predicate: #Predicate<OrderItemModifier> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let oims = try? modelContext.fetch(descriptor), !oims.isEmpty else { return }

        for oim in oims {
            do {
                if oim.isDeleted {
                    if try await NetworkManager.shared.deleteOrderItemModifierOnServer(id: oim.id) {
                        modelContext.delete(oim)
                    }
                } else if try await NetworkManager.shared.uploadOrderItemModifier(oim) {
                    oim.isSynced = true
                    oim.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [OrderItemModifier Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullOrderItemModifiersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteOims = try await NetworkManager.shared.fetchOrderItemModifiersFromSupabase()
            guard !remoteOims.isEmpty else { return }

            var __desclocals = FetchDescriptor<OrderItemModifier>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteOims {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])

                var orderItem: OrderItem? = nil
                if let oiid = remote["order_item_id"] as? String, let oiUUID = UUID(uuidString: oiid) {
                    orderItem = (try? modelContext.fetch(FetchDescriptor<OrderItem>(predicate: #Predicate<OrderItem> { $0.id == oiUUID })))?.first
                }
                var modifier: Modifier? = nil
                if let mid = remote["modifier_id"] as? String, let mUUID = UUID(uuidString: mid) {
                    modifier = (try? modelContext.fetch(FetchDescriptor<Modifier>(predicate: #Predicate<Modifier> { $0.id == mUUID })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeletedRemote {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    if local.isDeleted { continue }
                    local.orderItem = orderItem
                    local.modifier = modifier
                    local.price = remoteDouble(remote["price"])
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeletedRemote { continue }
                    let oim = OrderItemModifier(
                        id: id,
                        orderItem: orderItem,
                        modifier: modifier,
                        price: remoteDouble(remote["price"]),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(oim)
                    localById[idStr.lowercased()] = oim
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [OrderItemModifier Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - PromotionBundleItem
    // ──────────────────────────────────────────────────────────────────────

    func syncPromotionBundleItems(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<PromotionBundleItem>(
            predicate: #Predicate<PromotionBundleItem> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            do {
                // PromotionBundleItems are typically uploaded as part of the Promotion sync,
                // but standalone sync ensures orphan items are also covered.
                if item.isDeleted {
                    let idStr = item.id.uuidString.lowercased()
                    let softDeletePayload: [String: Any] = [
                        "is_deleted": true,
                        "updated_at": NetworkManager.iso8601.string(from: Date())
                    ]
                    _ = try await NetworkManager.shared.sendSupabaseRequest(
                        method: "PATCH",
                        endpoint: "promotion_bundle_items",
                        queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                        payload: softDeletePayload
                    )
                    modelContext.delete(item)
                } else {
                    // Use the existing bulk upload through promotion if available
                    if let promotion = item.promotion {
                        _ = try await NetworkManager.shared.uploadPromotionBundleItems(for: promotion)
                    }
                    item.isSynced = true
                    item.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [PromotionBundleItem Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullPromotionBundleItemsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchPromotionBundleItemsFromSupabase()
            guard !remoteItems.isEmpty else { return }

            var __desclocals = FetchDescriptor<PromotionBundleItem>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            // Pre-fetch promotions and menu items
            let allPromos = (try? modelContext.fetch(FetchDescriptor<Promotion>())) ?? []
            let promoMap = Dictionary(uniqueKeysWithValues: allPromos.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteItems {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])

                var promotion: Promotion? = nil
                if let pid = remote["promotion_id"] as? String { promotion = promoMap[pid.lowercased()] }
                var menuItem: MenuItem? = nil
                if let mid = remote["menu_item_id"] as? String {
                    menuItem = (try? modelContext.fetch(FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == mid })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeletedRemote {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    if local.isDeleted { continue }
                    local.promotion = promotion
                    local.menuItem = menuItem
                    local.quantity = remoteInt(remote["quantity"], fallback: 1)
                    local.displayOrder = remoteInt(remote["display_order"])
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeletedRemote { continue }
                    let item = PromotionBundleItem(
                        id: id,
                        promotion: promotion,
                        menuItem: menuItem,
                        quantity: remoteInt(remote["quantity"], fallback: 1),
                        displayOrder: remoteInt(remote["display_order"]),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(item)
                    localById[idStr.lowercased()] = item
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [PromotionBundleItem Pull Error]: \(error.localizedDescription)")
        }
    }
}
