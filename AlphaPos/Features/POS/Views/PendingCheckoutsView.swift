import SwiftUI
import SwiftData

/// Operational queue for interrupted Quick Service tenders. It intentionally
/// shows attempts (not completed payments), so pending QR/EDC activity cannot
/// be confused with recognized revenue.
struct PendingCheckoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CheckoutSession> {
        $0.state == "parked" && !$0.isDeleted
    }, sort: \CheckoutSession.updatedAt, order: .reverse)
    private var sessions: [CheckoutSession]

    let onResume: (CheckoutSession) -> Void
    @State private var cancelTarget: CheckoutSession?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "ไม่มีรายการรอชำระ",
                        systemImage: "checkmark.circle",
                        description: Text("รายการที่พักระหว่างชำระจะแสดงที่นี่")
                    )
                } else {
                    List(sessions) { session in
                        row(session)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("รายการรอชำระ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
            .confirmationDialog("ยกเลิกการชำระรายการนี้?", isPresented: Binding(
                get: { cancelTarget != nil },
                set: { if !$0 { cancelTarget = nil } }
            ), titleVisibility: .visible) {
                Button("ยกเลิก Payment Attempt", role: .destructive) {
                    guard let session = cancelTarget else { return }
                    for attempt in session.paymentAttempts where !attempt.lifecycleState.isTerminal {
                        attempt.lifecycleState = .cancelled
                    }
                    session.lifecycleState = .abandoned
                    session.releaseLock(deviceId: session.lockedByDevice ?? "")
                    modelContext.saveWithLogging(label: "cancelPendingCheckout")
                    cancelTarget = nil
                }
                Button("กลับ", role: .cancel) { cancelTarget = nil }
            }
        }
        .apColorScheme()
    }

    private func row(_ session: CheckoutSession) -> some View {
        let order = session.order
        let attempt = session.paymentAttempts.sorted(by: { $0.updatedAt > $1.updatedAt }).first
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(order?.orderNumber ?? "Unknown ticket")
                        .font(.headline)
                    Text("\(attempt?.method.replacingOccurrences(of: "_", with: " ").capitalized ?? "ยังไม่เลือกวิธี") · \(relativeTime(session.parkedAt ?? session.updatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("฿\(order?.outstandingAmount ?? attempt?.amount ?? 0, specifier: "%.2f")")
                    .font(.title3.bold())
            }

            HStack {
                Label(attempt?.status.replacingOccurrences(of: "_", with: " ") ?? "parked",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                Button("ยกเลิก") { cancelTarget = session }
                    .foregroundColor(.red)
                Button("เรียกคืน") {
                    onResume(session)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
