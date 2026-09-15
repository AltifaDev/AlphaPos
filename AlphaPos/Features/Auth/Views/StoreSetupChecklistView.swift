import SwiftData
import SwiftUI

/// Dashboard card for progressive store setup after fast onboarding.
struct StoreSetupChecklistView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    let items: [StoreSetupChecklist.Item]
    var onSelect: (StoreSetupChecklist.Item) -> Void
    var onDismiss: () -> Void
    var onSkipProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("setup_checklist_title".t)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("setup_checklist_subtitle".t)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("cancel_btn".t)
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(itemIconColor(for: item))
                                .frame(width: 36, height: 36)
                                .background(itemIconColor(for: item).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.titleKey.t)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(item.dynamicSubtitle())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(itemSubtitleColor(for: item))
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 4)

                            if item == .shopProfile {
                                Button("setup_checklist_skip".t) {
                                    onSkipProfile()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textTertiary)
                                .buttonStyle(.plain)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(12)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.appDivider.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.appSurfaceHigh.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "2D71F8").opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
    }

    private func itemIconColor(for item: StoreSetupChecklist.Item) -> Color {
        guard item == .activatePlan else { return Color(hex: "2D71F8") }
        if StoreSetupChecklist.isTrialExpired {
            return Color(hex: "FF453A")
        }
        if let days = StoreSetupChecklist.remainingTrialDays, days <= 3 {
            return Color(hex: "FF9F0A")
        }
        return Color(hex: "2D71F8")
    }

    private func itemSubtitleColor(for item: StoreSetupChecklist.Item) -> Color {
        guard item == .activatePlan else { return .textSecondary }
        if StoreSetupChecklist.isTrialExpired {
            return Color(hex: "FF453A")
        }
        if let days = StoreSetupChecklist.remainingTrialDays, days <= 3 {
            return Color(hex: "FF9F0A")
        }
        return .textSecondary
    }
}
