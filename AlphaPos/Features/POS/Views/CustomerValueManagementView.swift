import SwiftUI

/// Unified workspace for customer retention tools.
/// Loyalty and gift cards share one information architecture while keeping
/// their operational workflows separate and easy to scan.
struct CustomerValueManagementView: View {
    enum Section: String, CaseIterable, Identifiable {
        case loyalty
        case giftCards

        var id: String { rawValue }

        var title: String {
            switch self {
            case .loyalty: return "tab_loyalty".t
            case .giftCards: return "tab_gift_cards".t
            }
        }

        var icon: String {
            switch self {
            case .loyalty: return "star.circle.fill"
            case .giftCards: return "giftcard.fill"
            }
        }
    }

    @State private var section: Section

    init(initialSection: Section = .loyalty) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            Group {
                switch section {
                case .loyalty:
                    LoyaltyManagementView(embedded: true)
                case .giftCards:
                    GiftCardManagementView(embedded: true)
                }
            }
            .id(section)
            .transition(.opacity)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("customer_value_title".t)
        .apNavBar(background: Color.appBackground)
    }

    private var workspaceHeader: some View {
        HStack(spacing: APSpacing.lg) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(APGradient.accent)
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("customer_value_title".t)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("customer_value_subtitle".t)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer(minLength: APSpacing.lg)

            HStack(spacing: 5) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { section = item }
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .foregroundStyle(section == item ? Color.white : Color.textSecondary)
                            .background {
                                if section == item {
                                    Capsule().fill(Color.appAccent)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(5)
            .background(Color.appSurfaceHigh, in: Capsule())
            .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
        }
        .padding(.horizontal, APSpacing.lg)
        .padding(.vertical, 14)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) { Divider().background(Color.appDivider) }
    }
}
