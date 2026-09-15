import SwiftUI

/// Navigation guard shared by POS entry points.
/// Leaving POS is blocked while a cashier has an unsaved cart.
struct POSNavigationHandlers: ViewModifier {
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var showUnsavedCartAlert: Bool
    let hasUnsavedCart: Bool

    func body(content: Content) -> some View {
        content.onChange(of: selectedTab) { _, newValue in
            guard newValue != .pos, hasUnsavedCart else { return }
            selectedTab = .pos
            showUnsavedCartAlert = true
        }
    }
}
