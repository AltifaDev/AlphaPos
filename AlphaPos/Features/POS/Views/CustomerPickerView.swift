// CustomerPickerView.swift
// AlphaPos — Customer Picker & Management

import SwiftUI
import SwiftData

// MARK: - Customer Picker View

struct CustomerPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]
    
    let onSelect: (Customer) -> Void
    
    @State private var searchText = ""
    @State private var selectedCustomer: Customer?
    @State private var showAddSheet = false
    
    private var filteredCustomers: [Customer] {
        let active = customers.filter { !$0.isDeleted }
        if searchText.isEmpty { return active }
        let query = searchText.lowercased()
        return active.filter {
            $0.name.lowercased().contains(query) ||
            ($0.phone ?? "").contains(query) ||
            ($0.email ?? "").lowercased().contains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                HStack(spacing: 0) {
                    // Left: Customer list
                    customerListPanel
                    
                    Divider().background(Color.appDivider)
                    
                    // Right: Customer detail
                    if let customer = selectedCustomer {
                        customerDetailPanel(customer: customer)
                    } else {
                        emptyDetailState
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.appAccent)
                        Text("customers_title".t)
                            .font(.headline).fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("close_btn_label".t) {
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showAddSheet = true
                        APHaptic.trigger()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.appAccent)
                    }
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .sheet(isPresented: $showAddSheet) {
                AddCustomerSheet { newCustomer in
                    modelContext.insert(newCustomer)
                    modelContext.saveWithLogging(label: #function)
                    selectedCustomer = newCustomer
                    
                    Task {
                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                    }
                }
            }
        }
        .apColorScheme()
    }
    
    // MARK: - Customer List Panel
    
    private var customerListPanel: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                TextField("Search name, phone, email...", text: $searchText)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .tint(.appAccent)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .padding(APSpacing.md)
            
            HStack {
                Text(String(format: "customers_count_template".t, filteredCustomers.count))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.sm)
            
            Divider().background(Color.appDivider)
            
            if filteredCustomers.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.textTertiary)
                    Text("customers_none_found".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    
                    Button(action: {
                        showAddSheet = true
                        APHaptic.trigger()
                    }) {
                        Label("add_customer_btn".t, systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.appAccent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(filteredCustomers) { customer in
                            customerListCard(customer: customer)
                        }
                    }
                    .padding(APSpacing.md)
                }
            }
        }
        .frame(width: 360)
        .background(Color.appBackground)
    }
    
    private func customerListCard(customer: Customer) -> some View {
        let isSelected = selectedCustomer?.id == customer.id
        
        return Button(action: {
            withAnimation(.spring(response: 0.3)) {
                selectedCustomer = customer
            }
            APHaptic.trigger()
        }) {
            HStack(spacing: APSpacing.md) {
                // Avatar with tier color
                ZStack {
                    Circle()
                        .fill(tierGradient(for: customer.membershipTier))
                        .frame(width: 40, height: 40)
                    Text(String(customer.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    if let phone = customer.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
                
                tierBadge(for: customer.membershipTier)
            }
            .padding(APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(isSelected ? Color.appAccent : Color.appBorderSubtle, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty Detail State
    
    private var emptyDetailState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 44))
                    .foregroundColor(.textTertiary)
            }
            Text("customers_select_title".t)
                .font(.title3.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("customers_select_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
    
    // MARK: - Customer Detail Panel
    
    private func customerDetailPanel(customer: Customer) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    // Profile header card
                    profileHeaderCard(customer: customer)
                    
                    // Stats grid
                    statsGrid(customer: customer)
                    
                    // Customer info
                    customerInfoSection(customer: customer)
                    
                    // Recent orders placeholder
                    recentOrdersSection(customer: customer)
                }
                .padding(APSpacing.lg)
            }
            
            // Select button
            selectCustomerBar(customer: customer)
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }
    
    // MARK: - Profile Header Card
    
    private func profileHeaderCard(customer: Customer) -> some View {
        VStack(spacing: APSpacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(tierGradient(for: customer.membershipTier))
                    .frame(width: 72, height: 72)
                    .shadow(color: tierColor(for: customer.membershipTier).opacity(0.4), radius: 12)
                Text(String(customer.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(customer.name)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            
            tierBadge(for: customer.membershipTier)
            
            if let phone = customer.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone.fill")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            if let email = customer.email, !email.isEmpty {
                Label(email, systemImage: "envelope.fill")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .apCard()
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(customer: Customer) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: APSpacing.md) {
            statCard(title: "Visits", value: "\(customer.visitCount)", icon: "figure.walk", color: .appAccent)
            statCard(title: "Points", value: "\(customer.loyaltyPoints)", icon: "star.fill", color: Color(hex: "F59E0B"))
            statCard(title: "Total Spend", value: "฿\(Int(customer.totalSpend))", icon: "banknote.fill", color: .appTeal)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: APSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .apCard()
    }
    
    // MARK: - Customer Info
    
    private func customerInfoSection(customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("customers_details_header".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            if let notes = customer.notes, !notes.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundColor(.textTertiary)
                    Text(notes)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding(APSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
            }
            
            if let allergies = customer.allergies, !allergies.isEmpty {
                HStack(alignment: .top) {
                    Image(systemName: "allergens")
                        .foregroundColor(.appRose)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("customers_allergies_lbl".t)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.appRose)
                        Text(allergies)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(APSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appRose.opacity(0.08))
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appRose.opacity(0.2), lineWidth: 1)
                )
            }
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.textTertiary)
                Text("customers_last_visit_lbl".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Text(customer.updatedAt, style: .date)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface)
            .cornerRadius(APRadius.md)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.textTertiary)
                Text("customers_member_since_lbl".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Text(customer.createdAt, style: .date)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textPrimary)
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface)
            .cornerRadius(APRadius.md)
        }
    }
    
    // MARK: - Recent Orders Section
    
    private func recentOrdersSection(customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("customers_recent_orders_header".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            let recentOrders = orders.filter { !$0.isDeleted && $0.customer?.id == customer.id }.prefix(8)
            if recentOrders.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("customers_no_orders_yet".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(APSpacing.xl)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach(Array(recentOrders)) { order in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(order.orderNumber)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.textPrimary)
                                Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("฿\(order.total, specifier: "%.2f")")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.appTeal)
                                Text(order.status.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                    }
                }
            }
        }
    }
    
    // MARK: - Select Customer Bar
    
    private func selectCustomerBar(customer: Customer) -> some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("customers_selected_lbl".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(customer.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    APHaptic.trigger()
                    onSelect(customer)
                    dismiss()
                }) {
                    Label("link_to_order_btn".t, systemImage: "link.circle.fill")
                        .apGradientButton()
                }
                .frame(width: 220)
            }
            .padding(APSpacing.md)
        }
        .background(Color.appSurface)
    }
    
    // MARK: - Tier Helpers
    
    private func tierColor(for tier: String) -> Color {
        switch tier.lowercased() {
        case "silver":   return Color(hex: "9CA3AF")
        case "gold":     return Color(hex: "F59E0B")
        case "platinum": return Color(hex: "8B5CF6")
        default:         return Color(hex: "6B7280")
        }
    }
    
    private func tierGradient(for tier: String) -> LinearGradient {
        switch tier.lowercased() {
        case "silver":
            return LinearGradient(colors: [Color(hex: "9CA3AF"), Color(hex: "D1D5DB")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "gold":
            return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FBBF24")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "platinum":
            return LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "A78BFA")], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color(hex: "6B7280"), Color(hex: "9CA3AF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private func tierBadge(for tier: String) -> some View {
        let displayName = tier.capitalized
        let color = tierColor(for: tier)
        
        return HStack(spacing: 4) {
            Image(systemName: tierIcon(for: tier))
                .font(.system(size: 10))
            Text(displayName)
                .font(.caption.weight(.bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }
    
    private func tierIcon(for tier: String) -> String {
        switch tier.lowercased() {
        case "silver":   return "medal"
        case "gold":     return "medal.fill"
        case "platinum": return "crown.fill"
        default:         return "person.fill"
        }
    }
}

// MARK: - Add Customer Sheet

struct AddCustomerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onSave: (Customer) -> Void
    
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var allergies = ""
    @State private var isTaxExempt = false
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: APSpacing.lg) {
                        // Avatar preview
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "6B7280"), Color(hex: "9CA3AF")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                            Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .animation(.spring(response: 0.3), value: name)
                        }
                        .padding(.top, APSpacing.md)
                        
                        VStack(spacing: APSpacing.md) {
                            formField(title: "Name *", placeholder: "Customer name", text: $name, icon: "person.fill")
                            formField(title: "Phone", placeholder: "+66 xxx xxx xxxx", text: $phone, icon: "phone.fill")
                            formField(title: "Email", placeholder: "email@example.com", text: $email, icon: "envelope.fill")
                            formField(title: "Notes", placeholder: "Any special notes...", text: $notes, icon: "note.text")
                            formField(title: "Allergies", placeholder: "Nuts, Shellfish, etc.", text: $allergies, icon: "allergens")
                            Toggle("Tax Exempt", isOn: $isTaxExempt)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, APSpacing.sm)
                                .tint(.appAccent)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("customers_new_btn".t)
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.Common.cancel.t) {
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.Common.save.t) {
                        let customer = Customer(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            email: email.isEmpty ? nil : email,
                            phone: phone.isEmpty ? nil : phone,
                            notes: notes.isEmpty ? nil : notes,
                            allergies: allergies.isEmpty ? nil : allergies,
                            isTaxExempt: isTaxExempt
                        )
                        onSave(customer)
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                    .fontWeight(.bold)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
        }
        .apColorScheme()
        .presentationDetents([.large])
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.xs) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            HStack(spacing: APSpacing.sm) {
                Image(systemName: icon)
                    .foregroundColor(.textTertiary)
                    .frame(width: 20)
                TextField(placeholder, text: text)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .tint(.appAccent)
            }
            .padding(APSpacing.sm)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.sm)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }
}
