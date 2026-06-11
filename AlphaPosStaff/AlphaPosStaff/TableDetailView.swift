import SwiftUI

struct TableDetailView: View {
    let table: RestaurantTable
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var showingAddItemsSheet = false
    @State private var selectedCategory = "all"
    
    // Catalog selection cart
    @State private var cartItems: [MenuItem: Int] = [:]
    
    @Environment(\.dismiss) private var dismiss

    private var currentTable: RestaurantTable {
        NetworkService.shared.tables.first(where: { $0.tableNumber == table.tableNumber }) ?? table
    }

    private var isAllServed: Bool {
        if !NetworkService.shared.kitchenWorkflowRequired { return true }
        guard !orders.isEmpty else { return false }
        for order in orders {
            if order.status == "cancelled" { continue }
            for item in order.items {
                if item.status != "served" {
                    return false
                }
            }
        }
        return true
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Info Banner
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("session_orders".localized(for: appLanguage))
                            .font(.caption).foregroundColor(.textSecondary)
                        Text(String(format: "table_guests_count_format".localized(for: appLanguage), currentTable.tableNumber, currentTable.guestCount))
                            .font(.headline).fontWeight(.bold).foregroundColor(.textPrimary)
                    }
                    Spacer()
                    
                    APBadge(text: "active".localized(for: appLanguage), color: .appRose)
                }
                .padding()
                .background(Color.appSurface)
                
                Divider().background(Color.appDivider)
                
                if isLoading {
                    ProgressView().tint(.appAccent).frame(maxHeight: .infinity)
                } else if orders.isEmpty {
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 48)).foregroundColor(.textTertiary)
                        Text("no_orders_placed".localized(for: appLanguage))
                            .font(.headline).foregroundColor(.textSecondary)
                        
                        Button(action: {
                            cartItems.removeAll()
                            showingAddItemsSheet = true
                        }) {
                            Label("order_food".localized(for: appLanguage), systemImage: "plus")
                                .apGradientButton(gradient: APGradient.accent)
                        }
                        .frame(maxWidth: 200)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(orders) { order in
                            Section(header:
                                HStack {
                                    Text(order.orderNumber)
                                        .font(.subheadline).fontWeight(.black)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    let isOrderAllServed = !order.items.isEmpty && order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
                                    let statusToShow = isOrderAllServed ? "served" : order.status
                                    APBadge(text: statusToShow.localized(for: appLanguage).capitalized, color: statusColor(for: statusToShow))
                                }
                                .padding(.vertical, 4)
                            ) {
                                ForEach(order.items) { item in
                                    HStack {
                                        Text("\(item.quantity)x \(item.name)")
                                            .font(.subheadline)
                                            .foregroundColor(.textPrimary)
                                        
                                        Spacer()
                                        
                                        Text("฿\(Int(item.price * Double(item.quantity)))")
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.vertical, 2)
                                    .listRowBackground(Color.appSurface)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteItem(item, from: order)
                                        } label: {
                                            Label("delete".localized(for: appLanguage), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                }
                
                // Bottom CTAs
                VStack(spacing: APSpacing.md) {
                    HStack(spacing: APSpacing.md) {
                        Button(action: {
                            cartItems.removeAll()
                            showingAddItemsSheet = true
                        }) {
                            Label("add_food".localized(for: appLanguage), systemImage: "plus")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, APSpacing.md)
                                .background(Color.appSurfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                                .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        }
                        
                        if !orders.isEmpty {
                            if isAllServed {
                                NavigationLink(destination: BillingView(table: currentTable, orders: orders)) {
                                    Label("bill_payment".localized(for: appLanguage), systemImage: "creditcard.fill")
                                        .apGradientButton(gradient: APGradient.destructive)
                                }
                            } else {
                                Button(action: {
                                    APHaptic.trigger()
                                }) {
                                    Label("bill_payment".localized(for: appLanguage), systemImage: "creditcard.fill")
                                        .apGradientButton(gradient: APGradient.destructive, disabled: true)
                                }
                                .disabled(true)
                                
                                Text("All items must be served before checkout")
                                    .font(.caption2)
                                    .foregroundColor(.appRose)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.appSurface)
            }
        }
        .navigationTitle("table_details_title".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadOrders()
        }
        .sheet(isPresented: $showingAddItemsSheet) {
            addItemSheetView()
                .apColorScheme()
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "preparing": return .appAmber
        case "ready": return .appTeal
        case "served": return .appAccent
        case "completed": return .appTeal
        default: return .textSecondary
        }
    }
    
    private func loadOrders() {
        isLoading = true
        Task {
            // Refresh tables/sessions first to ensure we have the latest session token from the server
            await NetworkService.shared.refreshAll()
            
            guard let token = currentTable.sessionToken else {
                await MainActor.run {
                    self.orders = []
                    self.isLoading = false
                }
                return
            }
            
            do {
                let list = try await NetworkService.shared.fetchTableOrders(tableNumber: currentTable.tableNumber, sessionToken: token)
                await MainActor.run {
                    self.orders = list
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteItem(_ item: OrderItem, from order: Order) {
        APHaptic.trigger()
        Task {
            isLoading = true
            do {
                let success = try await NetworkService.shared.deleteOrderItem(itemId: item.id)
                if success {
                    loadOrders()
                } else {
                    isLoading = false
                }
            } catch {
                isLoading = false
            }
        }
    }
    
    // MARK: - Add Items Catalog Sheet
    
    private func addItemSheetView() -> some View {
        let categories = ["all", "appetizers", "mains", "drinks", "desserts"]
        let items = NetworkService.shared.menuItems
        let filteredItems = selectedCategory == "all" ? items : items.filter { $0.category == selectedCategory }
        
        return NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Category pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: APSpacing.sm) {
                            ForEach(categories, id: \.self) { cat in
                                Button(action: {
                                    selectedCategory = cat
                                }) {
                                    Text(cat.localized(for: appLanguage).capitalized)
                                        .apChip(selected: selectedCategory == cat)
                                }
                            }
                        }
                        .padding()
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: APSpacing.sm) {
                            ForEach(filteredItems) { menuItem in
                                HStack(spacing: 12) {
                                    // Styled Product Image Box
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.appSurfaceHigh)
                                            .frame(width: 60, height: 60)
                                        
                                        if let imageUrl = menuItem.image_url, let url = URL(string: imageUrl) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                case .failure(_), .empty:
                                                    Text(menuItem.emoji ?? "🍔")
                                                        .font(.system(size: 30))
                                                @unknown default:
                                                    Text(menuItem.emoji ?? "🍔")
                                                        .font(.system(size: 30))
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        } else {
                                            Text(menuItem.emoji ?? "🍔")
                                                .font(.system(size: 30))
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(menuItem.name)
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                        
                                        Text(menuItem.desc ?? "")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(2)
                                        
                                        Text("฿\(Int(menuItem.price))")
                                            .font(.subheadline).fontWeight(.bold)
                                            .foregroundColor(.appAccent)
                                    }
                                    
                                    Spacer()
                                    
                                    // Quantity selector
                                    let qty = cartItems[menuItem] ?? 0
                                    if qty > 0 {
                                        HStack(spacing: APSpacing.md) {
                                            Button(action: {
                                                cartItems[menuItem] = qty - 1
                                            }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.title2).foregroundColor(.textSecondary)
                                            }
                                            
                                            Text("\(qty)")
                                                .font(.headline).foregroundColor(.textPrimary)
                                            
                                            Button(action: {
                                                cartItems[menuItem] = qty + 1
                                            }) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.title2).foregroundColor(.appAccent)
                                            }
                                        }
                                    } else {
                                        Button(action: {
                                            cartItems[menuItem] = 1
                                        }) {
                                            Text("add_button".localized(for: appLanguage))
                                                .font(.caption).fontWeight(.bold)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.appSurfaceHigh)
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                                        }
                                    }
                                }
                                .apCard()
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, APSpacing.xl)
                    }
                    
                    // Save Button
                    let cartTotal = cartItems.values.reduce(0, +)
                    if cartTotal > 0 {
                        Button(action: {
                            submitOrder()
                        }) {
                            Text(String(format: "submit_order_items_format".localized(for: appLanguage), cartTotal))
                                .apGradientButton(gradient: APGradient.positive)
                        }
                        .padding()
                        .background(Color.appSurface)
                    }
                }
            }
            .navigationTitle("add_items_title".localized(for: appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized(for: appLanguage)) {
                        showingAddItemsSheet = false
                    }
                }
            }
        }
    }
    
    private func submitOrder() {
        showingAddItemsSheet = false
        isLoading = true
        
        let orderId = UUID().uuidString
        let orderNumber = "ORD-\(String(UUID().int ?? 0).prefix(4))"

        let itemsPayload = cartItems.filter { $0.value > 0 }.map { item, qty in
            return [
                "id": UUID().uuidString,
                "name": item.name,
                "quantity": qty,
                "price": item.price,
                "status": "cooking",
                "item_id": item.id
            ] as [String : Any]
        }
        
        let total = cartItems.map { $0.key.price * Double($0.value) }.reduce(0, +)
        
        Task {
            do {
                _ = try await NetworkService.shared.uploadOrder(
                    orderId: orderId,
                    orderNumber: orderNumber,
                    tableNumber: currentTable.tableNumber,
                    total: total,
                    items: itemsPayload,
                    sessionToken: currentTable.sessionToken,
                    guestCount: currentTable.guestCount
                )
                await MainActor.run {
                    loadOrders()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

extension UUID {
    var int: Int? {
        let clean = self.uuidString.replacingOccurrences(of: "-", with: "")
        let prefix = String(clean.prefix(8))
        return Int(prefix, radix: 16)
    }
}
