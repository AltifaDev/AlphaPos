import Foundation
import SwiftData

extension SyncEngine {
    func syncCheckoutLifecycle(_ modelContext: ModelContext) async {
        var sessionDescriptor = FetchDescriptor<CheckoutSession>(
            predicate: #Predicate { !$0.isSynced }
        )
        sessionDescriptor.fetchLimit = 500
        for session in (try? modelContext.fetch(sessionDescriptor)) ?? [] {
            do {
                if try await NetworkManager.shared.uploadCheckoutSession(session) {
                    session.isSynced = true
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [CheckoutSession]: \(error.localizedDescription)")
            }
        }

        var attemptDescriptor = FetchDescriptor<PaymentAttempt>(
            predicate: #Predicate { !$0.isSynced }
        )
        attemptDescriptor.fetchLimit = 500
        for attempt in (try? modelContext.fetch(attemptDescriptor)) ?? [] {
            do {
                if try await NetworkManager.shared.uploadPaymentAttempt(attempt) {
                    attempt.isSynced = true
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [PaymentAttempt]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }
}
