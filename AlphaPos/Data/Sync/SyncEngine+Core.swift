import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Core Sync Orchestration
extension SyncEngine {
    // MARK: - Sync Helpers

    func syncSecurityPolicies(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<SecurityPolicy>(
            predicate: #Predicate<SecurityPolicy> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let policies = try? modelContext.fetch(descriptor), !policies.isEmpty else { return }
        for policy in policies {
            do {
                let success = try await NetworkManager.shared.uploadSecurityPolicy(policy)
                if success { policy.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [SecurityPolicy Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncRolePermissions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Role>(
            predicate: #Predicate<Role> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let roles = try? modelContext.fetch(descriptor), !roles.isEmpty else { return }
        for role in roles {
            do {
                let success = try await NetworkManager.shared.replaceRolePermissions(role: role)
                if success { role.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [RolePermission Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncMerchantDevices(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<MerchantDevice>(
            predicate: #Predicate<MerchantDevice> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let devices = try? modelContext.fetch(descriptor), !devices.isEmpty else { return }
        for device in devices {
            do {
                let success = try await NetworkManager.shared.uploadMerchantDevice(device)
                if success { device.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [MerchantDevice Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncStaffSessions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<StaffSessionRecord>(
            predicate: #Predicate<StaffSessionRecord> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }

        // Pre-fetch all employees once (avoid N+1 query inside loop)
        var __descallEmployees = FetchDescriptor<Employee>()
        __descallEmployees.fetchLimit = 500  // N3: prevent OOM
        let allEmployees = (try? modelContext.fetch(__descallEmployees)) ?? []
        let employeeMap = Dictionary(uniqueKeysWithValues: allEmployees.map { ($0.id, $0) })

        for session in sessions {
            do {
                // Guard: skip if the referenced employee hasn't been synced to server yet
                // to avoid FK violation on staff_sessions.employee_id_fkey
                if let empId = session.employeeId {
                    let emp = employeeMap[empId]
                    // Skip if: employee not in local store (unknown) OR found but not yet synced
                    if emp == nil || emp?.isSynced == false {
                        continue  // employee not yet on server — defer to next sync cycle
                    }
                }
                let success = try await NetworkManager.shared.uploadStaffSessionRecord(session)
                if success { session.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [StaffSession Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncAuditLogs(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<AuditLog>(
            predicate: #Predicate<AuditLog> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let logs = try? modelContext.fetch(descriptor), !logs.isEmpty else { return }

        // Pre-fetch all employees once to avoid N+1 query inside loop
        var __descallEmployees = FetchDescriptor<Employee>()
        __descallEmployees.fetchLimit = 500  // N3: prevent OOM
        let allEmployees = (try? modelContext.fetch(__descallEmployees)) ?? []
        let employeeMap = Dictionary(uniqueKeysWithValues: allEmployees.map { ($0.id, $0) })

        for log in logs {
            do {
                if log.isDeleted {
                    // Guard: skip if referenced employee not yet on server
                    if let empId = log.employeeId {
                        let emp = employeeMap[empId]
                        if emp == nil || emp?.isSynced == false {
                            continue
                        }
                    }
                    _ = try await NetworkManager.shared.deleteAuditLogOnServer(id: log.id)
                    modelContext.delete(log)
                } else {
                    // Guard: skip if referenced employee not yet on server
                    if let empId = log.employeeId {
                        let emp = employeeMap[empId]
                        if emp == nil || emp?.isSynced == false {
                            continue
                        }
                    }
                    let success = try await NetworkManager.shared.uploadAuditLog(log)
                    if success { log.isSynced = true }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [AuditLog Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncOrders(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let orders = try? modelContext.fetch(descriptor), !orders.isEmpty else { return }

        // H-8 FIX: Clean up any duplicate unsynced order numbers before uploading to prevent constraint violations
        for order in orders {
            if let session = order.tableSession, !order.isSynced {
                // Find sibling orders that were created earlier or already synced
                let siblingOrders = session.orders.filter { $0.id != order.id && !$0.isDeleted }
                let hasConflict = siblingOrders.contains { $0.orderNumber == order.orderNumber }
                if hasConflict {
                    let sessionOrderCount = siblingOrders.count
                    order.orderNumber = "\(order.orderNumber)-\(sessionOrderCount + 1)"
                    order.updatedAt = Date()
                    modelContext.saveWithLogging(label: #function)
                }
            }
        }

        for order in orders {
            if order.isDeleted {
                do {
                    let success = try await NetworkManager.shared.deleteOrderOnServer(id: order.id)
                    if success {
                        modelContext.delete(order)
                        try modelContext.save()
                    } else {
                        encounteredSyncError = true
                    }
                } catch {
                    encounteredSyncError = true
                    print("SyncEngine [Order Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadOrder(order: order)

                if success {
                    order.isSynced = true
                    for item in order.items {
                        item.isSynced = true
                    }
                    order.updatedAt = Date()
                    try modelContext.save()
                } else {
                    encounteredSyncError = true
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Order Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncPayments(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate<Payment> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let payments = try? modelContext.fetch(descriptor), !payments.isEmpty else { return }

        for payment in payments {
            if payment.isDeleted {
                do {
                    _ = try await NetworkManager.shared.deletePaymentOnServer(id: payment.id)
                } catch {
                    // Non-fatal: payment may not exist on server yet (created offline then deleted before sync)
                    print("SyncEngine [Payment Delete]: \(error.localizedDescription)")
                }
                modelContext.delete(payment)
                modelContext.saveWithLogging(label: #function)
                continue
            }

            do {
                let success: Bool
                if let order = payment.order,
                   let tableSession = order.tableSession,
                   let table = tableSession.table {
                    success = try await NetworkManager.shared.completeCheckout(
                        paymentId: payment.id,
                        orderId: order.id,
                        amount: payment.amount,
                        method: payment.paymentMethod,
                        tableNumber: table.tableNumber
                    )
                } else {
                    success = try await NetworkManager.shared.uploadPayment(
                        id: payment.id,
                        orderId: payment.order?.id,
                        amount: payment.amount,
                        method: payment.paymentMethod
                    )
                }

                if success {
                    payment.isSynced = true
                    payment.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Payment Sync Error]: \(error.localizedDescription)")
            }

        }
    }

    func syncOrderDiscounts(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<OrderDiscount>(
            predicate: #Predicate<OrderDiscount> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let discounts = try? modelContext.fetch(descriptor), !discounts.isEmpty else { return }

        for discount in discounts {
            do {
                let success: Bool
                if discount.isDeleted {
                    success = try await NetworkManager.shared.deleteOrderDiscountOnServer(id: discount.id)
                    if success {
                        modelContext.delete(discount)
                        try modelContext.save()
                    }
                } else {
                    success = try await NetworkManager.shared.uploadOrderDiscount(discount)
                    if success {
                        discount.isSynced = true
                        discount.updatedAt = Date()
                        try modelContext.save()
                    }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [OrderDiscount Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncTimecards(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Timecard>(
            predicate: #Predicate<Timecard> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let timecards = try? modelContext.fetch(descriptor), !timecards.isEmpty else { return }

        for timecard in timecards {
            if timecard.isDeleted {
                do {
                    _ = try await NetworkManager.shared.deleteTimecardOnServer(id: timecard.id)
                } catch {
                    print("SyncEngine [Timecard Delete]: \(error.localizedDescription)")
                    encounteredSyncError = true
                }
                modelContext.delete(timecard)
                modelContext.saveWithLogging(label: #function)
                continue
            }

            guard let employeeId = timecard.employee?.id else {
                encounteredSyncError = true
                print("SyncEngine [Timecard Sync Error]: Missing employee relation for timecard \(timecard.id)")
                continue
            }

            // Duplicate detection: before pushing a new clock-in, check if there's
            // already an active timecard for this employee on the server
            if timecard.clockOut == nil {
                let remoteActive = try? await NetworkManager.shared.fetchActiveTimecard(employeeId: employeeId)
                if let remoteActive = remoteActive, remoteActive != timecard.id.uuidString.lowercased() {
                    print("SyncEngine [Timecard Sync]: Remote active timecard found for employee \(employeeId). Merging data into local record.")
                    // Another device created an active timecard — mark ours as a duplicate
                    timecard.status = "pending_audit"
                    timecard.notes = (timecard.notes ?? "") + " [Possible duplicate: remote active timecard exists]"
                }
            }

            let empName = "\(timecard.employee?.firstName ?? "") \(timecard.employee?.lastName ?? "")"
            do {
                let success = try await NetworkManager.shared.uploadTimecard(
                    id: timecard.id, employeeId: employeeId,
                    employeeName: empName,
                    clockIn: timecard.clockIn,
                    clockOut: timecard.clockOut,
                    status: timecard.status,
                    breakDuration: timecard.breakDurationMinutes,
                    overtimeMinutes: timecard.overtimeMinutes,
                    notes: timecard.notes,
                    clockInConfidence: timecard.clockInFaceConfidence,
                    clockOutConfidence: timecard.clockOutFaceConfidence,
                    clockInSelfieUrl: timecard.clockInSelfieUrl,
                    clockOutSelfieUrl: timecard.clockOutSelfieUrl,
                    shiftId: timecard.shift?.id,
                    verifiedByUserId: timecard.verifiedByUserId
                )

                if success {
                    timecard.isSynced = true
                    timecard.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Timecard Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncCustomers(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let customers = try? modelContext.fetch(descriptor), !customers.isEmpty else { return }
        for customer in customers {
            do {
                if customer.isDeleted {
                    if try await NetworkManager.shared.deleteCustomerOnServer(id: customer.id) {
                        modelContext.delete(customer)
                    }
                } else if try await NetworkManager.shared.uploadCustomer(customer: customer) {
                    customer.isSynced = true
                    customer.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Customer Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullCompletedOrdersAndPayments(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let remoteOrders = try await NetworkManager.shared.fetchCompletedOrdersFromSupabase()
            guard !remoteOrders.isEmpty else { return }

            for remoteOrder in remoteOrders {
                guard let idStr = remoteOrder["id"] as? String,
                      let orderId = UUID(uuidString: idStr) else { continue }

                // Check if this order already exists locally
                var descriptor = FetchDescriptor<Order>(
                    predicate: #Predicate<Order> { $0.id == orderId }
                )
                descriptor.fetchLimit = 1

                let orderNumber = remoteOrder["order_number"] as? String ?? remoteOrder["orderNumber"] as? String ?? "ORD-UNKNOWN"
                let total = remoteDouble(remoteOrder["total"])
                let subtotal = remoteDouble(remoteOrder["subtotal"])
                let tax = remoteDouble(remoteOrder["tax"])
                let serviceCharge = remoteDouble(remoteOrder["service_charge"] ?? remoteOrder["serviceCharge"])
                let discount = remoteDouble(remoteOrder["discount"])
                let status = remoteOrder["status"] as? String ?? "completed"
                let createdAtStr = remoteOrder["created_at"] as? String ?? remoteOrder["createdAt"] as? String ?? ""
                let orderType = remoteOrder["order_type"] as? String ?? remoteOrder["orderType"] as? String ?? "dine_in"
                let cashierName = remoteOrder["cashier_name"] as? String ?? remoteOrder["cashierName"] as? String ?? "Somsri"

                let createdAt = parseISO8601Date(createdAtStr)

                let existingOrder: Order
                if let existingOrders = try? modelContext.fetch(descriptor), let order = existingOrders.first {
                    existingOrder = order
                    existingOrder.status = status
                    existingOrder.total = total
                    existingOrder.subtotal = subtotal
                    existingOrder.tax = tax
                    existingOrder.serviceCharge = serviceCharge
                    existingOrder.discount = discount
                    existingOrder.orderType = orderType
                    existingOrder.cashierName = cashierName
                    existingOrder.isSynced = true
                } else {
                    existingOrder = Order(
                        id: orderId,
                        orderNumber: orderNumber,
                        orderType: orderType,
                        status: status,
                        subtotal: subtotal,
                        tax: tax,
                        serviceCharge: serviceCharge,
                        discount: discount,
                        total: total,
                        createdAt: createdAt,
                        cashierName: cashierName,
                        isSynced: true
                    )
                    modelContext.insert(existingOrder)
                }

                // Add or update remote items
                if let remoteItems = remoteOrder["order_items"] as? [[String: Any]] ?? remoteOrder["orderItems"] as? [[String: Any]] {
                    for remoteItem in remoteItems {
                        let itemIdStr = remoteItem["id"] as? String ?? ""
                        guard let itemId = UUID(uuidString: itemIdStr) else { continue }

                        let name = remoteItem["item_name"] as? String ?? remoteItem["itemName"] as? String ?? "Unknown Item"
                        let qty = remoteInt(remoteItem["quantity"])
                        let price = remoteDouble(remoteItem["unit_price"] ?? remoteItem["unitPrice"])
                        let itemStatus = remoteItem["status"] as? String ?? "served"

                        if let localItem = existingOrder.items.first(where: { $0.id == itemId }) {
                            localItem.quantity = qty
                            localItem.unitPrice = price
                            localItem.subtotal = Double(qty) * price
                            localItem.status = itemStatus
                            localItem.isSynced = true
                        } else {
                            let orderItem = OrderItem(
                                id: itemId,
                                order: existingOrder,
                                menuItem: nil,
                                itemName: name,
                                quantity: qty,
                                unitPrice: price,
                                notes: nil,
                                status: itemStatus,
                                isSynced: true
                            )
                            modelContext.insert(orderItem)
                            orderItem.order = existingOrder
                            existingOrder.items.append(orderItem)
                        }
                    }
                }

                // Add or update remote payments
                if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                    for remotePayment in remotePayments {
                        let paymentIdStr = remotePayment["id"] as? String ?? ""
                        guard let paymentId = UUID(uuidString: paymentIdStr) else { continue }

                        let amount = remoteDouble(remotePayment["amount"])
                        let method = remotePayment["payment_method"] as? String ?? remotePayment["paymentMethod"] as? String ?? "cash"
                        let pCreatedAtStr = remotePayment["created_at"] as? String ?? remotePayment["createdAt"] as? String ?? ""
                        let pCreatedAt = parseISO8601Date(pCreatedAtStr)
                        let pStatus = remotePayment["status"] as? String ?? "completed"

                        if let localPayment = existingOrder.payments.first(where: { $0.id == paymentId }) {
                            localPayment.amount = amount
                            localPayment.paymentMethod = method
                            localPayment.paidAt = pCreatedAt
                            localPayment.status = pStatus
                            localPayment.isSynced = true
                        } else {
                            let newPayment = Payment(
                                id: paymentId,
                                order: existingOrder,
                                paymentMethod: method,
                                amount: amount,
                                status: pStatus,
                                paidAt: pCreatedAt,
                                isSynced: true
                            )
                            modelContext.insert(newPayment)
                            existingOrder.payments.append(newPayment)
                        }
                    }
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [CompletedOrders Pull Error]: \(error.localizedDescription)")
        }
    }

    func pullCustomersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCustomers = try await NetworkManager.shared.fetchCustomersFromSupabase()
            guard !remoteCustomers.isEmpty else { return }
            var __desclocals = FetchDescriptor<Customer>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCustomers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.email = remote["email"] as? String
                    local.phone = remote["phone"] as? String
                    local.taxId = remote["tax_id"] as? String
                    local.address = remote["address"] as? String
                    local.loyaltyPoints = remoteInt(remote["loyalty_points"])
                    local.membershipTier = remote["membership_tier"] as? String ?? "standard"
                    local.totalSpend = remoteDouble(remote["total_spend"])
                    local.visitCount = remoteInt(remote["visit_count"])
                    local.notes = remote["notes"] as? String
                    local.allergies = remote["allergies"] as? String
                    local.preferences = remote["preferences"] as? String
                    if let dobStr = remote["date_of_birth"] as? String {
                        local.dateOfBirth = parseISO8601DateOptional(dobStr)
                    }
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let dob = (remote["date_of_birth"] as? String).flatMap { parseISO8601DateOptional($0) }
                    let customer = Customer(
                        id: id,
                        name: name,
                        email: remote["email"] as? String,
                        phone: remote["phone"] as? String,
                        taxId: remote["tax_id"] as? String,
                        address: remote["address"] as? String,
                        loyaltyPoints: remoteInt(remote["loyalty_points"]),
                        membershipTier: remote["membership_tier"] as? String ?? "standard",
                        totalSpend: remoteDouble(remote["total_spend"]),
                        visitCount: remoteInt(remote["visit_count"]),
                        notes: remote["notes"] as? String,
                        dateOfBirth: dob,
                        allergies: remote["allergies"] as? String,
                        preferences: remote["preferences"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(customer)
                    localById[idStr.lowercased()] = customer
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Customer Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncGiftCards(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<GiftCard>(
            predicate: #Predicate<GiftCard> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let cards = try? modelContext.fetch(descriptor), !cards.isEmpty else { return }
        for card in cards {
            do {
                if card.isDeleted {
                    if try await NetworkManager.shared.deleteGiftCardOnServer(id: card.id) {
                        modelContext.delete(card)
                    }
                } else if try await NetworkManager.shared.uploadGiftCard(card) {
                    card.isSynced = true
                    card.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [GiftCard Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullGiftCardsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCards = try await NetworkManager.shared.fetchGiftCardsFromSupabase()
            guard !remoteCards.isEmpty else { return }
            var __desclocals = FetchDescriptor<GiftCard>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCards {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let cardNumber = remote["card_number"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var customer: Customer? = nil
                if let customerIdStr = remote["customer_id"] as? String, let customerId = UUID(uuidString: customerIdStr) {
                    customer = (try? modelContext.fetch(FetchDescriptor<Customer>(predicate: #Predicate<Customer> { $0.id == customerId })))?.first
                }

                let expiresAt = (remote["expires_at"] as? String).flatMap { parseISO8601DateOptional($0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.cardNumber = cardNumber
                    local.balance = remoteDouble(remote["balance"])
                    local.initialValue = remoteDouble(remote["initial_value"])
                    local.customer = customer
                    local.status = remote["status"] as? String ?? "active"
                    local.expiresAt = expiresAt
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let card = GiftCard(
                        id: id,
                        cardNumber: cardNumber,
                        balance: remoteDouble(remote["balance"]),
                        initialValue: remoteDouble(remote["initial_value"]),
                        customer: customer,
                        status: remote["status"] as? String ?? "active",
                        expiresAt: expiresAt,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(card)
                    localById[idStr.lowercased()] = card
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [GiftCard Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncLoyaltyTransactions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<LoyaltyTransaction>(
            predicate: #Predicate<LoyaltyTransaction> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else { return }
        for txn in txns {
            do {
                if txn.isDeleted {
                    if try await NetworkManager.shared.deleteLoyaltyTransactionOnServer(id: txn.id) {
                        modelContext.delete(txn)
                    }
                } else if try await NetworkManager.shared.uploadLoyaltyTransaction(txn) {
                    txn.isSynced = true
                    txn.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [LoyaltyTransaction Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullLoyaltyTransactionsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteTxns = try await NetworkManager.shared.fetchLoyaltyTransactionsFromSupabase()
            guard !remoteTxns.isEmpty else { return }
            var __desclocals = FetchDescriptor<LoyaltyTransaction>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteTxns {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var customer: Customer? = nil
                if let customerIdStr = remote["customer_id"] as? String, let customerId = UUID(uuidString: customerIdStr) {
                    customer = (try? modelContext.fetch(FetchDescriptor<Customer>(predicate: #Predicate<Customer> { $0.id == customerId })))?.first
                }

                var order: Order? = nil
                if let orderIdStr = remote["order_id"] as? String, let orderId = UUID(uuidString: orderIdStr) {
                    order = (try? modelContext.fetch(FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == orderId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.customer = customer
                    local.order = order
                    local.transactionType = remote["transaction_type"] as? String ?? "earn"
                    local.points = remoteInt(remote["points"])
                    local.pointsBalanceAfter = remoteInt(remote["points_balance_after"])
                    local.transactionDescription = remote["description"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let txn = LoyaltyTransaction(
                        id: id,
                        customer: customer,
                        order: order,
                        transactionType: remote["transaction_type"] as? String ?? "earn",
                        points: remoteInt(remote["points"]),
                        pointsBalanceAfter: remoteInt(remote["points_balance_after"]),
                        transactionDescription: remote["description"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(txn)
                    localById[idStr.lowercased()] = txn
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [LoyaltyTransaction Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncRegisterSessions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<RegisterSession>(
            predicate: #Predicate<RegisterSession> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }
        for session in sessions {
            do {
                let success = try await NetworkManager.shared.uploadRegisterSession(session)
                if success { session.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [RegisterSession Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullRegisterSessions(_ modelContext: ModelContext) async {
        do {
            let remoteSessions = try await NetworkManager.shared.fetchRegisterSessionsFromSupabase()
            guard !remoteSessions.isEmpty else { return }
            var descriptor = FetchDescriptor<RegisterSession>()
            descriptor.fetchLimit = 500
            let locals = (try? modelContext.fetch(descriptor)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })
            
            // Pre-fetch all branches
            let allBranches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            let branchMap = Dictionary(uniqueKeysWithValues: allBranches.map { ($0.id.uuidString.lowercased(), $0) })
            
            for remote in remoteSessions {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                
                var branch: Branch? = nil
                if let branchIdStr = remote["branch_id"] as? String {
                    branch = branchMap[branchIdStr.lowercased()]
                }
                
                let openedByUserIdStr = remote["opened_by_user_id"] as? String ?? ""
                guard let openedByUserId = UUID(uuidString: openedByUserIdStr) else { continue }
                
                let closedByUserIdStr = remote["closed_by_user_id"] as? String
                let closedByUserId = closedByUserIdStr.flatMap { UUID(uuidString: $0) }
                
                let openedAtStr = remote["opened_at"] as? String ?? ""
                let openedAt = parseISO8601Date(openedAtStr)
                
                let closedAtStr = remote["closed_at"] as? String
                let closedAt = closedAtStr.flatMap { parseISO8601Date($0) }
                
                let openingCash = remoteDouble(remote["opening_cash"])
                let expectedClosingCash = remoteDouble(remote["expected_closing_cash"])
                let actualClosingCash = remoteDouble(remote["actual_closing_cash"])
                let cashDiscrepancy = remoteDouble(remote["cash_discrepancy"])
                let notes = remote["notes"] as? String
                let isDeleted = remote["is_deleted"] as? Bool ?? false
                
                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeleted {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    local.openedByUserId = openedByUserId
                    local.closedByUserId = closedByUserId
                    local.openedAt = openedAt
                    local.closedAt = closedAt
                    local.openingCash = openingCash
                    local.expectedClosingCash = expectedClosingCash
                    local.actualClosingCash = actualClosingCash
                    local.cashDiscrepancy = cashDiscrepancy
                    local.notes = notes
                    local.branch = branch
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeleted { continue }
                    let session = RegisterSession(
                        id: id,
                        openedByUserId: openedByUserId,
                        closedByUserId: closedByUserId,
                        openedAt: openedAt,
                        closedAt: closedAt,
                        openingCash: openingCash,
                        expectedClosingCash: expectedClosingCash,
                        actualClosingCash: actualClosingCash,
                        cashDiscrepancy: cashDiscrepancy,
                        notes: notes,
                        branch: branch,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(session)
                    localById[idStr.lowercased()] = session
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [RegisterSession Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncCashMovements(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<CashMovement>(
            predicate: #Predicate<CashMovement> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let movements = try? modelContext.fetch(descriptor), !movements.isEmpty else { return }
        
        // Pre-fetch all sessions once
        var sessDescriptor = FetchDescriptor<RegisterSession>()
        sessDescriptor.fetchLimit = 500
        let allSessions = (try? modelContext.fetch(sessDescriptor)) ?? []
        let sessionMap = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0) })
        
        for movement in movements {
            do {
                if let sess = movement.registerSession {
                    let syncedSess = sessionMap[sess.id]
                    if syncedSess == nil || syncedSess?.isSynced == false {
                        continue // Defer cash movement upload
                    }
                }
                let success = try await NetworkManager.shared.uploadCashMovement(movement)
                if success { movement.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [CashMovement Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullCashMovements(_ modelContext: ModelContext) async {
        do {
            let remoteMovements = try await NetworkManager.shared.fetchCashMovementsFromSupabase()
            guard !remoteMovements.isEmpty else { return }
            var descriptor = FetchDescriptor<CashMovement>()
            descriptor.fetchLimit = 500
            let locals = (try? modelContext.fetch(descriptor)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })
            
            // Pre-fetch all sessions
            let allSessions = (try? modelContext.fetch(FetchDescriptor<RegisterSession>())) ?? []
            let sessionMap = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id.uuidString.lowercased(), $0) })
            
            for remote in remoteMovements {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                
                var session: RegisterSession? = nil
                if let sessionIdStr = remote["register_session_id"] as? String {
                    session = sessionMap[sessionIdStr.lowercased()]
                }
                
                let movementType = remote["movement_type"] as? String ?? ""
                let amount = remoteDouble(remote["amount"])
                let reason = remote["reason"] as? String ?? ""
                
                let performedByEmployeeIdStr = remote["performed_by_employee_id"] as? String
                let performedByEmployeeId = performedByEmployeeIdStr.flatMap { UUID(uuidString: $0) }
                let isDeleted = remote["is_deleted"] as? Bool ?? false
                
                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeleted {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    local.registerSession = session
                    local.movementType = movementType
                    local.amount = amount
                    local.reason = reason
                    local.performedByEmployeeId = performedByEmployeeId
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeleted { continue }
                    let movement = CashMovement(
                        id: id,
                        registerSession: session,
                        movementType: movementType,
                        amount: amount,
                        reason: reason,
                        performedByEmployeeId: performedByEmployeeId,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(movement)
                    localById[idStr.lowercased()] = movement
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [CashMovement Pull Error]: \(error.localizedDescription)")
        }
    }

}
