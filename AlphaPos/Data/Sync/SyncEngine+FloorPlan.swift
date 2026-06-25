import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Floor Plan, Orders, Sessions Sync
extension SyncEngine {
    // MARK: - Floor Plan Image Sync
    func syncFloorPlanImages(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<FloorPlanImage>(
            predicate: #Predicate<FloorPlanImage> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            do {
                let success = try await NetworkManager.shared.uploadFloorPlanImage(floorPlan: item)
                if success {
                    if item.isDeleted {
                        modelContext.delete(item)
                    } else {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                    try? modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [FloorPlanImage Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncEmployees(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate<Employee> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let employees = try? modelContext.fetch(descriptor), !employees.isEmpty else { return }

        for employee in employees {
            do {
                let success = try await NetworkManager.shared.uploadEmployee(employee: employee)
                if success {
                    if employee.isDeleted {
                        modelContext.delete(employee)
                    } else {
                        employee.isSynced = true
                        employee.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Employee Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncEmployeeShifts(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<EmployeeShift>(
            predicate: #Predicate<EmployeeShift> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let shifts = try? modelContext.fetch(descriptor), !shifts.isEmpty else { return }

        for shift in shifts {
            if shift.isDeleted {
                modelContext.delete(shift)
                try? modelContext.save()
                continue
            }

            guard shift.employee != nil else {
                encounteredSyncError = true
                print("SyncEngine [EmployeeShift Sync Error]: Missing employee relation for shift \(shift.id)")
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadEmployeeShift(shift: shift)
                if success {
                    shift.isSynced = true
                    shift.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [EmployeeShift Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncMerchant() async {
        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return }

        let name = UserDefaults.standard.string(forKey: "store_name") ?? UserDefaults.standard.string(forKey: "logged_in_name") ?? "My New POS Shop"
        let email = UserDefaults.standard.string(forKey: "logged_in_email") ?? "owner@alphapos.com"
        let kitchenWorkflowRequired = UserDefaults.standard.object(forKey: "kitchen_workflow_required") as? Bool ?? true
        let isTableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
        let isWebOrderingEnabled = UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true

        let phone = UserDefaults.standard.string(forKey: "store_phone")
        let website = UserDefaults.standard.string(forKey: "store_website")
        let address = UserDefaults.standard.string(forKey: "store_address")
        let taxId = UserDefaults.standard.string(forKey: "store_tax_id")
        let branchCode = UserDefaults.standard.string(forKey: "store_branch_code")
        let taxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double
        let taxType = UserDefaults.standard.string(forKey: "store_tax_type")
        let serviceChargeRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double
        let receiptHeader = UserDefaults.standard.string(forKey: "store_receipt_header")
        let receiptFooter = UserDefaults.standard.string(forKey: "store_receipt_footer")
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number")

        do {
            _ = try await NetworkManager.shared.uploadMerchant(
                id: merchantId,
                name: name,
                email: email,
                kitchenWorkflowRequired: kitchenWorkflowRequired,
                isTableSystemEnabled: isTableSystemEnabled,
                isWebOrderingEnabled: isWebOrderingEnabled,
                phone: phone,
                website: website,
                address: address,
                taxId: taxId,
                branchCode: branchCode,
                taxRate: taxRate,
                taxType: taxType,
                serviceChargeRate: serviceChargeRate,
                receiptHeader: receiptHeader,
                receiptFooter: receiptFooter,
                promptPayNumber: promptPayNumber
            )
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Merchant Sync Error]: \(error.localizedDescription)")
        }
    }

    func pullRestaurantTables(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        // 0. Normalize existing local table numbers (e.g. "T1" -> "1")
        let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
        if let localTables = try? modelContext.fetch(localTablesDescriptor) {
            var needsSave = false
            for table in localTables {
                let trimmed = table.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("t") {
                    let suffix = String(trimmed.dropFirst())
                    if suffix.allSatisfy({ $0.isNumber }) {
                        table.tableNumber = suffix
                        table.isSynced = false
                        table.updatedAt = Date()
                        needsSave = true
                    }
                }
            }
            if needsSave {
                try? modelContext.save()
            }
        }

        do {
            let remoteTables = try await NetworkManager.shared.fetchRestaurantTables()
            
            var remoteIds = Set<UUID>()

            if remoteTables.isEmpty {
                #if DEBUG
                print("SyncEngine: Server has 0 tables. Forcing re-sync of local tables.")
                #endif
                let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
                if let localTables = try? modelContext.fetch(localTablesDescriptor) {
                    var needsSave = false
                    for table in localTables {
                        if table.isSynced {
                            table.isSynced = false
                            table.updatedAt = Date()
                            needsSave = true
                        }
                    }
                    if needsSave {
                        try? modelContext.save()
                    }
                }
            }

            for remoteTable in remoteTables {
                guard let idStr = remoteTable["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                
                remoteIds.insert(id)

                let tableNumber = remoteTable["table_number"] as? String ?? ""
                let capacity = remoteTable["capacity"] as? Int ?? 2
                let status = remoteTable["status"] as? String ?? "vacant"
                let qrCodeIdentifier = remoteTable["qr_code_identifier"] as? String
                let positionX = remoteTable["position_x"] as? Double ?? 0.0
                let positionY = remoteTable["position_y"] as? Double ?? 0.0
                let floor = remoteTable["floor"] as? Int ?? 1
                let zone = remoteTable["zone"] as? String ?? "Indoor"
                let isDeleted = remoteTable["is_deleted"] as? Bool ?? false

                let updatedAtStr = remoteTable["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                var existingTable: RestaurantTable? = nil
                let idDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.id == id }
                )

                if let matches = try? modelContext.fetch(idDescriptor), let first = matches.first {
                    existingTable = first
                } else {
                    let numDescriptor = FetchDescriptor<RestaurantTable>(
                        predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                    )
                    if let matches = try? modelContext.fetch(numDescriptor), !matches.isEmpty {
                        // Prioritize preserving the table that has active sessions or unsynced edits
                        let sortedMatches = matches.sorted { t1, t2 in
                            let t1HasActive = t1.sessions.contains(where: { $0.isActive })
                            let t2HasActive = t2.sessions.contains(where: { $0.isActive })
                            if t1HasActive != t2HasActive {
                                return t1HasActive && !t2HasActive
                            }
                            return !t1.isSynced && t2.isSynced
                        }

                        existingTable = sortedMatches.first
                        existingTable?.id = id

                        if sortedMatches.count > 1 {
                            for i in 1..<sortedMatches.count {
                                modelContext.delete(sortedMatches[i])
                            }
                        }
                    }
                }

                if let table = existingTable {
                    if isDeleted {
                        modelContext.delete(table)
                    } else {
                        // Only overwrite table properties from the server if local changes are already synced
                        if table.isSynced {
                            if table.tableNumber != tableNumber { table.tableNumber = tableNumber }
                            if table.capacity != capacity { table.capacity = capacity }
                            if table.qrCodeIdentifier != qrCodeIdentifier { table.qrCodeIdentifier = qrCodeIdentifier }
                            if table.positionX != positionX { table.positionX = positionX }
                            if table.positionY != positionY { table.positionY = positionY }
                            if table.floor != floor { table.floor = floor }
                            if table.zone != zone { table.zone = zone }
                            if table.updatedAt != updatedAt { table.updatedAt = updatedAt }
                            
                            // Sync cleaning and reserved statuses from the server.
                            // vacant/occupied/reserved are handled by pullActiveSessions,
                            // but cleaning and reserved (when no session is active) are owned by the table record.
                            if status == "cleaning" || status == "reserved" {
                                if table.status != status {
                                    table.status = status
                                }
                            } else if status == "vacant" && (table.status == "cleaning" || table.status == "reserved") {
                                table.status = "vacant"
                            }
                        }

                        // ⚠️ DO NOT write table.status here.
                        // pullActiveSessions() runs immediately after and is the sole
                        // source of truth for status (occupied/vacant/reserved).
                        // Writing status here causes a flicker: vacant→occupied→vacant→occupied
                        // because SwiftUI @Query re-renders on every intermediate save().
                    }
                } else if !isDeleted {
                    let newTable = RestaurantTable(
                        id: id,
                        tableNumber: tableNumber,
                        capacity: capacity,
                        status: status,
                        qrCodeIdentifier: qrCodeIdentifier,
                        positionX: positionX,
                        positionY: positionY,
                        floor: floor,
                        zone: zone,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newTable)
                }
            }
            
            // Prune synced local tables that are no longer on the server
            let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
            if let localTables = try? modelContext.fetch(localTablesDescriptor) {
                for table in localTables {
                    if table.isSynced && !remoteIds.contains(table.id) {
                        modelContext.delete(table)
                    }
                }
            }
            
            try? modelContext.save()
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Table Pull Error]: \(error.localizedDescription)")
        }
    }

    // Pull active orders from customer mobile app and insert into local SwiftData store
    func pullCustomerOrders(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let remoteOrders = try await NetworkManager.shared.fetchCustomerOrders()

            // Track all remote order IDs to identify deleted orders later
            var remoteOrderIds = Set<UUID>()

            for remoteOrder in remoteOrders {
                guard let idString = remoteOrder["id"] as? String,
                      let orderId = UUID(uuidString: idString) else { continue }

                remoteOrderIds.insert(orderId)

                // Check if this order already exists locally
                var descriptor = FetchDescriptor<Order>(
                    predicate: #Predicate<Order> { $0.id == orderId }
                )
                descriptor.fetchLimit = 500  // Prevent OOM on large datasets

                let orderNumber = remoteOrder["orderNumber"] as? String ?? "ORD-UNKNOWN"
                let total = remoteOrder["total"] as? Double ?? 0.0
                let status = remoteOrder["status"] as? String ?? "preparing"
                let createdAtStr = remoteOrder["createdAt"] as? String ?? ""
                let tableNumber = remoteOrder["tableNumber"] as? String ?? ""

                let createdAt = parseISO8601Date(createdAtStr)

                // Find or create Table Session for this tableNumber
                let tableDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                )

                let sessionToken = remoteOrder["sessionToken"] as? String ?? remoteOrder["session_token"] as? String
                var targetTableSession: TableSession? = nil

                if let token = sessionToken {
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.sessionToken == token }
                    )
                    if let sessions = try? modelContext.fetch(sessionDesc), let matchedSession = sessions.first {
                        targetTableSession = matchedSession
                    }
                }

                if targetTableSession == nil {
                    if let tables = try? modelContext.fetch(tableDescriptor), let table = tables.first {
                        let tableSessionIdStr = remoteOrder["table_session_id"] as? String ?? remoteOrder["tableSessionId"] as? String ?? ""
                        let tableSessionId = UUID(uuidString: tableSessionIdStr) ?? UUID()

                        if let activeSession = table.sessions.first(where: { $0.isActive }) {
                            if Calendar.current.isDateInToday(activeSession.startedAt) {
                                targetTableSession = activeSession
                            } else {
                                // Close stale session
                                activeSession.isActive = false
                                activeSession.endedAt = Date()
                                activeSession.isSynced = false
                                activeSession.updatedAt = Date()

                                let newSession = TableSession(id: tableSessionId, startedAt: Date(), isActive: true, table: table, isSynced: true)
                                if let token = sessionToken {
                                    newSession.sessionToken = token
                                }
                                modelContext.insert(newSession)
                                targetTableSession = newSession
                                table.status = "occupied"
                            }
                        } else {
                            let newSession = TableSession(id: tableSessionId, startedAt: Date(), isActive: true, table: table, isSynced: true)
                            if let token = sessionToken {
                                newSession.sessionToken = token
                            }
                            modelContext.insert(newSession)
                            targetTableSession = newSession
                            table.status = "occupied"
                        }
                    }
                }

                if let existingOrders = try? modelContext.fetch(descriptor), let existingOrder = existingOrders.first {
                    // Order already exists. Update its status, total, and ensure it links to the active session.
                    existingOrder.status = status
                    existingOrder.isSynced = true // Self-healing sync status
                    existingOrder.total = total
                    if existingOrder.tableSession == nil || existingOrder.tableSession != targetTableSession {
                        existingOrder.tableSession = targetTableSession
                    }

                    // Update order items. Do not treat an empty remote item payload as
                    // authoritative for an existing order with local items: Supabase
                    // realtime can deliver the orders event before the order_items batch
                    // is visible, and deleting here makes the iPad appear to lose the order.
                    if let remoteItems = remoteOrder["items"] as? [[String: Any]],
                       !(remoteItems.isEmpty && !existingOrder.items.isEmpty && total > 0) {
                        let remoteItemIds = Set(remoteItems.compactMap { remoteItem -> UUID? in
                            if let idStr = remoteItem["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // 1. Delete local items that are no longer present on the server
                        for localItem in existingOrder.items {
                            if !remoteItemIds.contains(localItem.id) {
                                modelContext.delete(localItem)
                            }
                        }

                        // 2. Add or update remote items
                        for remoteItem in remoteItems {
                            let itemIdStr = remoteItem["id"] as? String ?? ""
                            if let itemId = UUID(uuidString: itemIdStr) {
                                let name = remoteItem["name"] as? String ?? "Unknown Item"
                                let qty = remoteItem["quantity"] as? Int ?? 1
                                let price = remoteItem["price"] as? Double ?? 0.0
                                let itemStatus = remoteItem["status"] as? String ?? "cooking"

                                if let localItem = existingOrder.items.first(where: { $0.id == itemId }) {
                                    localItem.quantity = qty
                                    localItem.unitPrice = price
                                    localItem.subtotal = Double(qty) * price
                                    localItem.status = itemStatus
                                    localItem.isSynced = true // Self-healing sync status
                                    let servedBy = remoteItem["served_by"] as? String
                                    localItem.servedBy = servedBy
                                    // Always update itemName from remote data
                                    if !name.isEmpty && name != "Unknown Item" {
                                        localItem.itemName = name
                                    }
                                    // Re-resolve menuItem if it was nil (fix persistent Unknown Item)
                                    if localItem.menuItem == nil {
                                        let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                                        if let menuItemIdStr = menuItemIdStr {
                                            var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                                            idDescriptor.fetchLimit = 1
                                            localItem.menuItem = (try? modelContext.fetch(idDescriptor))?.first
                                        }
                                        if localItem.menuItem == nil && !name.isEmpty && name != "Unknown Item" {
                                            let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                                            localItem.menuItem = (try? modelContext.fetch(nameDescriptor))?.first
                                        }
                                    }
                                } else {
                                    // Item was added remotely — look up MenuItem by ID first, then name
                                    let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                                    let menuItem: MenuItem?
                                    if let menuItemIdStr = menuItemIdStr {
                                        var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                                        idDescriptor.fetchLimit = 1  // N3: point lookup
                                        menuItem = (try? modelContext.fetch(idDescriptor))?.first
                                    } else {
                                        let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                                        menuItem = (try? modelContext.fetch(nameDescriptor))?.first
                                    }
                                    
                                    let servedBy = remoteItem["served_by"] as? String
                                    let orderItem = OrderItem(
                                        id: itemId,
                                        order: existingOrder,
                                        menuItem: menuItem,
                                        itemName: name,
                                        quantity: qty,
                                        unitPrice: price,
                                        notes: nil,
                                        status: itemStatus,
                                        servedBy: servedBy,
                                        isSynced: true
                                    )
                                    modelContext.insert(orderItem)
                                    orderItem.order = existingOrder
                                    orderItem.isSynced = true
                                    existingOrder.items.append(orderItem)
                                }
                            }
                        }
                    }

                    // Update order payments
                    if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                        let remotePaymentIds = Set(remotePayments.compactMap { remotePayment -> UUID? in
                            if let idStr = remotePayment["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // 1. Delete local payments that are no longer present on the server
                        for localPayment in existingOrder.payments {
                            if !remotePaymentIds.contains(localPayment.id) {
                                modelContext.delete(localPayment)
                            }
                        }

                        // 2. Add or update remote payments
                        for remotePayment in remotePayments {
                            let paymentIdStr = remotePayment["id"] as? String ?? ""
                            if let paymentId = UUID(uuidString: paymentIdStr) {
                                let amount = remotePayment["amount"] as? Double ?? 0.0
                                let method = remotePayment["paymentMethod"] as? String ?? "cash"
                                let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                                let pCreatedAt = parseISO8601Date(pCreatedAtStr)

                                if let localPayment = existingOrder.payments.first(where: { $0.id == paymentId }) {
                                    localPayment.amount = amount
                                    localPayment.paymentMethod = method
                                    localPayment.paidAt = pCreatedAt
                                } else {
                                    // Payment was added remotely, create it locally
                                    let newPayment = Payment(
                                        id: paymentId,
                                        order: existingOrder,
                                        paymentMethod: method,
                                        amount: amount,
                                        status: "completed",
                                        paidAt: pCreatedAt,
                                        isSynced: true // Already synced on server
                                    )
                                    modelContext.insert(newPayment)
                                    existingOrder.payments.append(newPayment)
                                }
                            }
                        }
                    }
                    try? modelContext.save()
                    continue
                }

                // FIX: retry inline ก่อนสร้าง Order — ถ้ายังไม่มี items หลัง retry ก็ยังสร้าง Order
                // เพื่อป้องกัน order หายไปจาก SwiftData (เดิม: continue ทิ้ง order ทันที)
                var effectiveItems = remoteOrder["items"] as? [[String: Any]] ?? []
                if effectiveItems.isEmpty && total > 0 {
                    #if DEBUG
                    print("SyncEngine [Pull]: Order \(orderNumber) has no items yet — retrying fetch inline.")
                    #endif
                    // Retry up to 3 รอบ (0.8s, 1.5s, 2.0s) ก่อน fall through สร้าง Order
                    for retryWait: UInt64 in [800_000_000, 1_500_000_000, 2_000_000_000] {
                        try? await Task.sleep(nanoseconds: retryWait)
                        if let freshOrders = try? await NetworkManager.shared.fetchCustomerOrders(),
                           let match = freshOrders.first(where: { ($0["id"] as? String) == idString }),
                           let freshItems = match["items"] as? [[String: Any]], !freshItems.isEmpty {
                            effectiveItems = freshItems
                            break
                        }
                    }
                    // ไม่ continue — fall through เสมอเพื่อสร้าง Order ใน SwiftData
                    // ถ้า items ยังว่าง iPhone self-healing polling จะ patch items ทีหลัง
                }

                // Create new Order
                let newOrder = Order(
                    id: orderId,
                    orderNumber: orderNumber,
                    tableSession: targetTableSession,
                    orderType: "dine_in",
                    status: status,
                    total: total,
                    createdAt: createdAt,
                    isSynced: true // Already synced on server
                )

                modelContext.insert(newOrder)

                // Map items
                if !effectiveItems.isEmpty {
                    let remoteItems = effectiveItems
                    for remoteItem in remoteItems {
                        let name = remoteItem["name"] as? String ?? "Unknown Item"
                        let qty = remoteItem["quantity"] as? Int ?? 1
                        let price = remoteItem["price"] as? Double ?? 0.0
                        let itemStatus = remoteItem["status"] as? String ?? "cooking"
                        let itemIdStr = remoteItem["id"] as? String ?? ""
                        let itemId = UUID(uuidString: itemIdStr) ?? UUID()

                        // Find local MenuItem by ID first, then fall back to name match
                        let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                        let localItem: MenuItem?
                        if let menuItemIdStr = menuItemIdStr {
                            var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                            idDescriptor.fetchLimit = 1  // N3: point lookup
                            localItem = (try? modelContext.fetch(idDescriptor))?.first
                        } else {
                            let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                            localItem = (try? modelContext.fetch(nameDescriptor))?.first
                        }

                        let servedBy = remoteItem["served_by"] as? String
                        let orderItem = OrderItem(
                            id: itemId,
                            order: newOrder,
                            menuItem: localItem,
                            itemName: name,
                            quantity: qty,
                            unitPrice: price,
                            notes: nil,
                            status: itemStatus,
                            servedBy: servedBy,
                            isSynced: true
                        )
                        modelContext.insert(orderItem)
                        orderItem.order = newOrder
                        orderItem.isSynced = true
                        newOrder.items.append(orderItem)
                    }
                }

                // Map payments
                if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                    for remotePayment in remotePayments {
                        let paymentIdStr = remotePayment["id"] as? String ?? ""
                        let paymentId = UUID(uuidString: paymentIdStr) ?? UUID()
                        let amount = remotePayment["amount"] as? Double ?? 0.0
                        let method = remotePayment["paymentMethod"] as? String ?? "cash"
                        let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                        let pCreatedAt = parseISO8601Date(pCreatedAtStr)

                        let newPayment = Payment(
                            id: paymentId,
                            order: newOrder,
                            paymentMethod: method,
                            amount: amount,
                            status: "completed",
                            paidAt: pCreatedAt,
                            isSynced: true // Already synced on server
                        )
                        modelContext.insert(newPayment)
                        newOrder.payments.append(newPayment)
                    }
                }

                try modelContext.save()
                
                let age = Date().timeIntervalSince(createdAt)
                if !self.isFirstSync && age < 300 {
                    self.triggerLocalNotification(orderNumber: orderNumber, tableNumber: tableNumber)
                }
                
                #if DEBUG
                print("SyncEngine [Pull]: Inserted customer order \(orderNumber) for Table \(tableNumber) successfully.")
                #endif
            }

            // Delete local synced orders belonging to active table sessions that are no longer on the server
            let orderDescriptor = FetchDescriptor<Order>()
            if let localOrders = try? modelContext.fetch(orderDescriptor) {
                for localOrder in localOrders {
                    if localOrder.isSynced && !localOrder.isDeleted && localOrder.tableSession?.isActive == true {
                        if !remoteOrderIds.contains(localOrder.id) {
                            modelContext.delete(localOrder)
                            #if DEBUG
                            print("SyncEngine [Pull]: Deleted local order \(localOrder.orderNumber) because it was removed from the server.")
                            #endif
                        }
                    }
                }
                try? modelContext.save()
            }

        } catch {
            encounteredSyncError = true
            print("SyncEngine [Pull Customer Orders Error]: \(error.localizedDescription)")
        }
    }

    func pullActiveSessions(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteSessions = try await NetworkManager.shared.fetchActiveSessions()
            let remoteActiveTables = Set(remoteSessions.compactMap { $0["tableNumber"] as? String })

            // ─────────────────────────────────────────────────────────────────
            // FIX: Merge deactivate + activate into a single pass per table.
            // Previously this was 2 separate passes which caused SwiftUI @Query
            // to see intermediate states:
            //   Pass 1 → table.status = "vacant"  (re-render #1 — FLICKER)
            //   Pass 2 → table.status = "occupied" (re-render #2)
            // Now we calculate the desired status first, then write ONCE only
            // if the value actually changed (guard before assign).
            // ─────────────────────────────────────────────────────────────────

            // Build a lookup: tableNumber → remote session dict (or nil if none)
            let remoteSessionByTable: [String: [String: Any]] = Dictionary(
                remoteSessions.compactMap { s -> (String, [String: Any])? in
                    guard let tn = s["tableNumber"] as? String else { return nil }
                    return (tn, s)
                },
                uniquingKeysWith: { first, _ in first }
            )

            // Single pass over all local tables
            let allTablesDescriptor = FetchDescriptor<RestaurantTable>()
            if let allTables = try? modelContext.fetch(allTablesDescriptor) {
                for table in allTables {
                    let tableNumber  = table.tableNumber
                    let remoteSession = remoteSessionByTable[tableNumber]
                    let hasRemoteSession = remoteSession != nil

                    // --- Fetch local active sessions for this table ---
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> {
                            $0.table?.tableNumber == tableNumber && $0.isActive
                        }
                    )
                    let localActiveSessions = (try? modelContext.fetch(sessionDesc)) ?? []

                    if hasRemoteSession, let rs = remoteSession {
                        // ── Table HAS an active remote session ──────────────
                        let sessionToken    = rs["sessionToken"] as? String ?? ""
                        let startedAtStr    = rs["started_at"] as? String ?? rs["created_at"] as? String ?? ""
                        let startedAt       = parseISO8601Date(startedAtStr)
                        let remoteGuestCount = (rs["guest_count"] as? Int) ?? (rs["guestCount"] as? Int) ?? 2
                        let idStr           = rs["id"] as? String ?? ""
                        let sessionId       = UUID(uuidString: idStr) ?? UUID()

                        var foundMatch = false
                        for activeSession in localActiveSessions {
                            if activeSession.sessionToken == sessionToken {
                                // Update existing matching session (no status change needed)
                                if activeSession.startedAt != startedAt { activeSession.startedAt = startedAt }
                                if activeSession.guestCount != remoteGuestCount { activeSession.guestCount = remoteGuestCount }
                                activeSession.isSynced = true
                                foundMatch = true
                            } else {
                                // Stale local session — close it (no status change yet)
                                if activeSession.isActive {
                                    activeSession.isActive = false
                                    activeSession.endedAt  = Date()
                                    #if DEBUG
                                    print("SyncEngine [Session Pull]: Closed stale session \(activeSession.sessionToken) for Table \(tableNumber)")
                                    #endif
                                }
                            }
                        }
                        if !foundMatch {
                            // No local active session matches → create one
                            let newSession = TableSession(
                                id: sessionId,
                                sessionToken: sessionToken,
                                startedAt: startedAt,
                                isActive: true,
                                table: table,
                                guestCount: remoteGuestCount,
                                isSynced: true
                            )
                            modelContext.insert(newSession)
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Created session for Table \(tableNumber) (\(remoteGuestCount) guests)")
                            #endif
                        }

                        // ── Write status ONCE, only if actually changed ─────
                        if table.status != "occupied" {
                            table.status    = "occupied"
                            table.updatedAt = Date()
                        }

                    } else {
                        // ── Table has NO active remote session ───────────────
                        for activeSession in localActiveSessions {
                            activeSession.isActive = false
                            activeSession.endedAt  = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Closed session for Table \(tableNumber) — no remote session")
                            #endif
                        }

                        // ── Write status ONCE, only if actually changed ─────
                        let expectedStatus = "vacant"
                        if table.status != expectedStatus
                            && table.status == "occupied"
                            && table.isSynced {
                            table.status    = expectedStatus
                            table.updatedAt = Date()
                        }
                    }
                }
            }

            try? modelContext.save()
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Sessions Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncServiceRequests() async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteRequests = try await NetworkManager.shared.fetchServiceRequests()
            var newRequests: [ServiceRequest] = []
            for req in remoteRequests {
                if let id = req["id"] as? String,
                   let tableNum = req["tableNumber"] as? String,
                   let type = req["requestType"] as? String,
                   let status = req["status"] as? String,
                   let createdAt = req["createdAt"] as? String {
                    let request = ServiceRequest(id: id, tableNumber: tableNum, requestType: type, status: status, createdAt: createdAt)
                    newRequests.append(request)

                    if status == "pending" {
                        let alreadyNotified = self.notifiedRequestIds.contains(id)
                        if !alreadyNotified {
                            self.notifiedRequestIds.insert(id)
                            self.triggerServiceRequestNotification(tableNumber: tableNum, requestType: type)
                        }
                    }
                }
            }

            await MainActor.run {
                self.activeRequests = newRequests
                // Prune IDs for requests no longer active to prevent unbounded growth
                self.notifiedRequestIds = self.notifiedRequestIds.intersection(Set(newRequests.map { $0.id }))
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Service Requests Sync Error]: \(error.localizedDescription)")
        }
    }

}
