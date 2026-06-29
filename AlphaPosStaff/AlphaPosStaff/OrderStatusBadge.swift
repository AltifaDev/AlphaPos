// OrderStatusBadge.swift
// AlphaPosStaff — Reusable pill-shaped status badge for orders
// Color-coded by status: pending=orange, preparing=blue, ready=green, served=gray, cancelled=red

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OrderStatusBadge
// ─────────────────────────────────────────────────────────────────────────────

struct OrderStatusBadge: View {
    let status: String
    var size: BadgeSize = .medium
    var lang: String = "en"
    
    enum BadgeSize {
        case small   // for item-level (10pt font)
        case medium  // for order list rows (11pt font)
        case large   // for detail headers (13pt font)
        
        var fontSize: CGFloat {
            switch self {
            case .small:  return 9
            case .medium: return 10
            case .large:  return 12
            }
        }
        
        var paddingH: CGFloat {
            switch self {
            case .small:  return 6
            case .medium: return 9
            case .large:  return 12
            }
        }
        
        var paddingV: CGFloat {
            switch self {
            case .small:  return 2
            case .medium: return 3
            case .large:  return 5
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small:  return 8
            case .medium: return 9
            case .large:  return 11
            }
        }
    }
    
    private var config: (label: String, icon: String, fg: Color, bg: Color) {
        switch status.lowercased() {
        // Order-level statuses
        case "pending", "placed":
            return ("status_pending".localized(for: lang), "clock.fill", Color.appAmber, Color.appAmber.opacity(0.12))
        case "confirmed":
            return ("status_confirmed".localized(for: lang), "checkmark.circle.fill", Color.appIndigo, Color.appIndigo.opacity(0.12))
        case "preparing", "cooking":
            return ("status_preparing".localized(for: lang), "flame.fill", Color.appAccent, Color.appAccent.opacity(0.12))
        case "ready":
            return ("status_ready".localized(for: lang), "bell.fill", Color.appGreen, Color.appGreen.opacity(0.12))
        case "served":
            return ("status_served".localized(for: lang), "checkmark.seal.fill", Color.textSecondary, Color.appSurfaceHigh)
        case "completed":
            return ("status_completed".localized(for: lang), "creditcard.fill", Color.appGreen, Color.appGreen.opacity(0.10))
        case "cancelled":
            return ("status_cancelled".localized(for: lang), "xmark.circle.fill", Color.appRose, Color.appRose.opacity(0.12))
        // Item-level statuses
        case "cooking_item", "in_progress":
            return ("status_cooking".localized(for: lang), "flame.fill", Color.appAccent, Color.appAccent.opacity(0.12))
        case "queued":
            return ("status_queued".localized(for: lang), "tray.fill", Color.appAmber, Color.appAmber.opacity(0.12))
        default:
            return (status.capitalized, "circle.fill", Color.textSecondary, Color.appSurfaceHigh)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: config.icon)
                .font(.system(size: size.iconSize, weight: .bold))
            Text(config.label)
                .font(.system(size: size.fontSize, weight: .bold))
        }
        .foregroundColor(config.fg)
        .padding(.horizontal, size.paddingH)
        .padding(.vertical, size.paddingV)
        .background(config.bg)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(config.fg.opacity(0.2), lineWidth: 0.5)
        )
        // Accessibility: VoiceOver อ่านสถานะ ไม่อ่านทีละ element
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(config.label)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#Preview("All Statuses") {
    VStack(spacing: 16) {
        Group {
            Text("Small").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                OrderStatusBadge(status: "pending", size: .small)
                OrderStatusBadge(status: "preparing", size: .small)
                OrderStatusBadge(status: "ready", size: .small)
                OrderStatusBadge(status: "served", size: .small)
            }
        }
        
        Group {
            Text("Medium").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                OrderStatusBadge(status: "pending", size: .medium)
                OrderStatusBadge(status: "confirmed", size: .medium)
                OrderStatusBadge(status: "preparing", size: .medium)
                OrderStatusBadge(status: "ready", size: .medium)
            }
            HStack(spacing: 8) {
                OrderStatusBadge(status: "served", size: .medium)
                OrderStatusBadge(status: "completed", size: .medium)
                OrderStatusBadge(status: "cancelled", size: .medium)
            }
        }
        
        Group {
            Text("Large").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                OrderStatusBadge(status: "preparing", size: .large)
                OrderStatusBadge(status: "ready", size: .large)
                OrderStatusBadge(status: "cancelled", size: .large)
            }
        }
    }
    .padding()
    .background(Color.appBackground)
}
