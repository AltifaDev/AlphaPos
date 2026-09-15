import SwiftUI
import Combine

// MARK: - KDS visual language (Toast / Square KDS–aligned semantics)

enum KDSStationTheme {
    static func accent(_ station: KDSStation) -> Color {
        station == .kitchen ? Color(hex: "6366F1") : Color(hex: "0891B2")
    }

    static func accentSoft(_ station: KDSStation) -> Color {
        accent(station).opacity(0.14)
    }

    static func headerGradient(_ station: KDSStation) -> LinearGradient {
        let base = accent(station)
        return LinearGradient(
            colors: [base.opacity(0.15), Color.appSurfaceHigh.opacity(0.95), Color.appSurfaceHigh],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum KDSElapsedUrgency {
    case fresh, warning, critical

    static func from(minutes: Int) -> KDSElapsedUrgency {
        if minutes >= 15 { return .critical }
        if minutes >= 8 { return .warning }
        return .fresh
    }

    var color: Color {
        switch self {
        case .fresh: return Color(hex: "10B981")
        case .warning: return Color(hex: "F59E0B")
        case .critical: return Color(hex: "EF4444")
        }
    }

    var icon: String {
        switch self {
        case .fresh: return "clock.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "flame.fill"
        }
    }
}

struct KDSElapsedTimerBadge: View {
    let startDate: Date
    var compact: Bool = false

    @State private var totalSeconds = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var minutes: Int { totalSeconds / 60 }
    private var urgency: KDSElapsedUrgency { .from(minutes: minutes) }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: urgency.icon)
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, value: urgency == .critical)
            Text(formatted)
                .font(.system(size: compact ? 13 : 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .foregroundColor(urgency.color)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            Capsule(style: .continuous)
                .fill(urgency.color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(urgency.color.opacity(0.35), lineWidth: 1.2)
        )
        .shadow(color: urgency == .critical ? urgency.color.opacity(0.3) : .clear, radius: 8, y: 2)
        .onAppear { refresh() }
        .onReceive(tick) { _ in refresh() }
        .animation(.easeInOut(duration: 0.35), value: urgency)
    }

    private var formatted: String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func refresh() {
        totalSeconds = max(0, Int(Date().timeIntervalSince(startDate)))
    }
}

struct KDSMetaChip: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .textSecondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .textCase(.none)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.8)
        )
    }
}

struct KDSStationBadge: View {
    let station: KDSStation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: station == .kitchen ? "flame.fill" : "wineglass.fill")
                .font(.system(size: 12, weight: .black))
            Text(station == .kitchen ? "kds_station_kitchen_upper".t : "kds_station_bar_upper".t)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: station == .kitchen
                            ? [Color(hex: "6366F1"), Color(hex: "4F46E5")]
                            : [Color(hex: "06B6D4"), Color(hex: "0891B2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: KDSStationTheme.accent(station).opacity(0.35), radius: 6, y: 2)
    }
}

// MARK: - Progress bar for order completion

struct KDSProgressHeaderBar: View {
    let completedCount: Int
    let totalCount: Int
    let station: KDSStation

    private var progress: Double {
        guard totalCount > 0 else { return 1.0 }
        return min(1.0, max(0.0, Double(completedCount) / Double(totalCount)))
    }

    private var isAllCompleted: Bool {
        totalCount > 0 && completedCount >= totalCount
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: isAllCompleted ? "checkmark.circle.fill" : "timer")
                        .font(.system(size: 11, weight: .bold))
                    Text(isAllCompleted
                         ? "kds_all_station_completed".t
                         : "\(completedCount)/\(totalCount) " + "kds_items_ready_count".t)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(isAllCompleted ? Color(hex: "10B981") : .textSecondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(isAllCompleted ? Color(hex: "10B981") : KDSStationTheme.accent(station))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.appSurface.opacity(0.7))
                        .frame(height: 6)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isAllCompleted
                                    ? [Color(hex: "10B981"), Color(hex: "059669")]
                                    : [KDSStationTheme.accent(station), Color.appTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Detail header

struct KDSOrderDetailHeader: View {
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    let ticket: KDSTicket
    var completedCount: Int = 0
    var totalCount: Int = 0
    let onClose: () -> Void

    private var order: Order { ticket.order }
    private var station: KDSStation { ticket.station }
    private var identity: OrderDisplayIdentity {
        OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
    }

    var body: some View {
        VStack(spacing: APSpacing.md) {
            HStack(alignment: .center, spacing: APSpacing.md) {
                // Queue-first in Quick Service; table-first in Table Service.
                HStack(spacing: APSpacing.sm) {
                    Text(identity.primaryLabel)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.textPrimary)

                    KDSStationBadge(station: station)
                }

                // Order metadata
                HStack(spacing: 8) {
                    Text(identity.orderLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.appSurface)
                        )

                    KDSMetaChip(
                        title: order.orderType == "dine_in" ? "pos_dine_in".t : "pos_take_out".t,
                        icon: order.orderType == "dine_in" ? "fork.knife" : "bag.fill",
                        tint: order.orderType == "dine_in" ? Color(hex: "3B82F6") : Color(hex: "8B5CF6")
                    )
                }

                Spacer(minLength: APSpacing.sm)

                // Timer badge
                KDSElapsedTimerBadge(startDate: order.createdAt)

                // Close button
                Button(action: {
                    APHaptic.trigger()
                    onClose()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color.appSurface)
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(KDSPressScaleStyle())
                .accessibilityLabel("close_btn".t)
            }

            // Progress bar
            if totalCount > 0 {
                KDSProgressHeaderBar(
                    completedCount: completedCount,
                    totalCount: totalCount,
                    station: station
                )
            }
        }
        .padding(.horizontal, APSpacing.lg)
        .padding(.vertical, APSpacing.md)
        .background(
            KDSStationTheme.headerGradient(station)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appDivider.opacity(0.8))
                .frame(height: 1)
        }
    }
}

