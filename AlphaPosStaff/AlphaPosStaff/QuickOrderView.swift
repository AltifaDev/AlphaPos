// QuickOrderView.swift
// AlphaPosStaff — Quick Order Mode (Takeaway / Delivery / Walk-in)
// สั่งออเดอร์โดยไม่ต้องเปิดโต๊ะ

import SwiftUI

struct QuickOrderView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_name") private var staffName = ""
    
    @State private var networkService = NetworkService.shared
    @State private var menuItems: [MenuItem] = []
    @State private var cartItems: [MenuItem: Int] = [:]
    @State private var selectedOrderType: OrderType = .takeaway
    @State private var selectedCategory = "all"
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var submittedQueueNumber = ""
    @State private var submittedOrderId = ""
    @State private var showOrderTimeline = false
    @State private var showPaymentSheet = false
    @State private var searchText = ""
    @State private var submitError: String? = nil
    @State private var showSplitBill = false
    @State private var showSubmitConfirm = false
    
    // Filter & Sorting State
    @State private var showFilterSheet = false
    @State private var filterSortBy: SortOption = .none
    @State private var filterMinPrice = ""
    @State private var filterMaxPrice = ""
    @State private var filterFavoritesOnly = false
    
    // Persistent Favorites
    @AppStorage("favorite_menu_item_ids") private var favoriteItemIdsData: Data = Data()
    
    private var favoriteItemIds: Set<String> {
        get {
            let decoded = try? JSONDecoder().decode(Set<String>.self, from: favoriteItemIdsData)
            return decoded ?? []
        }
        nonmutating set {
            let encoded = try? JSONEncoder().encode(newValue)
            favoriteItemIdsData = encoded ?? Data()
        }
    }
    
    enum SortOption: String, CaseIterable {
        case none = "sort_none"
        case priceLowHigh = "price_low_high"
        case priceHighLow = "price_high_low"
        case nameAZ = "name_a_z"
        case nameZA = "name_z_a"
        
        var displayKey: String { rawValue }
    }
    
    enum OrderType: String, CaseIterable {
        case takeaway = "take_out"
        case delivery = "delivery"
        case walkIn = "dine_in"
        
        var displayKey: String {
            switch self {
            case .takeaway: return "takeaway"
            case .delivery: return "delivery"
            case .walkIn: return "walk_in"
            }
        }
        
        var icon: String {
            switch self {
            case .takeaway: return "bag.fill"
            case .delivery: return "bicycle"
            case .walkIn: return "figure.walk"
            }
        }
        
        var color: Color {
            switch self {
            case .takeaway: return Color.appTeal
            case .delivery: return Color.appAccent
            case .walkIn:   return Color.appAmber
            }
        }
    }
    
    private var categories: [String] {
        let cats = Set(menuItems.map { $0.category })
        return ["all"] + cats.sorted()
    }
    
    private var filteredMenu: [MenuItem] {
        var items = menuItems
        if selectedCategory != "all" {
            items = items.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if filterFavoritesOnly {
            items = items.filter { favoriteItemIds.contains($0.id) }
        }
        if let minVal = Double(filterMinPrice), minVal > 0 {
            items = items.filter { $0.price >= minVal }
        }
        if let maxVal = Double(filterMaxPrice), maxVal > 0 {
            items = items.filter { $0.price <= maxVal }
        }
        
        switch filterSortBy {
        case .none:
            break
        case .priceLowHigh:
            items.sort { $0.price < $1.price }
        case .priceHighLow:
            items.sort { $0.price > $1.price }
        case .nameAZ:
            items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameZA:
            items.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        }
        
        return items
    }
    
    private var isFilterActive: Bool {
        filterSortBy != .none || !filterMinPrice.isEmpty || !filterMaxPrice.isEmpty || filterFavoritesOnly
    }
    
    private var cartCount: Int {
        cartItems.values.reduce(0, +)
    }
    
    private var cartTotal: Double {
        cartItems.reduce(0.0) { $0 + (Double($1.value) * $1.key.price) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if showSuccess {
                    successOverlay
                } else {
                    VStack(spacing: 0) {
                        // Order type selector
                        orderTypeSelector
                        
                        Divider().background(Color.appDivider)
                        
                        // Menu + Cart
                        if isLoading {
                            Spacer()
                            ProgressView()
                                .tint(.appAccent)
                            Spacer()
                        } else {
                            menuSection
                        }
                        
                        // Cart summary bar
                        if cartCount > 0 {
                            cartBar
                        }
                    }
                }
            }
            .navigationTitle("quick_order".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadMenu()
            }
            .sheet(isPresented: $showPaymentSheet) {
                PaymentMethodSheet(
                    total: cartTotal,
                    orderType: selectedOrderType,
                    onPay: { method in
                        showPaymentSheet = false
                        submitOrder(paymentMethod: method)
                    },
                    onPayLater: {
                        showPaymentSheet = false
                        submitOrder(paymentMethod: nil)
                    },
                    appLanguage: appLanguage
                )
            }
            .sheet(isPresented: $showOrderTimeline) {
                OrderTimelineView(
                    order: Order(
                        id: submittedOrderId,
                        orderNumber: submittedQueueNumber.isEmpty ? "QO-0000" : submittedQueueNumber,
                        tableNumber: "QUICK",
                        total: cartTotal,
                        status: "preparing",
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        items: cartItems.map { (menuItem, qty) in
                            OrderItem(id: UUID().uuidString, name: menuItem.name, quantity: qty, price: menuItem.price, status: "cooking", item_id: menuItem.id, notes: nil, servedBy: nil)
                        },
                        sessionToken: nil
                    )
                )
            }
            .sheet(isPresented: $showSplitBill) {
                SplitBillView(
                    orderId: submittedOrderId,
                    orderItems: cartItems.map { (menuItem, qty) in
                        OrderItem(id: UUID().uuidString, name: menuItem.name, quantity: qty, price: menuItem.price, status: "cooking", item_id: menuItem.id, notes: nil, servedBy: nil)
                    },
                    totalAmount: cartTotal
                )
            }
            .sheet(isPresented: $showFilterSheet) {
                MenuFilterSheet(
                    sortBy: $filterSortBy,
                    minPrice: $filterMinPrice,
                    maxPrice: $filterMaxPrice,
                    favoritesOnly: $filterFavoritesOnly,
                    appLanguage: appLanguage
                )
            }
            .alert("submit_order_failed".localized(for: appLanguage),
                   isPresented: Binding(get: { submitError != nil }, set: { if !$0 { submitError = nil } })) {
                Button("ok".localized(for: appLanguage), role: .cancel) { submitError = nil }
            } message: {
                if let err = submitError {
                    Text(err)
                }
            }
            .confirmationDialog(
                "confirm".localized(for: appLanguage),
                isPresented: $showSubmitConfirm,
                titleVisibility: .visible
            ) {
                Button("select_payment".localized(for: appLanguage)) {
                    showPaymentSheet = true
                }
                Button("cancel".localized(for: appLanguage), role: .cancel) {}
            } message: {
                let itemCount = cartCount
                let total = cartTotal
                Text("\(selectedOrderType.displayKey.localized(for: appLanguage)) · \(itemCount) \("items_label".localized(for: appLanguage)) · ฿\(String(format: "%.0f", total))")
            }
        }
    }
    
    // MARK: - Order Type Selector
    
    private var orderTypeSelector: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(OrderType.allCases, id: \.rawValue) { type in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedOrderType = type
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 13, weight: .bold))
                            Text(type.displayKey.localized(for: appLanguage).localized(for: appLanguage).capitalized)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedOrderType == type
                                ? type.color.opacity(0.12)
                                : Color.appSurface
                        )
                        .foregroundColor(
                            selectedOrderType == type ? type.color : .textSecondary
                        )
                        .cornerRadius(14)
                        .shadow(color: selectedOrderType == type ? type.color.opacity(0.1) : Color.black.opacity(0.01), radius: 5, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedOrderType == type ? type.color.opacity(0.3) : Color.appDivider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }
    
    // MARK: - Menu Section
    
    private var menuSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 16, weight: .medium))
                    TextField("search_menu".localized(for: appLanguage), text: $searchText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.textPrimary)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textTertiary)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.appSurface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appDivider, lineWidth: 1)
                )
                
                // Filter Button with Active State Badge
                Button(action: {
                    showFilterSheet = true
                    APHaptic.trigger()
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isFilterActive ? .white : .brandGreenDark)
                            .padding(12)
                            .background(isFilterActive ? Color.brandGreenDark : Color.brandGreenLight.opacity(0.5))
                            .cornerRadius(16)
                        
                        if isFilterActive {
                            Circle()
                                .fill(Color.appRose)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedCategory = cat }
                        } label: {
                            Text(cat == "all" ? "all_categories".localized(for: appLanguage) : cat.capitalized)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedCategory == cat ? Color.brandGreenDark : Color.appSurface)
                                .foregroundColor(selectedCategory == cat ? .white : .textSecondary)
                                .cornerRadius(20)
                                .shadow(color: selectedCategory == cat ? Color.brandGreenDark.opacity(0.2) : Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedCategory == cat ? Color.clear : Color.appDivider, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            
            // Menu items list using modern Grid layout
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 14)], spacing: 14) {
                    ForEach(filteredMenu) { item in
                        menuItemCard(item)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, cartCount > 0 ? 100 : 30)
            }
        }
    }
    
    private func menuItemCard(_ item: MenuItem) -> some View {
        let qty = cartItems[item] ?? 0
        
        return VStack(alignment: .leading, spacing: 8) {
            // Card Image/Emoji Section
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.brandGreenMuted)
                    .frame(height: 110)
                
                // Rating Badge (Mock)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                    Text("4.8")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appSurface)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                // Image or Emoji Icon
                if let urlStr = item.image_url, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            // Fallback to emoji on failure
                            Text(item.emoji ?? "🍔")
                                .font(.system(size: 48))
                        case .empty:
                            ProgressView()
                                .tint(.brandGreenDark)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    // Emoji Icon fallback
                    Text(item.emoji ?? "🍔")
                        .font(.system(size: 48))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 10)
                }
                
                // Favorite Button (Functional)
                Button(action: {
                    var current = favoriteItemIds
                    if current.contains(item.id) {
                        current.remove(item.id)
                    } else {
                        current.insert(item.id)
                    }
                    favoriteItemIds = current
                    APHaptic.trigger()
                }) {
                    Image(systemName: favoriteItemIds.contains(item.id) ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(favoriteItemIds.contains(item.id) ? .appRose : .brandGreenDark)
                        .padding(8)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                }
                .padding(8)
            }
            .frame(height: 110)
            
            // Info Section
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                
                Text(item.category.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textSecondary)
                    
                Text(item.desc ?? "Fresh & Handcrafted")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 4)
            
            // Bottom Price and Stepper/Add Row
            HStack {
                Text("฿\(String(format: "%.0f", item.price))")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.brandGreenDark)
                
                Spacer()
                
                // Stepper or Plus Button
                if qty > 0 {
                    HStack(spacing: 8) {
                        Button {
                            if qty == 1 { cartItems.removeValue(forKey: item) }
                            else { cartItems[item] = qty - 1 }
                            APHaptic.trigger()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.brandGreenDark)
                                .clipShape(Circle())
                        }
                        
                        Text("\(qty)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        
                        Button {
                            cartItems[item] = qty + 1
                            APHaptic.trigger()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.brandGreenDark)
                                .clipShape(Circle())
                        }
                    }
                    .padding(3)
                    .background(Color.brandGreenLight.opacity(0.5))
                    .cornerRadius(12)
                } else {
                    Button {
                        cartItems[item] = 1
                        APHaptic.trigger()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.brandGreenDark)
                            .clipShape(Circle())
                            .shadow(color: Color.brandGreenDark.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color.appSurface)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appDivider.opacity(0.5), lineWidth: 1)
        )
    }
    
    // MARK: - Cart Bar
    
    private var cartBar: some View {
        HStack(spacing: 14) {
            // Cart info
            VStack(alignment: .leading, spacing: 2) {
                Text("your_cart".localized(for: appLanguage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                HStack(spacing: 4) {
                    Text("\(cartCount) " + "items_label".localized(for: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("•")
                        .foregroundColor(.textTertiary)
                    Text("฿\(String(format: "%.0f", cartTotal))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appAccent)
                }
            }
            
            Spacer()
            
            // Submit button
            Button {
                // แสดง confirm summary ก่อนไปเลือกวิธีชำระเงิน
                showSubmitConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))
                    Text("submit_order".localized(for: appLanguage))
                        .font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [selectedOrderType.color, selectedOrderType.color.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: selectedOrderType.color.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.appSurface
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -4)
        )
    }
    
    // MARK: - Success Overlay
    
    private var successOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Custom Box Illustration
            BoxIllustrationView(color: Color.brandGreenAccent)
            
            VStack(spacing: 8) {
                Text("order_submitted".localized(for: appLanguage))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Text("Your order has been placed successfully")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            
            // Queue number
            VStack(spacing: 6) {
                Text("queue_number".localized(for: appLanguage).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.brandGreenDark)
                    .tracking(1.5)
                
                Text(submittedQueueNumber)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(Color.brandGreenDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.brandGreenLight.opacity(0.6))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.brandGreenDark.opacity(0.15), lineWidth: 1.5)
            )
            .padding(.horizontal, 40)
            .padding(.top, 10)
            
            // Order type badge
            HStack(spacing: 6) {
                Image(systemName: selectedOrderType.icon)
                    .font(.system(size: 12, weight: .bold))
                Text(selectedOrderType.displayKey.localized(for: appLanguage).capitalized)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(selectedOrderType.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(selectedOrderType.color.opacity(0.1))
            .cornerRadius(20)
            
            Spacer()
            
            VStack(spacing: 12) {
                // Track order button
                Button {
                    showOrderTimeline = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                        Text("track_order".localized(for: appLanguage))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandGreenMuted)
                    .foregroundColor(Color.brandGreenDark)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.brandGreenDark.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Split bill button
                Button {
                    showSplitBill = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1.fill")
                        Text("split_bill".localized(for: appLanguage))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appSurface)
                    .foregroundColor(.appIndigo)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.appIndigo.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // New order button
                Button {
                    withAnimation(.spring()) {
                        showSuccess = false
                        cartItems.removeAll()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("new_order".localized(for: appLanguage))
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandGreenDark)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: Color.brandGreenDark.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
    
    // MARK: - Actions
    
    private func loadMenu() async {
        isLoading = true
        do {
            menuItems = try await NetworkService.shared.fetchMenu()
        } catch {
            print("QuickOrderView: Failed to load menu — \(error)")
        }
        isLoading = false
    }
    
    private func submitOrder(paymentMethod: String?) {
        guard cartCount > 0 else { return }
        isSubmitting = true
        
        let items: [[String: Any]] = cartItems.map { (menuItem, qty) in
            ["id": UUID().uuidString, "name": menuItem.name,
             "itemId": menuItem.id, "quantity": qty, "price": menuItem.price]
        }
        let total = cartTotal
        let orderId = UUID().uuidString
        let queueNum = "Q-\(Int.random(in: 100...999))"
        let orderNumber = "QO-\(Int.random(in: 1000...9999))"
        
        Task {
            do {
                _ = try await NetworkService.shared.uploadOrder(
                    orderId: orderId,
                    orderNumber: orderNumber,
                    tableNumber: "QUICK",
                    total: total,
                    items: items,
                    sessionToken: nil,
                    guestCount: 1,
                    orderType: selectedOrderType.rawValue,
                    queueNumber: queueNum,
                    cashierName: staffName
                )
                
                // Upload payment if method provided
                if let method = paymentMethod {
                    _ = try? await NetworkService.shared.uploadPayment(
                        orderId: orderId,
                        amount: total,
                        method: method
                    )
                }
                
                await MainActor.run {
                    submittedQueueNumber = queueNum
                    submittedOrderId = orderId
                    isSubmitting = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSuccess = true
                    }
                    APHaptic.success()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submitError = "order_submit_error_msg".localized(for: appLanguage) + "\n\(error.localizedDescription)"
                    APHaptic.error()
                }
            }
        }
    }
}

// MARK: - Payment Method Sheet

private struct PaymentMethodSheet: View {
    let total: Double
    let orderType: QuickOrderView.OrderType
    let onPay: (String) -> Void
    let onPayLater: () -> Void
    let appLanguage: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Total
                VStack(spacing: 4) {
                    Text("total_amount".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Text("฿\(String(format: "%.2f", total))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                .padding(.top, 10)
                
                Divider().background(Color.appDivider)
                
                // Payment methods
                VStack(spacing: 12) {
                    Text("pay_now".localized(for: appLanguage))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    paymentButton(icon: "banknote.fill", label: "Cash", color: Color(hex: "10B981"), method: "cash")
                    paymentButton(icon: "creditcard.fill", label: "Card", color: Color(hex: "3B82F6"), method: "credit_card")
                    paymentButton(icon: "qrcode", label: "PromptPay QR", color: Color(hex: "003B71"), method: "qr_promptpay")
                }
                
                Divider().background(Color.appDivider)
                
                // Pay later
                Button {
                    onPayLater()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                        Text("pay_later".localized(for: appLanguage))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appSurface)
                    .foregroundColor(.textSecondary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appDivider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle("select_payment".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
    }
    
    private func paymentButton(icon: String, label: String, color: Color, method: String) -> some View {
        Button {
            onPay(method)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .cornerRadius(8)
                
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct BoxIllustrationView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // Ambient stars/sparkles
            Group {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundColor(color.opacity(0.6))
                    .offset(x: -60, y: -50)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundColor(color.opacity(0.4))
                    .offset(x: 70, y: -20)
                
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(color.opacity(0.3))
                    .offset(x: -50, y: 40)
            }
            
            // Outer Ring
            Circle()
                .stroke(
                    LinearGradient(colors: [color.opacity(0.4), color.opacity(0.01)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                )
                .frame(width: 180, height: 180)
            
            // Inner checkmark & box container
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 54))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .background(Color.brandGreenDark.clipShape(Circle()))
                    .offset(x: 22, y: -22)
            }
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Menu Filter Sheet

struct MenuFilterSheet: View {
    @Binding var sortBy: QuickOrderView.SortOption
    @Binding var minPrice: String
    @Binding var maxPrice: String
    @Binding var favoritesOnly: Bool
    
    let appLanguage: String
    
    @Environment(\.dismiss) private var dismiss
    
    // Temporary states for local selections (Adhering to SwiftUI Form State Checklist)
    @State private var localSortBy: QuickOrderView.SortOption = .none
    @State private var localMinPrice: String = ""
    @State private var localMaxPrice: String = ""
    @State private var localFavoritesOnly: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Sorting section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("sort_by".localized(for: appLanguage).uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .tracking(1.0)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(QuickOrderView.SortOption.allCases, id: \.self) { option in
                                Button {
                                    localSortBy = option
                                    APHaptic.trigger()
                                } label: {
                                    Text(option.displayKey.localized(for: appLanguage))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(localSortBy == option ? Color.brandGreenDark : Color.appSurface)
                                        .foregroundColor(localSortBy == option ? .white : .textSecondary)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(localSortBy == option ? Color.clear : Color.appDivider, lineWidth: 1)
                                        )
                                        .shadow(color: localSortBy == option ? Color.brandGreenDark.opacity(0.15) : Color.clear, radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider().background(Color.appDivider).padding(.horizontal)
                    
                    // Price range section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("price_range".localized(for: appLanguage).uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .tracking(1.0)
                        
                        HStack(spacing: 12) {
                            HStack {
                                Text("฿")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                TextField("min_price".localized(for: appLanguage), text: $localMinPrice)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appDivider, lineWidth: 1)
                            )
                            
                            Text("to".localized(for: appLanguage))
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                            
                            HStack {
                                Text("฿")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                TextField("max_price".localized(for: appLanguage), text: $localMaxPrice)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appDivider, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider().background(Color.appDivider).padding(.horizontal)
                    
                    // Favorites toggle section
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $localFavoritesOnly) {
                            HStack(spacing: 10) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.appRose)
                                    .font(.system(size: 16))
                                Text("favorites_only".localized(for: appLanguage))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        .tint(Color.brandGreenDark)
                        .padding(14)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appDivider, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
            }
            .background(Color.appBackground)
            .navigationTitle("filter_menu".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    // Reset Button
                    Button {
                        localSortBy = .none
                        localMinPrice = ""
                        localMaxPrice = ""
                        localFavoritesOnly = false
                        APHaptic.trigger()
                    } label: {
                        Text("reset".localized(for: appLanguage))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appDivider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Apply Button
                    Button {
                        sortBy = localSortBy
                        minPrice = localMinPrice
                        maxPrice = localMaxPrice
                        favoritesOnly = localFavoritesOnly
                        dismiss()
                        APHaptic.success()
                    } label: {
                        Text("apply".localized(for: appLanguage))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brandGreenDark)
                            .cornerRadius(12)
                            .shadow(color: Color.brandGreenDark.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Color.appSurface
                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: -4)
                )
            }
            .onAppear {
                localSortBy = sortBy
                localMinPrice = minPrice
                localMaxPrice = maxPrice
                localFavoritesOnly = favoritesOnly
            }
        }
    }
}

