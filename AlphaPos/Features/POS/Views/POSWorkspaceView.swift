import SwiftUI

/// Presentation shell for the POS workspace.
///
/// The POS state stays owned by `POSView`; this component only decides which
/// workspace state to render and lays out the menu and cart rails. Keeping the
/// branches here prevents the root `POSView.body` expression from growing with
/// every POS feature.
struct POSWorkspaceView<MenuContent: View, CartContent: View, EmptyContent: View, TableContent: View, HeaderContent: View>: View {
    let hasLoadedCatalog: Bool
    let hasCatalogItems: Bool
    let requiresTable: Bool
    let menuContent: () -> MenuContent
    let cartContent: () -> CartContent
    let emptyContent: () -> EmptyContent
    let tableContent: () -> TableContent
    let headerContent: () -> HeaderContent

    init(
        hasLoadedCatalog: Bool,
        hasCatalogItems: Bool,
        requiresTable: Bool,
        @ViewBuilder menuContent: @escaping () -> MenuContent,
        @ViewBuilder cartContent: @escaping () -> CartContent,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        @ViewBuilder tableContent: @escaping () -> TableContent,
        @ViewBuilder headerContent: @escaping () -> HeaderContent
    ) {
        self.hasLoadedCatalog = hasLoadedCatalog
        self.hasCatalogItems = hasCatalogItems
        self.requiresTable = requiresTable
        self.menuContent = menuContent
        self.cartContent = cartContent
        self.emptyContent = emptyContent
        self.tableContent = tableContent
        self.headerContent = headerContent
    }

    var body: some View {
        ZStack {
            POSReferencePalette.background.ignoresSafeArea()

            if hasLoadedCatalog && !hasCatalogItems {
                emptyContent()
            } else if requiresTable {
                tableContent()
            } else {
                VStack(spacing: 0) {
                    headerContent()
                    HStack(spacing: 0) {
                        menuContent()
                        cartContent()
                    }
                }
            }
        }
    }
}