// MARK: - Modifier tag chip

struct KDSModifierTagChip: View {
    let text: String
    var isDone: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDone ? .textTertiary : Color(hex: "0284C7"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDone ? Color.appSurfaceHigh.opacity(0.3) : Color(hex: "0284C7").opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDone ? Color.clear : Color(hex: "0284C7").opacity(0.25), lineWidth: 0.8)
        )
    }
}

// MARK: - Item row card

struct KDSOrderDetailItemCard: View {
    let item: OrderItem
    let station: KDSStation
    let canManageKitchen: Bool
    let onReady: () -> Void
    let onAlert: () -> Void
    let onCancel: () -> Void
    let onRecall: () -> Void

    @State private var appeared = false

    private var isDone: Bool {
        item.status == "served" || item.status == "cancelled"
    }

    private var isAlert: Bool { item.status == "alert" }

    var body: some View {
        HStack(alignment: .center, spacing: APSpacing.md) {
            // Quantity Box
            quantityBadge

            // Details
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.menuItem?.name ?? item.itemName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(isDone ? .textTertiary : .textPrimary)
                        .strikethrough(isDone)
                        .fixedSize(horizontal: false, vertical: true)

                    if item.status == "served" {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("kds_item_ready_badge".t)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "10B981"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(hex: "10B981").opacity(0.12))
                        )
                    }
                }

                // Modifiers
                if !item.modifiers.isEmpty {
                    KDSModifiersLayout(modifiers: item.modifiers.compactMap { $0.modifier?.name }, isDone: isDone)
                }

                // Notes callout
                if let notes = item.notes, !notes.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11, weight: .bold))
                        Text(notes)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "818CF8"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hex: "818CF8").opacity(0.12))
                    )
                }

                statusFooter
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Buttons
            actionRow
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 12)
        .background(
            glassCardBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(borderColor, lineWidth: isAlert ? 2 : 1)
        )
        .shadow(
            color: isAlert
                ? Color.appRose.opacity(0.25)
                : (isDone ? .clear : Color.black.opacity(0.08)),
            radius: 8,
            y: 3
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: item.status)
    }

    private var quantityBadge: some View {
        Text("\(item.quantity)×")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundColor(
                isAlert ? Color.appRose : (isDone ? .textTertiary : Color.white)
            )
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(
                        isAlert
                            ? LinearGradient(colors: [Color.appRose.opacity(0.2), Color.appRose.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                            : (isDone
                               ? LinearGradient(colors: [Color.appSurfaceHigh.opacity(0.5), Color.appSurfaceHigh.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                               : LinearGradient(colors: [KDSStationTheme.accent(station), KDSStationTheme.accent(station).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(
                        isAlert ? Color.appRose.opacity(0.5) : (isDone ? Color.appBorderSubtle : Color.white.opacity(0.2)),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isDone ? .clear : KDSStationTheme.accent(station).opacity(0.25),
                radius: 4,
                y: 2
            )
    }

    @ViewBuilder
    private var statusFooter: some View {
        if item.status == "served" {
            if let servedBy = item.servedBy, !servedBy.isEmpty {
                Label(LocalizationManager.shared.t("kds_served_by_template", servedBy), systemImage: "person.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
        } else if item.status == "cancelled" {
            Text("kds_item_cancelled_badge".t)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appRose)
        } else if isAlert {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("kds_staff_alerted".t)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(Color(hex: "F59E0B"))
            .symbolEffect(.pulse, options: .repeating)
        }
    }

    private var borderColor: Color {
        if isAlert { return Color.appRose.opacity(0.7) }
        if isDone { return Color.appBorderSubtle.opacity(0.4) }
        return Color.appBorderSubtle
    }

    @ViewBuilder
    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
            .fill(isDone ? Color.appSurface.opacity(0.4) : Color.appSurface)
    }

    @ViewBuilder
    private var actionRow: some View {
        if isDone {
            KDSIconActionButton(
                title: "pos_recall".t,
                icon: "arrow.uturn.backward",
                role: .neutral,
                action: onRecall
            )
        } else {
            HStack(spacing: 8) {
                // Alert button
                KDSIconActionButton(
                    title: "kds_alert_staff".t,
                    icon: "bell.fill",
                    role: .warning,
                    disabled: isAlert,
                    action: onAlert
                )

                // Cancel button (manager only)
                if canManageKitchen {
                    KDSIconActionButton(
                        title: "cancel".t,
                        icon: "xmark",
                        role: .destructive,
                        action: onCancel
                    )
                }

                // Ready button
                KDSIconActionButton(
                    title: "kds_mark_item_ready".t,
                    icon: "checkmark",
                    role: .success,
                    action: onReady
                )
            }
        }
    }
}

// Simple modifier list wrapper
struct KDSModifiersLayout: View {
    let modifiers: [String]
    var isDone: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modifiers, id: \.self) { mod in
                KDSModifierTagChip(text: mod, isDone: isDone)
            }
        }
    }
}

// MARK: - Order summary strip

struct KDSOrderSummaryStrip: View {
    let itemCount: Int
    let totalQuantity: Int
    let orderTime: Date
    var actorName: String? = nil

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: orderTime)
    }

    var body: some View {
        HStack(spacing: APSpacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("\(itemCount) " + "kds_items_summary".t + " (\(totalQuantity) " + "unit_pieces".t + ")")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.textSecondary)

            Circle()
                .fill(Color.appDivider)
                .frame(width: 4, height: 4)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .bold))
                Text("order_time_at".t + " \(timeString) " + "time_unit_hour_short".t)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.textTertiary)

            Spacer()

            if let actorName, !actorName.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(actorName)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.appSurfaceHigh)
                )
            }
        }
        .padding(.horizontal, APSpacing.lg)
        .padding(.vertical, 10)
        .background(Color.appSurface.opacity(0.6))
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Action Button Roles & Style

