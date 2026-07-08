import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Financial Data Sync (Expense, RefundTransaction, OrderTaxLine, Tip)
// These models contain critical financial data that must be synced to Supabase
// to ensure accurate reporting across all devices.
extension SyncEngine {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Expense
    // ──────────────────────────────────────────────────────────────────────

    func syncExpenses(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let expenses = try? modelContext.fetch(descriptor), !expenses.isEmpty else { return }

        for expense in expenses {
            do {
                if expense.isDeleted {
                    if try await NetworkManager.shared.deleteExpenseOnServer(id: expense.id) {
                        modelContext.delete(expense)
                    }
                } else if try await NetworkManager.shared.uploadExpense(expense) {
                    expense.isSynced = true
                    expense.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Expense Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullExpensesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteExpenses = try await NetworkManager.shared.fetchExpensesFromSupabase()
            guard !remoteExpenses.isEmpty else { return }

            var __desclocals = FetchDescriptor<Expense>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            // Pre-fetch suppliers and branches for FK resolution
            let allSuppliers = (try? modelContext.fetch(FetchDescriptor<Supplier>())) ?? []
            let supplierMap = Dictionary(uniqueKeysWithValues: allSuppliers.map { ($0.id.uuidString.lowercased(), $0) })
            let allBranches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            let branchMap = Dictionary(uniqueKeysWithValues: allBranches.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteExpenses {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let title = remote["title"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])
                if isDeletedRemote { continue }

                var supplier: Supplier? = nil
                if let sid = remote["supplier_id"] as? String { supplier = supplierMap[sid.lowercased()] }
                var branch: Branch? = nil
                if let bid = remote["branch_id"] as? String { branch = branchMap[bid.lowercased()] }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.title = title
                    local.invoiceNo = remote["invoice_no"] as? String
                    local.category = remote["category"] as? String ?? local.category
                    local.quantity = remoteDouble(remote["quantity"], fallback: 1.0)
                    local.unit = remote["unit"] as? String
                    local.unitPrice = remoteDouble(remote["unit_price"])
                    local.amount = remoteDouble(remote["amount"])
                    local.vatRate = remoteDouble(remote["vat_rate"])
                    local.vatAmount = remoteDouble(remote["vat_amount"])
                    local.paymentMethod = remote["payment_method"] as? String ?? local.paymentMethod
                    local.status = remote["status"] as? String ?? local.status
                    local.isCapEx = remoteBool(remote["is_capex"])
                    local.date = remoteDate(remote["date"])
                    local.notes = remote["notes"] as? String
                    local.supplier = supplier
                    local.branch = branch
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let expense = Expense(
                        id: id,
                        invoiceNo: remote["invoice_no"] as? String,
                        title: title,
                        category: remote["category"] as? String ?? "Other",
                        quantity: remoteDouble(remote["quantity"], fallback: 1.0),
                        unit: remote["unit"] as? String,
                        unitPrice: remoteDouble(remote["unit_price"]),
                        amount: remoteDouble(remote["amount"]),
                        vatRate: remoteDouble(remote["vat_rate"]),
                        vatAmount: remoteDouble(remote["vat_amount"]),
                        paymentMethod: remote["payment_method"] as? String ?? "Cash",
                        status: remote["status"] as? String ?? "Paid",
                        isCapEx: remoteBool(remote["is_capex"]),
                        date: remoteDate(remote["date"]),
                        notes: remote["notes"] as? String,
                        supplier: supplier,
                        branch: branch,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(expense)
                    localById[idStr.lowercased()] = expense
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Expense Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - RefundTransaction
    // ──────────────────────────────────────────────────────────────────────

    func syncRefundTransactions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<RefundTransaction>(
            predicate: #Predicate<RefundTransaction> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let refunds = try? modelContext.fetch(descriptor), !refunds.isEmpty else { return }

        for refund in refunds {
            do {
                if refund.isDeleted {
                    if try await NetworkManager.shared.deleteRefundTransactionOnServer(id: refund.id) {
                        modelContext.delete(refund)
                    }
                } else if try await NetworkManager.shared.uploadRefundTransaction(refund: refund) {
                    refund.isSynced = true
                    refund.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [RefundTransaction Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullRefundTransactionsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRefunds = try await NetworkManager.shared.fetchRefundTransactionsFromSupabase()
            guard !remoteRefunds.isEmpty else { return }

            var __desclocals = FetchDescriptor<RefundTransaction>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteRefunds {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])
                if isDeletedRemote { continue }

                var order: Order? = nil
                if let oid = remote["order_id"] as? String, let orderId = UUID(uuidString: oid) {
                    order = (try? modelContext.fetch(FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == orderId })))?.first
                }
                var payment: Payment? = nil
                if let pid = remote["original_payment_id"] as? String, let paymentId = UUID(uuidString: pid) {
                    payment = (try? modelContext.fetch(FetchDescriptor<Payment>(predicate: #Predicate<Payment> { $0.id == paymentId })))?.first
                }

                let refundedBy = (remote["refunded_by_employee_id"] as? String).flatMap { UUID(uuidString: $0) }
                let approvedBy = (remote["approved_by_employee_id"] as? String).flatMap { UUID(uuidString: $0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.order = order
                    local.originalPayment = payment
                    local.refundAmount = remoteDouble(remote["refund_amount"])
                    local.refundMethod = remote["refund_method"] as? String ?? local.refundMethod
                    local.reasonCode = remote["reason_code"] as? String ?? local.reasonCode
                    local.reasonNotes = remote["reason_notes"] as? String
                    local.refundedByEmployeeId = refundedBy
                    local.approvedByEmployeeId = approvedBy
                    local.status = remote["status"] as? String ?? local.status
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let refund = RefundTransaction(
                        id: id,
                        order: order,
                        originalPayment: payment,
                        refundAmount: remoteDouble(remote["refund_amount"]),
                        refundMethod: remote["refund_method"] as? String ?? "cash",
                        reasonCode: remote["reason_code"] as? String ?? "customer_request",
                        reasonNotes: remote["reason_notes"] as? String,
                        refundedByEmployeeId: refundedBy,
                        approvedByEmployeeId: approvedBy,
                        status: remote["status"] as? String ?? "completed",
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(refund)
                    localById[idStr.lowercased()] = refund
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [RefundTransaction Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - OrderTaxLine
    // ──────────────────────────────────────────────────────────────────────

    func syncOrderTaxLines(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<OrderTaxLine>(
            predicate: #Predicate<OrderTaxLine> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let taxLines = try? modelContext.fetch(descriptor), !taxLines.isEmpty else { return }

        for taxLine in taxLines {
            do {
                if taxLine.isDeleted {
                    if try await NetworkManager.shared.deleteOrderTaxLineOnServer(id: taxLine.id) {
                        modelContext.delete(taxLine)
                    }
                } else if try await NetworkManager.shared.uploadOrderTaxLine(taxLine) {
                    taxLine.isSynced = true
                    taxLine.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [OrderTaxLine Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullOrderTaxLinesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteTaxLines = try await NetworkManager.shared.fetchOrderTaxLinesFromSupabase()
            guard !remoteTaxLines.isEmpty else { return }

            var __desclocals = FetchDescriptor<OrderTaxLine>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteTaxLines {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var order: Order? = nil
                if let oid = remote["order_id"] as? String, let orderId = UUID(uuidString: oid) {
                    order = (try? modelContext.fetch(FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == orderId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.order = order
                    local.taxName = remote["tax_name"] as? String ?? local.taxName
                    local.taxRate = remoteDouble(remote["tax_rate"])
                    local.taxableAmount = remoteDouble(remote["taxable_amount"])
                    local.taxAmount = remoteDouble(remote["tax_amount"])
                    local.isInclusive = remoteBool(remote["is_inclusive"], fallback: true)
                    local.jurisdiction = remote["jurisdiction"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let taxLine = OrderTaxLine(
                        id: id,
                        order: order,
                        taxName: remote["tax_name"] as? String ?? "VAT",
                        taxRate: remoteDouble(remote["tax_rate"], fallback: 7.0),
                        taxableAmount: remoteDouble(remote["taxable_amount"]),
                        taxAmount: remoteDouble(remote["tax_amount"]),
                        isInclusive: remoteBool(remote["is_inclusive"], fallback: true),
                        jurisdiction: remote["jurisdiction"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(taxLine)
                    localById[idStr.lowercased()] = taxLine
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [OrderTaxLine Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Tip
    // ──────────────────────────────────────────────────────────────────────

    func syncTips(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Tip>(
            predicate: #Predicate<Tip> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let tips = try? modelContext.fetch(descriptor), !tips.isEmpty else { return }

        for tip in tips {
            do {
                if tip.isDeleted {
                    if try await NetworkManager.shared.deleteTipOnServer(id: tip.id) {
                        modelContext.delete(tip)
                    }
                } else if try await NetworkManager.shared.uploadTip(tip) {
                    tip.isSynced = true
                    tip.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Tip Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullTipsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteTips = try await NetworkManager.shared.fetchTipsFromSupabase()
            guard !remoteTips.isEmpty else { return }

            var __desclocals = FetchDescriptor<Tip>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteTips {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var order: Order? = nil
                if let oid = remote["order_id"] as? String, let orderId = UUID(uuidString: oid) {
                    order = (try? modelContext.fetch(FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == orderId })))?.first
                }
                var payment: Payment? = nil
                if let pid = remote["payment_id"] as? String, let paymentId = UUID(uuidString: pid) {
                    payment = (try? modelContext.fetch(FetchDescriptor<Payment>(predicate: #Predicate<Payment> { $0.id == paymentId })))?.first
                }
                let employeeId = (remote["employee_id"] as? String).flatMap { UUID(uuidString: $0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.order = order
                    local.payment = payment
                    local.amount = remoteDouble(remote["amount"])
                    local.tipType = remote["tip_type"] as? String ?? local.tipType
                    local.employeeId = employeeId
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let tip = Tip(
                        id: id,
                        order: order,
                        payment: payment,
                        amount: remoteDouble(remote["amount"]),
                        tipType: remote["tip_type"] as? String ?? "manual",
                        employeeId: employeeId,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(tip)
                    localById[idStr.lowercased()] = tip
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Tip Pull Error]: \(error.localizedDescription)")
        }
    }
}
