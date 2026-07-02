// CustomerCRMView.swift
// AlphaPos — Enterprise Customer CRM
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData

/// Customer Relationship Management view.
/// Provides a unified customer database with segmentation,
/// purchase history, and engagement tools.
///
/// Enterprise features:
/// - Customer database with search & filters
/// - Customer segments (VIP, Regular, New, At-risk)
/// - Purchase history per customer
/// - Lifetime value (LTV) calculation
/// - Communication log (SMS/LINE/Email history)
/// - Customer notes & tags
/// - Export/Import customer data
struct CustomerCRMView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Order.createdAt, order: .reverse) private var allOrders: [Order]
    @State private var searchText = ""
    @State private var selectedSegment: CustomerSegment = .all
    @State private var selectedCustomer: Customer? = nil
    
    @State private var showingAddCustomerSheet = false
    @State private var newCustomerName = ""
    @State private var newCustomerPhone = ""
    @State private var newCustomerEmail = ""
    
    enum CustomerSegment: String, CaseIterable, Identifiable {
        case all = "All"
        case vip = "VIP"
        case regular = "Regular"
        case new = "New"
        case atRisk = "At Risk"
        
        var id: String { rawValue }
        
        var color: Color {
            switch self {
            case .all: return .appAccent
            case .vip: return Color(hex: "F59E0B")
            case .regular: return Color(hex: "10B981")
            case .new: return Color(hex: "3B82F6")
            case .atRisk: return Color(hex: "EF4444")
            }
        }
        
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .vip: return "crown.fill"
            case .regular: return "person.fill"
            case .new: return "person.badge.plus"
            case .atRisk: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider().background(Color.appDivider)
            
            // Content
            HStack(spacing: 0) {
                // Customer list
                customerListSection
                    .frame(maxWidth: .infinity)
                
                Divider().background(Color.appDivider)
                
                // Customer detail
                customerDetailSection
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showingAddCustomerSheet) {
            NavigationStack {
                Form {
                    Section(header: Text("Customer Information")) {
                        TextField("Name", text: $newCustomerName)
                        TextField("Phone", text: $newCustomerPhone)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $newCustomerEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                }
                .navigationTitle("Add Customer")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingAddCustomerSheet = false
                            clearAddCustomerFields()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveCustomer()
                        }
                        .disabled(newCustomerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func clearAddCustomerFields() {
        newCustomerName = ""
        newCustomerPhone = ""
        newCustomerEmail = ""
    }
    
    private func saveCustomer() {
        let name = newCustomerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = newCustomerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = newCustomerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newCustomer = Customer(
            name: name,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone
        )
        modelContext.insert(newCustomer)
        try? modelContext.save()
        
        // Background sync
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        
        selectedCustomer = newCustomer
        showingAddCustomerSheet = false
        clearAddCustomerFields()
        APHaptic.trigger()
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("customers_title".t)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("\(customers.count) " + "customers_count_suffix".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            // Segment pills
            HStack(spacing: 8) {
                ForEach(CustomerSegment.allCases) { segment in
                    Button {
                        withAnimation { selectedSegment = segment }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: segment.icon)
                                .font(.system(size: 10))
                            Text(segment.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedSegment == segment ? segment.color.opacity(0.15) : Color.appSurfaceHigh)
                        .foregroundColor(selectedSegment == segment ? segment.color : .textSecondary)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Add customer button
            Button {
                showingAddCustomerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("add_customer".t)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appAccent)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Customer List
    
    private var customerListSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                TextField("search_customers".t, text: $searchText)
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color.appSurfaceHigh)
            .cornerRadius(10)
            .padding()
            
            // Customer rows
            ScrollView {
                LazyVStack(spacing: 4) {
                    if filteredCustomers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 40))
                                .foregroundColor(.textTertiary)
                            Text("no_customers_found".t)
                                .font(.subheadline)
                                .foregroundColor(.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(filteredCustomers) { customer in
                            customerRow(customer)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func customerRow(_ customer: Customer) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(customerInitials(customer.name))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(customer.phone ?? customer.email ?? "No contact")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
            
            Spacer()
            
            // LTV
            VStack(alignment: .trailing, spacing: 2) {
                Text("฿\(customer.totalSpend.formatted(.number.precision(.fractionLength(0))))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("\(customer.visitCount) visits")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(10)
        .background(selectedCustomer?.id == customer.id ? Color.appAccent.opacity(0.08) : Color.clear)
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { selectedCustomer = customer }
        }
    }
    
    // MARK: - Customer Detail
    
    private var customerDetailSection: some View {
        Group {
            if let customer = selectedCustomer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Profile header
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.appAccent.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                Text(customerInitials(customer.name))
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.appAccent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(customer.name)
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(.textPrimary)
                                if let phone = customer.phone {
                                    Text(phone)
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                }
                                if let email = customer.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        
                        // Stats
                        HStack(spacing: 16) {
                            statCard(title: "Total Spent", value: "฿\(customer.totalSpend.formatted(.number.precision(.fractionLength(0))))", color: .green)
                            statCard(title: "Visits", value: "\(customer.visitCount)", color: .blue)
                            statCard(title: "Points", value: "\(customer.loyaltyPoints)", color: .purple)
                        }
                        
                        // Purchase history from actual orders
                        let customerOrders = allOrders.filter { $0.customer?.id == customer.id && $0.status == "completed" }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("crm_purchase_history".t)
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            if customerOrders.isEmpty {
                                Text("crm_purchase_history_empty".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 40)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(12)
                            } else {
                                ForEach(customerOrders) { order in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(order.orderNumber)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        Text("฿\(order.total.formatted(.number.precision(.fractionLength(2))))")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.textPrimary)
                                    }
                                    .padding()
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.textTertiary)
                    Text("select_customer_prompt".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private var filteredCustomers: [Customer] {
        var result = customers
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch selectedSegment {
        case .all:
            break
        case .vip:
            result = result.filter { $0.totalSpend >= 5000 || $0.membershipTier.lowercased() == "gold" || $0.membershipTier.lowercased() == "platinum" }
        case .regular:
            result = result.filter { $0.totalSpend > 0 && $0.totalSpend < 5000 }
        case .new:
            result = result.filter { $0.visitCount <= 1 }
        case .atRisk:
            result = result.filter { $0.visitCount > 1 && $0.totalSpend < 500 }
        }
        return result
    }
    
    private func customerInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
