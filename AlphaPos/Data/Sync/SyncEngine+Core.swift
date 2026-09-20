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
        let dirtyPolicies = (try? modelContext.fetch(descriptor)) ?? []
        for policy in dirtyPolicies {
            do {
                let success = try await NetworkManager.shared.uploadSecurityPolicy(policy)
                if success { policy.isSynced = true }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [SecurityPolicy Sync Error]: \(error.localizedDescription)")
            }
        }

        do {
            if let remote = try await NetworkManager.shared.fetchSecurityPolicy() {
                let allPolicies = (try? modelContext.fetch(FetchDescriptor<SecurityPolicy>())) ?? []
                let policy = allPolicies.first ?? SecurityPolicy()
                if allPolicies.isEmpty { modelContext.insert(policy) }

                policy.passcodeMinLength = remote["passcode_min_length"] as? Int ?? policy.passcodeMinLength
                policy.passcodeMaxAttempts = remote["passcode_max_attempts"] as? Int ?? policy.passcodeMaxAttempts
                policy.lockoutMinutes = remote["lockout_minutes"] as? Int ?? policy.lockoutMinutes
                policy.staffSessionTimeoutMinutes = remote["staff_session_timeout_minutes"] as? Int ?? policy.staffSessionTimeoutMinutes
                policy.requireManagerOverrideForRefund = remote["require_manager_override_for_refund"] as? Bool ?? policy.requireManagerOverrideForRefund
                policy.requireManagerOverrideForVoid = remote["require_manager_override_for_void"] as? Bool ?? policy.requireManagerOverrideForVoid
                policy.requireManagerOverrideForNoSale = remote["require_manager_override_for_no_sale"] as? Bool ?? policy.requireManagerOverrideForNoSale
                policy.requireManagerOverrideForDrawerTest = remote["require_manager_override_for_drawer_test"] as? Bool ?? policy.requireManagerOverrideForDrawerTest
                policy.requireFaceScan = remote["require_face_scan"] as? Bool ?? policy.requireFaceScan
                policy.isSynced = true

                let defaults = UserDefaults.standard
                defaults.set(policy.passcodeMaxAttempts, forKey: "passcode_max_attempts")
                defaults.set(policy.lockoutMinutes, forKey: "passcode_lockout_minutes")
                defaults.set(policy.staffSessionTimeoutMinutes, forKey: "staff_session_timeout_minutes")
                defaults.set(policy.requireManagerOverrideForRefund, forKey: "require_manager_override_for_refund")
                defaults.set(policy.requireManagerOverrideForVoid, forKey: "require_manager_override_for_void")
                defaults.set(policy.requireManagerOverrideForNoSale, forKey: "require_manager_override_for_no_sale")
                defaults.set(policy.requireManagerOverrideForDrawerTest, forKey: "require_manager_override_for_drawer_test")
                defaults.set(policy.requireFaceScan, forKey: "require_face_scan")
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [SecurityPolicy Pull Error]: \(error.localizedDescription)")
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncRolePermissions(_ modelContext: ModelContext) async {
        // Deprecated: Roles and their permissions are synced atomically in syncRoles().
        // We keep this function as a no-op to maintain orchestration compatibility.
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

    /// Merge server audit_logs into local SwiftData (upsert by id).
    func pullAuditLogs(_ modelContext: ModelContext, limit: Int = 100) async {
        guard !UserDefaults.standard.bool(forKey: "offline_sync_mode") else { return }
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let rows = try await NetworkManager.shared.fetchAuditLogs(limit: limit)
            await MainActor.run {
                for row in rows {
                    guard let idStr = row["id"] as? String,
                          let id = UUID(uuidString: idStr) else { continue }

                    let targetId = id
                    var descriptor = FetchDescriptor<AuditLog>(
                        predicate: #Predicate<AuditLog> { $0.id == targetId }
                    )
                    descriptor.fetchLimit = 1
                    let existing = try? modelContext.fetch(descriptor).first

                    // Never overwrite a local unsynced edit with a remote row.
                    if let existing, !existing.isSynced { continue }

                    let actionType = row["action_type"] as? String ?? "unknown"
                    let details = row["details"] as? String
                    let employeeId = (row["employee_id"] as? String).flatMap(UUID.init(uuidString:))
                    let originalValue = row["original_value"] as? Double
                    let newValue = row["new_value"] as? Double
                    let createdAt = parseISO8601Date(row["created_at"])
                    let updatedAt = parseISO8601Date(row["updated_at"], fallback: createdAt)

                    if let existing {
                        existing.actionType = actionType
                        existing.details = details
                        existing.employeeId = employeeId
                        existing.originalValue = originalValue
                        existing.newValue = newValue
                        existing.createdAt = createdAt
                        existing.updatedAt = updatedAt
                        existing.isSynced = true
                        existing.isDeleted = false
                    } else {
                        let log = AuditLog(
                            id: id,
                            employeeId: employeeId,
                            actionType: actionType,
                            details: details,
                            originalValue: originalValue,
                            newValue: newValue,
                            createdAt: createdAt,
                            isSynced: true,
                            isDeleted: false,
                            updatedAt: updatedAt
                        )
                        modelContext.insert(log)
                    }
                }
                modelContext.saveWithLogging(label: #function)
            }
        } catch {
            reportSyncFailure("AuditLog pull", soft: true)
            print("SyncEngine [AuditLog Pull Error]: \(error.localizedDescription)")
        }
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
                // Audit logging is ancillary telemetry. A policy/auth mismatch
                // on audit_logs must not mark the operational sync as failed or
                // prevent orders from reaching the KDS. Keep the local row
                // unsynced so it can be retried after credentials/policy are
                // repaired, but let orders, payments, and order_items finish.
                print("SyncEngine [AuditLog Sync Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func syncOrders(_ modelContext: ModelContext) async {
        // Repair legacy/offline records before uploading. A stale local
        // dine-in order can retain a deleted table number (for example 222),
        // which the server correctly rejects and which otherwise poisons every
        // subsequent sync attempt. Preserve the sale/items, but normalize an
        // orphaned tableless record as a Quick Order.
        let localTables = (try? modelContext.fetch(FetchDescriptor<RestaurantTable>())) ?? []
        let localOrders = (try? modelContext.fetch(FetchDescriptor<Order>())) ?? []
        var repairedLegacyQuickOrders = 0
        for order in localOrders where !order.isDeleted && !order.isSynced && order.orderType == "dine_in" {
            let tableNumber = order.floorTableNumber
                ?? order.tableSession?.table?.tableNumber
                ?? ""
            let normalizedTable = tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let orderBranchId = order.branch.id.uuidString.lowercased()
            let hasLocalTable = !normalizedTable.isEmpty && localTables.contains(where: { (table: RestaurantTable) in
                !table.isDeleted && table.branchId.lowercased() == orderBranchId && table.tableNumber == normalizedTable
            })
            let hasLiveSession = order.tableSession?.isActive == true && order.tableSession?.table != nil
            if normalizedTable.uppercased() == "QUICK" || (!hasLocalTable && !hasLiveSession) {
                order.orderType = "take_out"
                order.tableSession = nil
                order.floorTableNumber = nil
                order.updatedAt = Date()
                order.isSynced = false
                repairedLegacyQuickOrders += 1
            }
        }
        if repairedLegacyQuickOrders > 0 {
            modelContext.saveWithLogging(label: "repairLegacyQuickOrders")
            print("SyncEngine [Order Repair]: normalized \(repairedLegacyQuickOrders) orphaned dine-in order(s) to take_out")
        }

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
                    let success = try await NetworkManager.shared.deleteOrderOnServer(
                        id: order.id, expectedRowVersion: order.rowVersion
                    )
                    if success {
                        modelContext.delete(order)
                        try modelContext.save()
                    } else {
                        encounteredSyncError = true
                    }
                } catch {
                    reportSyncFailure("Order delete: \(error.localizedDescription)", soft: false)
                    print("SyncEngine [Order Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let sentOrderUpdatedAt = order.updatedAt
                let sentItemVersions = Dictionary(uniqueKeysWithValues: order.items.map { ($0.id, $0.updatedAt) })
                let success = try await NetworkManager.shared.uploadOrder(order: order)

                if success {
                    // Local edits may arrive while the network request is in
                    // flight. Only mark the exact snapshot sent to the server
                    // as synced; newer edits must stay in the next sync cycle.
                    let itemsUnchanged = order.items.count == sentItemVersions.count &&
                        order.items.allSatisfy { sentItemVersions[$0.id] == $0.updatedAt }
                    let snapshotUnchanged = !order.isDeleted &&
                        order.updatedAt == sentOrderUpdatedAt && itemsUnchanged
                    order.isSynced = snapshotUnchanged
                    for item in order.items {
                        item.isSynced = snapshotUnchanged
                    }
                    if snapshotUnchanged { order.updatedAt = Date() }
                    try modelContext.save()
                } else {
                    reportSyncFailure("Order upload returned false (\(order.id.uuidString.prefix(8)))", soft: false)
                }
            } catch {
                await NetworkManager.shared.recordSyncConflict(
                    entityType: "order", entityId: order.id,
                    expectedVersion: order.rowVersion, error: error
                )
                reportSyncFailure("Order: \(error.localizedDescription)", soft: false)
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

        for payment in payments where payment.isDeleted {
            do {
                _ = try await NetworkManager.shared.deletePaymentOnServer(id: payment.id)
            } catch {
                // Non-fatal: payment may not exist on server yet (created offline then deleted before sync)
                print("SyncEngine [Payment Delete]: \(error.localizedDescription)")
            }
            modelContext.delete(payment)
            modelContext.saveWithLogging(label: #function)
        }

        let activePayments = payments.filter { !$0.isDeleted }
        let groupedByOrder = Dictionary(grouping: activePayments.compactMap { payment in
            payment.order.map { ($0.id, payment) }
        }, by: { $0.0 })

        for (_, entries) in groupedByOrder {
            guard let order = entries.first?.1.order else { continue }
            // Always send the complete captured tender set. This makes split
            // tender one idempotent server transaction instead of N partial
            // commits and prevents an early retry from freezing a partial set.
            let captured = order.payments.filter { !$0.isDeleted && $0.isCaptured }
            guard !captured.isEmpty else { continue }
            let capturedTotal = captured.reduce(0.0) { $0 + $1.amount }
            if order.usesGovernmentSupport {
                // The unpaid government share is a receivable, not a tender.
                // complete_checkout_atomic intentionally requires tender ==
                // order total, so preserve the full sale header and replicate
                // only the citizen tender here.
                for payment in captured where !payment.isSynced {
                    do {
                        if try await NetworkManager.shared.uploadPayment(
                            id: payment.id, orderId: order.id, amount: payment.amount,
                            method: payment.paymentMethod, paidAt: payment.paidAt,
                            businessDateKey: payment.businessDateKey,
                            registerSessionId: payment.registerSessionId
                        ) {
                            payment.isSynced = true
                            payment.updatedAt = Date()
                            try modelContext.save()
                        }
                    } catch {
                        reportSyncFailure("Government-support tender: \(error.localizedDescription)", soft: false)
                    }
                }
                continue
            }
            let expectedTotal = order.total
            guard abs(capturedTotal - expectedTotal) <= 0.05 else {
                reportSyncFailure("Checkout \(order.orderNumber) waiting for complete tender set", soft: true)
                continue
            }

            do {
                let tableNumber = order.tableSession?.table?.tableNumber ?? "QUICK"
                let success = try await NetworkManager.shared.completeCheckout(
                    order: order, payments: captured, tableNumber: tableNumber
                )
                if success {
                    for payment in captured where !payment.isSynced {
                        try await NetworkManager.shared.annotatePaymentBusinessContext(id: payment.id, paidAt: payment.paidAt, businessDateKey: payment.businessDateKey, registerSessionId: payment.registerSessionId)
                        payment.isSynced = true
                        payment.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Payment Sync Error]: \(error.localizedDescription)")
            }
        }

        // Legacy orphan payments cannot participate in an atomic checkout.
        // Preserve compatibility while surfacing them for reconciliation.
        for payment in activePayments where payment.order == nil {
            do {
                if try await NetworkManager.shared.uploadPayment(
                    id: payment.id, orderId: nil, amount: payment.amount,
                    method: payment.paymentMethod, paidAt: payment.paidAt,
                    businessDateKey: payment.businessDateKey,
                    registerSessionId: payment.registerSessionId
                ) {
                    payment.isSynced = true
                    payment.updatedAt = Date()
                    reportSyncFailure("Legacy orphan payment uploaded: \(payment.id.uuidString.prefix(8))", soft: true)
                    try modelContext.save()
                }
            } catch {
                reportSyncFailure("Orphan payment: \(error.localizedDescription)", soft: false)
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
                reportSyncFailure("Timecard missing employee", soft: true)
                print("SyncEngine [Timecard Sync Error]: Missing employee relation for timecard \(timecard.id)")
                continue
            }

            // Idempotent clock-in reconciliation. A remote open card means the
            // employee is already clocked in; it is not an audit failure. Adopt
            // the canonical server ID so a later clock-out updates that same row
            // instead of leaving the remote card open forever.
            if timecard.clockOut == nil {
                let remoteActive = try? await NetworkManager.shared.fetchActiveTimecard(employeeId: employeeId)
                if let remoteActive,
                   remoteActive != timecard.id.uuidString.lowercased(),
                   let canonicalId = UUID(uuidString: remoteActive) {
                    var canonicalDescriptor = FetchDescriptor<Timecard>(
                        predicate: #Predicate<Timecard> { $0.id == canonicalId }
                    )
                    canonicalDescriptor.fetchLimit = 1
                    if let canonical = try? modelContext.fetch(canonicalDescriptor).first {
                        // The server row is already represented locally. Discard
                        // only the unsynced duplicate; HR history remains on the
                        // canonical object.
                        if canonical.clockOut == nil {
                            modelContext.delete(timecard)
                            modelContext.saveWithLogging(label: "syncTimecards.mergeExistingActive")
                            continue
                        }
                    } else {
                        timecard.id = canonicalId
                    }

                    // Remove annotations produced by older builds. Scheduling
                    // review (for example an unscheduled shift) remains intact.
                    timecard.notes = timecard.notes?
                        .replacingOccurrences(of: " [Possible duplicate: remote active timecard exists]", with: "")
                    print("SyncEngine [Timecard Sync]: Adopted canonical active timecard \(canonicalId) for employee \(employeeId).")
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
            predicate: #Predicate<Customer> { $0.isSynced == false }
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
            let operationalBranch = try BranchContext.shared.requireActiveBranch(in: modelContext)
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
                let cashierName = remoteOrder["cashier_name"] as? String ?? remoteOrder["cashierName"] as? String ?? "Staff"
                let deliveryBrand = remoteOrder["delivery_brand"] as? String
                let deliveryGP = remoteDouble(remoteOrder["delivery_gp"])
                let deliveryAdFee = remoteDouble(remoteOrder["delivery_ad_fee"])
                let deliveryAdFeeIsPct = remoteBool(remoteOrder["delivery_ad_fee_is_pct"], fallback: false)
                let deliveryOtherFee = remoteDouble(remoteOrder["delivery_other_fee"])
                let queueNumber: String? = {
                    if let s = remoteOrder["queue_number"] as? String, !s.isEmpty { return s }
                    if let i = remoteOrder["queue_number"] as? Int { return NetworkManager.formatQueueNumber(i) }
                    return nil
                }()
                let receiptNumber = remoteOrder["receipt_number"] as? String
                let platformOrderNumber = remoteOrder["platform_order_number"] as? String
                let supportProgramName = remoteOrder["support_program_name"] as? String
                let supportGovernmentRate = remoteDouble(remoteOrder["support_government_rate"])
                let supportCitizenAmount = remoteDouble(remoteOrder["support_citizen_amount"])
                let supportGovernmentAmount = remoteDouble(remoteOrder["support_government_amount"])
                let supportSettlementStatus = remoteOrder["support_settlement_status"] as? String ?? "not_applicable"
                let businessDateKey = remoteOrder["business_date"] as? String ?? remoteOrder["businessDate"] as? String ?? ""
                let registerSessionId = ((remoteOrder["register_session_id"] ?? remoteOrder["registerSessionId"]) as? String).flatMap(UUID.init(uuidString:))

                let createdAt = parseISO8601Date(createdAtStr)

                let isNewOrder: Bool
                let existingOrder: Order
                if let existingOrders = try? modelContext.fetch(descriptor), let order = existingOrders.first {
                    isNewOrder = false
                    existingOrder = order
                    existingOrder.status = status
                    existingOrder.total = total
                    existingOrder.subtotal = subtotal
                    existingOrder.tax = tax
                    existingOrder.serviceCharge = serviceCharge
                    existingOrder.discount = discount
                    existingOrder.orderType = orderType
                    existingOrder.cashierName = cashierName
                    existingOrder.deliveryBrand = deliveryBrand
                    existingOrder.deliveryGP = deliveryGP
                    existingOrder.deliveryAdFee = deliveryAdFee
                    existingOrder.deliveryAdFeeIsPct = deliveryAdFeeIsPct
                    existingOrder.deliveryOtherFee = deliveryOtherFee
                    if let queueNumber { existingOrder.queueNumber = queueNumber }
                    if let receiptNumber, !receiptNumber.isEmpty { existingOrder.receiptNumber = receiptNumber }
                    if let platformOrderNumber, !platformOrderNumber.isEmpty {
                        existingOrder.platformOrderNumber = platformOrderNumber
                    }
                    existingOrder.supportProgramName = supportProgramName
                    existingOrder.supportGovernmentRate = supportGovernmentRate
                    existingOrder.supportCitizenAmount = supportCitizenAmount
                    existingOrder.supportGovernmentAmount = supportGovernmentAmount
                    existingOrder.supportSettlementStatus = supportSettlementStatus
                    existingOrder.businessDateKey = businessDateKey
                    existingOrder.registerSessionId = registerSessionId
                    existingOrder.isSynced = true
                } else {
                    isNewOrder = true
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
                        businessDateKey: businessDateKey,
                        registerSessionId: registerSessionId,
                        branch: operationalBranch,
                        receiptNumber: receiptNumber,
                        cashierName: cashierName,
                        queueNumber: queueNumber,
                        deliveryBrand: deliveryBrand,
                        deliveryGP: deliveryGP,
                        deliveryAdFee: deliveryAdFee,
                        deliveryAdFeeIsPct: deliveryAdFeeIsPct,
                        deliveryOtherFee: deliveryOtherFee,
                        platformOrderNumber: platformOrderNumber,
                        supportProgramName: supportProgramName,
                        supportGovernmentRate: supportGovernmentRate,
                        supportCitizenAmount: supportCitizenAmount,
                        supportGovernmentAmount: supportGovernmentAmount,
                        supportSettlementStatus: supportSettlementStatus,
                        isSynced: true
                    )
                    modelContext.insert(existingOrder)
                }

                // Add or update remote items
                // fetchCustomerOrders normalizes the joined response to `items`.
                // Keep the legacy keys as fallbacks for older callers, but do
                // not omit items when inserting a brand-new order. Previously
                // the new-order path only checked `order_items`/`orderItems`,
                // so Quick Orders arrived with a valid header but an empty cart
                // and a zero payable total until a later refresh.
                if let remoteItems = remoteOrder["items"] as? [[String: Any]]
                    ?? remoteOrder["order_items"] as? [[String: Any]]
                    ?? remoteOrder["orderItems"] as? [[String: Any]] {
                    for remoteItem in remoteItems {
                        let itemIdStr = remoteItem["id"] as? String ?? ""
                        guard let itemId = UUID(uuidString: itemIdStr) else { continue }

                        let name = remoteItem["item_name"] as? String ?? remoteItem["itemName"] as? String ?? "Unknown Item"
                        let qty = remoteInt(remoteItem["quantity"])
                        let price = remoteDouble(
                            remoteItem["unit_price"] ?? remoteItem["unitPrice"] ?? remoteItem["price"]
                        )
                        let itemStatus = remoteItem["status"] as? String ?? "served"
                        let lineType = OrderItemLineType(
                            rawValue: remoteItem["line_type"] as? String
                                ?? remoteItem["lineType"] as? String
                                ?? OrderItemLineType.main.rawValue
                        ) ?? .main

                        if let localItem = existingOrder.items.first(where: { $0.id == itemId }) {
                            localItem.quantity = qty
                            localItem.unitPrice = price
                            localItem.subtotal = Double(qty) * price
                            localItem.lineType = lineType.rawValue
                            localItem.lineTypeVersion = 1
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
                                lineType: lineType,
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
                        let pBusinessDate = remotePayment["business_date"] as? String ?? ""
                        let pRegisterSessionId = (remotePayment["register_session_id"] as? String).flatMap(UUID.init(uuidString:))

                        let ledgerPayment: Payment
                        if let localPayment = existingOrder.payments.first(where: { $0.id == paymentId }) {
                            localPayment.amount = amount
                            localPayment.paymentMethod = method
                            localPayment.paidAt = pCreatedAt
                            localPayment.status = pStatus
                            localPayment.businessDateKey = pBusinessDate
                            localPayment.registerSessionId = pRegisterSessionId
                            localPayment.isSynced = true
                            ledgerPayment = localPayment
                        } else {
                            let newPayment = Payment(
                                id: paymentId,
                                order: existingOrder,
                                paymentMethod: method,
                                amount: amount,
                                status: pStatus,
                                paidAt: pCreatedAt,
                                businessDateKey: pBusinessDate,
                                registerSessionId: pRegisterSessionId,
                                isSynced: true
                            )
                            modelContext.insert(newPayment)
                            existingOrder.payments.append(newPayment)
                            ledgerPayment = newPayment
                        }
                        AccountingLedgerService.recordCapturedPayment(ledgerPayment, order: existingOrder, in: modelContext)
                    }
                }

                if isNewOrder && NotificationDeliveryPolicy.shouldDeliverPulledEvent(
                    isFirstSync: self.isFirstSync,
                    createdAt: createdAt
                ) {
                    let tNumber = (remoteOrder["table_number"] as? String)
                        ?? (remoteOrder["tableNumber"] as? String)
                        ?? "QUICK"
                    self.triggerLocalNotification(
                        orderNumber: orderNumber,
                        tableNumber: tNumber,
                        queueNumber: queueNumber,
                        orderType: orderType
                    )
                    let remoteItemsCount = (remoteOrder["items"] as? [[String: Any]]
                        ?? remoteOrder["order_items"] as? [[String: Any]]
                        ?? remoteOrder["orderItems"] as? [[String: Any]])?.count ?? existingOrder.items.count
                    self.alertNewCustomerOrder(
                        orderNumber: orderNumber,
                        tableNumber: tNumber,
                        itemCount: remoteItemsCount,
                        queueNumber: queueNumber
                    )
                }
            }
            modelContext.saveWithLogging(label: #function)
            self.refreshLiveOperationalAlerts(modelContext: modelContext)
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
            predicate: #Predicate<GiftCard> { $0.isSynced == false }
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
            predicate: #Predicate<LoyaltyTransaction> { $0.isSynced == false }
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
                guard let branch else {
                    encounteredSyncError = true
                    continue
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
                let businessDateKey = remote["business_date"] as? String ?? ""
                let isDeleted = remote["is_deleted"] as? Bool ?? false

                if let local = localById[idStr.lowercased()] {
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
                    if isDeleted {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    local.openedByUserId = openedByUserId
                    local.closedByUserId = closedByUserId
                    local.openedAt = openedAt
                    local.closedAt = closedAt
                    local.businessDateKey = businessDateKey.isEmpty ? BusinessDayContext.key(for: openedAt, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID) : businessDateKey
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
                        businessDateKey: businessDateKey,
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
