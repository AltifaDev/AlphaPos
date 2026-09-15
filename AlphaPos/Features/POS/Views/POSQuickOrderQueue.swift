import SwiftUI

/// Queue surface for orders that do not belong to a restaurant table.
///
/// Selecting an order only reports the selection to the owner. It deliberately
/// does not mutate the active table session or the current POS cart.
struct POSQuickOrderQueue: View {
    let orders: [Order]
    let onSelect: (Order) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        NavigationStack {
            List(orders) { order in
                Button {
                    onSelect(order)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(order.queueNumber.map { "คิว #\($0)" } ?? order.orderNumber)
                                .font(.headline)
                            Text(order.orderNumber)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Text(order.orderType == "delivery" ? "Delivery" : (order.orderType == "walk_in" ? "Walk-in" : "Takeaway"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(order.status.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appAmber)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if orders.isEmpty {
                    ContentUnavailableView(
                        lm.currentLanguage == .thai ? "ไม่มี Quick Order" : "No Quick Orders",
                        systemImage: "takeoutbag.and.cup.and.straw",
                        description: Text(lm.currentLanguage == .thai ? "ออเดอร์จาก iPhone จะแสดงที่นี่" : "Orders from iPhone will appear here")
                    )
                }
            }
            .navigationTitle(lm.currentLanguage == .thai ? "คิวออเดอร์ด่วน" : "Quick Order Queue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.currentLanguage == .thai ? "ปิด" : "Done") { dismiss() }
                }
            }
        }
    }
}