enum KDSIconActionRole {
    case success, warning, destructive, neutral

    var tint: Color {
        switch self {
        case .success: return Color(hex: "10B981")
        case .warning: return Color(hex: "F59E0B")
        case .destructive: return Color(hex: "EF4444")
        case .neutral: return Color.appAccent
        }
    }

    var backgroundGradient: LinearGradient {
        switch self {
        case .success:
            return LinearGradient(
                colors: [Color(hex: "10B981"), Color(hex: "059669")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warning:
            return LinearGradient(
                colors: [Color(hex: "F59E0B").opacity(0.18), Color(hex: "D97706").opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .destructive:
            return LinearGradient(
                colors: [Color(hex: "EF4444").opacity(0.18), Color(hex: "DC2626").opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .neutral:
            return LinearGradient(
                colors: [Color.appAccent.opacity(0.18), Color.appAccent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct KDSIconActionButton: View {
    let title: String
    let icon: String
    var role: KDSIconActionRole = .neutral
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            APHaptic.trigger()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: role == .success ? 16 : 14, weight: .bold))
                .foregroundColor(role == .success ? .white : (disabled ? role.tint.opacity(0.35) : role.tint))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(role == .success ? AnyShapeStyle(role.backgroundGradient) : AnyShapeStyle(role.tint.opacity(disabled ? 0.04 : 0.12)))
                )
                .overlay(
                    Circle()
                        .stroke(role == .success ? Color.white.opacity(0.2) : role.tint.opacity(disabled ? 0.08 : 0.3), lineWidth: 1)
                )
                .shadow(color: role == .success ? role.tint.opacity(0.35) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(KDSPressScaleStyle(scale: 0.92))
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

struct KDSPrimaryFooterButton: View {
    let title: String
    var badgeCount: Int? = nil
    var systemImage: String? = nil
    var gradient: LinearGradient = LinearGradient(
        colors: [Color(hex: "10B981"), Color(hex: "059669")],
        startPoint: .leading,
        endPoint: .trailing
    )
    let action: () -> Void

    var body: some View {
        Button(action: {
            APHaptic.trigger()
            action()
        }) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 18, weight: .heavy))

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "059669"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white)
                        )
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color(hex: "059669").opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(KDSPressScaleStyle(scale: 0.98))
    }
}

struct KDSPressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
