import SwiftUI

struct InAppNotificationView: View {
    let item: InAppNotificationItem
    let onDismiss: () -> Void

    private var iconName: String {
        switch item.type {
        case .order:   return "shippingbox.fill"
        case .table:   return "table.furniture"
        case .request: return "bell.badge.fill"
        case .system:  return "checkmark.circle.fill"
        }
    }

    private var bgGradient: LinearGradient {
        switch item.type {
        case .order:   return APGradient.accent
        case .table:   return APGradient.positive
        case .request: return APGradient.warning
        case .system:  return APGradient.accent
        }
    }

    var body: some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(item.body)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(bgGradient)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, APSpacing.md)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onTapGesture { onDismiss() }
    }
}

struct InAppNotificationContainer: View {
    private var manager = InAppNotificationManager.shared

    var body: some View {
        Group {
            if let item = manager.currentItem {
                InAppNotificationView(item: item) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        manager.currentItem = nil
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.currentItem?.id)
    }
}