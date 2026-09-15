import SwiftUI

/// Unified workspace for customer retention tools.
/// Customer profiles, loyalty and gift cards share one information architecture
/// while keeping their operational workflows separate and easy to scan.
struct CustomerValueManagementView: View {
    enum Section: String, CaseIterable, Identifiable {
        case customers
        case loyalty
        case giftCards

        var id: String { rawValue }

        var title: String {
            switch self {
            case .customers: return "customers_nav".t
            case .loyalty: return "tab_loyalty".t
            case .giftCards: return "tab_gift_cards".t
            }
        }

        var icon: String {
            switch self {
            case .customers: return "person.2.fill"
            case .loyalty: return "star.circle.fill"
            case .giftCards: return "giftcard.fill"
            }
        }
    }

    @State private var section: Section

    init(initialSection: Section = .customers) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch section {
                case .customers:
                    CustomerCRMView()
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                workspaceHeader
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 5) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { section = item }
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
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
        .padding(3)
        .background(Color.appSurfaceHigh, in: Capsule())
        .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}
