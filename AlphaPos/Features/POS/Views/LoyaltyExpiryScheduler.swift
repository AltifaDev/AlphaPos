// LoyaltyExpiryScheduler.swift
// AlphaPos — M-4: Loyalty Point Expiry Background Scheduler
//
// Runs once per app launch (and on LoyaltyManagementView.onAppear) to:
//   1. Find all "earn" LoyaltyTransactions whose expiresAt <= today
//   2. Deduct the expired points from customer.loyaltyPoints
//   3. Insert a "expire" LoyaltyTransaction as audit trail
//   4. Update customer.membershipTier if tier drops
//   5. Sync to Supabase

import Foundation
import SwiftData

@MainActor
final class LoyaltyExpiryScheduler {

    static let shared = LoyaltyExpiryScheduler()
    private init() {}

    /// UserDefaults key to throttle — run at most once per calendar day
    private let lastRunKey = "loyalty_expiry_last_run_date"

    // MARK: - Entry point (idempotent — safe to call multiple times)

    func runIfNeeded(modelContext: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastRun = UserDefaults.standard.object(forKey: lastRunKey) as? Date,
           Calendar.current.isDate(lastRun, inSameDayAs: today) {
            return // Already ran today
        }
        Task {
            await expirePoints(modelContext: modelContext)
            UserDefaults.standard.set(today, forKey: lastRunKey)
        }
    }

    // MARK: - Core expiry logic

    private func expirePoints(modelContext: ModelContext) async {
        let now = Date()

        // Fetch all earn transactions that have an expiresAt <= now and are not deleted
        let descriptor = FetchDescriptor<LoyaltyTransaction>(
            predicate: #Predicate<LoyaltyTransaction> {
                $0.transactionType == "earn" &&
                !$0.isDeleted &&
                $0.expiresAt != nil
            },
            sortBy: [SortDescriptor(\.expiresAt)]
        )
        guard let txns = try? modelContext.fetch(descriptor) else { return }

        // Filter in-memory (SwiftData predicate can't compare optional Date directly)
        let expired = txns.filter { tx in
            guard let exp = tx.expiresAt else { return false }
            return exp <= now
        }

        guard !expired.isEmpty else { return }

        // Group by customer
        var byCustomer: [UUID: (customer: Customer, totalExpiring: Int)] = [:]
        for tx in expired {
            guard let customer = tx.customer else { continue }
            let prev = byCustomer[customer.id]
            byCustomer[customer.id] = (customer, (prev?.totalExpiring ?? 0) + max(0, tx.points))
            // Mark transaction as soft-deleted so it doesn't run again
            tx.isDeleted = true
            tx.isSynced = false
            tx.updatedAt = now
        }

        // Apply expiry per customer
        for (_, info) in byCustomer {
            let customer = info.customer
            let expiring = info.totalExpiring
            guard expiring > 0 else { continue }

            let actualDeduct = min(expiring, customer.loyaltyPoints)
            customer.loyaltyPoints = max(0, customer.loyaltyPoints - actualDeduct)
            customer.membershipTier = resolvedTier(for: customer.totalSpend)
            customer.isSynced = false
            customer.updatedAt = now

            // Audit: "expire" transaction
            let expireTx = LoyaltyTransaction(
                customer: customer,
                order: nil,
                transactionType: "expire",
                points: -actualDeduct,
                pointsBalanceAfter: customer.loyaltyPoints,
                transactionDescription: "Points expired — \(actualDeduct) pts deducted",
                earnedAt: now,
                isSynced: false,
                isDeleted: false,
                updatedAt: now
            )
            modelContext.insert(expireTx)
        }

        // Save all changes
        modelContext.saveWithLogging(label: "LoyaltyExpiryScheduler.expirePoints")

        // Background sync to Supabase
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }

        #if DEBUG
        print("LoyaltyExpiryScheduler: expired \(byCustomer.count) customers, \(expired.count) transactions")
        #endif
    }

    // MARK: - Tier helper (mirrors POSViewModel.resolvedTier)
    private func resolvedTier(for totalSpend: Double) -> String {
        switch totalSpend {
        case 15000...: return "platinum"
        case 5000...:  return "gold"
        case 1000...:  return "silver"
        default:       return "standard"
        }
    }
}
