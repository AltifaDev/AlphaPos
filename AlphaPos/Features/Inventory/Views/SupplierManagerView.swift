// SupplierManagerView.swift
// AlphaPos — Premium Supplier & Contact Center

import SwiftUI
import SwiftData

struct SupplierManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    @Query(sort: \InventoryItem.name) private var allInventoryItems: [InventoryItem]
    
    @State private var viewModel = InventoryViewModel()
    @State private var selectedSupplier: Supplier?
    @State private var showingAddSheet = false
    @State private var searchText = ""
    
    // Add Supplier Sheet fields
    @State private var name = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    
    private var filteredSuppliers: [Supplier] {
        guard !searchText.isEmpty else { return suppliers }
        return suppliers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.contactName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left list panel
            VStack(spacing: 0) {
                // Header search and add
                HStack(spacing: APSpacing.sm) {
                    HStack(spacing: APSpacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textSecondary)
                            .font(.footnote)
                        TextField("Search supplier...", text: $searchText)
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(8)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .padding(9)
                            .background(APGradient.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)
                
                // Suppliers list
                if filteredSuppliers.isEmpty {
                    VStack(spacing: APSpacing.sm) {
                        Image(systemName: "person.2.slash.fill")
                            .font(.largeTitle)
                            .foregroundColor(.textTertiary)
                        Text("No Suppliers")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedSupplier) {
                        ForEach(filteredSuppliers) { supplier in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(supplier.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textPrimary)
                                    Text(supplier.contactName ?? "No Contact Name")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                if supplier.inventoryItems.count > 0 {
                                    Text("\(supplier.inventoryItems.count) items")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.appAccent.opacity(0.1))
                                        .foregroundColor(.appAccent)
                                        .clipShape(Capsule())
                                }
                            }
                            .tag(supplier)
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.appBackground)
                }
            }
            .frame(width: 320)
            .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .trailing)
            
            // Right detail panel
            if let supplier = selectedSupplier {
                supplierDetailView(supplier)
            } else {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(APGradient.accent)
                    Text("Select a Supplier")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("Choose from the left to view supplier contact info and raw materials supply list.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addSupplierSheet
        }
        .onAppear {
            viewModel.modelContext = modelContext
            if selectedSupplier == nil && !suppliers.isEmpty {
                selectedSupplier = suppliers.first
            }
        }
    }
    
    // MARK: - Detail Panel View
    
    private func supplierDetailView(_ supplier: Supplier) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.lg) {
                // Info block
                VStack(alignment: .leading, spacing: APSpacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(supplier.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Text("Supplier Profile & Details")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    
                    Divider().background(Color.appDivider)
                    
                    Grid(alignment: .leading, horizontalSpacing: APSpacing.lg, verticalSpacing: APSpacing.sm) {
                        detailGridRow(label: "Contact Person", value: supplier.contactName ?? "—")
                        detailGridRow(label: "Phone Number", value: supplier.phone ?? "—")
                        detailGridRow(label: "Email Address", value: supplier.email ?? "—")
                        detailGridRow(label: "Address", value: supplier.address ?? "—")
                    }
                }
                .padding(APSpacing.md)
                .apCard()
                
                // Supplied Items list
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    Text("Supplied Raw Ingredients")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                    
                    let suppliedItems = allInventoryItems.filter { $0.supplier?.id == supplier.id }
                    
                    if suppliedItems.isEmpty {
                        Text("No ingredients linked to this supplier. Link ingredients in Stock Levels.")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: APSpacing.sm) {
                            ForEach(suppliedItems) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.textPrimary)
                                        Text("SKU: \(item.sku ?? "N/A")")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Cost: ฿\(String(format: "%.2f", item.costPrice))/\(item.unit)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.textPrimary)
                                        Text("On Hand: \(String(format: "%.1f", item.currentQuantity)) \(item.unit)")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                Divider().background(Color.appDivider)
                            }
                        }
                        .padding(APSpacing.md)
                        .apCard()
                    }
                }
            }
            .padding(APSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
    
    private func detailGridRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
        }
    }
    
    // MARK: - Add Supplier Sheet
    
    private var addSupplierSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            Text("Supplier Contact details")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            
                            inputRow(label: "Company / Supplier Name", placeholder: "e.g., CP FreshMart", text: $name)
                            inputRow(label: "Contact Person Name", placeholder: "e.g., Somchai Jaidee", text: $contactName)
                            inputRow(label: "Phone Number", placeholder: "e.g., 0812345678", text: $phone)
                            inputRow(label: "Email Address", placeholder: "e.g., contact@company.com", text: $email)
                            inputRow(label: "Full Address", placeholder: "e.g., 123 Sukhumvit Rd, Bangkok", text: $address)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("Add New Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissAddSheet()
                    }
                    .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addSupplier(
                            name: name,
                            contactName: contactName.isEmpty ? nil : contactName,
                            phone: phone.isEmpty ? nil : phone,
                            email: email.isEmpty ? nil : email,
                            address: address.isEmpty ? nil : address
                        )
                        dismissAddSheet()
                    }
                    .disabled(name.isEmpty)
                    .foregroundStyle(APGradient.accent)
                }
            }
        }
        .apColorScheme()
    }
    
    private func inputRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 4)
    }
    
    private func dismissAddSheet() {
        name = ""
        contactName = ""
        phone = ""
        email = ""
        address = ""
        showingAddSheet = false
    }
}
