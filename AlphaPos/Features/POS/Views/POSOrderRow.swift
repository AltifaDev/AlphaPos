import SwiftUI

// MARK: - Ordered Item Row

struct POSOrderRow: View {
    let groupedItem: POSView.GroupedOrderedItem
    let showsKitchenStatus: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RemoteImageView(
                imageUrl: groupedItem.imageURL,
                imageData: groupedItem.imageData,
                fallbackColor: Color(hex: groupedItem.colorHex ?? "1E1B4B"),
                fallbackIcon: "fork.knife",
                iconSize: 16
            )
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(groupedItem.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(groupedItem.status == "cancelled" ? .textTertiary : .textPrimary)
                    .strikethrough(groupedItem.status == "cancelled")
                    .lineLimit(2)

                Text("\(groupedItem.quantity) × ฿\(String(format: "%.0f", groupedItem.totalPrice / Double(max(1, groupedItem.quantity))))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .posRollingNumber(value: Double(groupedItem.quantity))

                ForEach(groupedItem.selectedModifiers, id: \.id) { modifier in
                    HStack(spacing: 4) {
                        Text("(\(modifier.name))")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("(+\(String(format: "%.0f", modifier.extraPrice))฿)")
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.textTertiary)
                }

                if !groupedItem.notes.isEmpty {
                    Text(LocalizationManager.shared.t("note_label_template", groupedItem.notes))
                        .font(.system(size: 10.5))
                        .foregroundColor(.appAmber)
                }

                if showsKitchenStatus && groupedItem.status.lowercased() != "served" {
                    statusBadge(status: groupedItem.status)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "฿%.0f", groupedItem.totalPrice))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .frame(width: 72, alignment: .trailing)
                .posRollingNumber(value: groupedItem.totalPrice)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .background(Color.appSurface)
        .opacity(groupedItem.status == "cancelled" ? 0.5 : 1)
        .posOrderQuantityFlash(trigger: groupedItem.quantity)
    }

    private func statusBadge(status: String) -> some View {
        let text: String
        let icon: String
        let color: Color

        switch status.lowercased() {
        case "cooking", "preparing":
            text = "กำลังปรุง"
            icon = "🍳"
            color = .appAmber
        case "ready":
            text = "พร้อมเสิร์ฟ"
            icon = "🛎️"
            color = .appTeal
        case "served":
            text = "เสิร์ฟแล้ว"
            icon = "textSecondary"
            // Wait, "textSecondary" is not a direct static color. We should use Color.textSecondary.
            return HStack(spacing: 3) {
                Text("🍽️")
                    .font(.system(size: 10))
                Text("pos_served".t)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.textSecondary.opacity(0.12))
            .foregroundColor(.textSecondary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.textSecondary.opacity(0.25), lineWidth: 0.5)
            )
        case "cancelled":
            text = "ยกเลิก"
            icon = "❌"
            color = .appRose
        default:
            text = status.capitalized
            icon = "⏳"
            color = .appAmber
        }

        return HStack(spacing: 3) {
            Text(icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct POSOrderQuantityFlashModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlashing = false
    @State private var flashToken = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        POSReferencePalette.accent.opacity(
                            isFlashing ? (reduceMotion ? 0.08 : 0.14) : 0
                        )
                    )
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, _ in
                flash()
            }
    }

    private func flash() {
        let token = UUID()
        flashToken = token

        withAnimation(.easeOut(duration: reduceMotion ? 0.04 : 0.08)) {
            isFlashing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.14)) {
            guard flashToken == token else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.10 : 0.26)) {
                isFlashing = false
            }
        }
    }
}

extension View {
    func posOrderQuantityFlash<Trigger: Equatable>(trigger: Trigger) -> some View {
        modifier(POSOrderQuantityFlashModifier(trigger: trigger))
    }
}
