// SupplierManagerView.swift
// AlphaPos — Premium Supplier & Contact Center

import SwiftUI
import SwiftData

struct SupplierManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
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
                        TextField("search_supplier_placeholder".t, text: $searchText)
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
                        Text("no_suppliers_found".t)
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
                                    Text(supplier.contactName ?? "no_contact_name".t)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                if supplier.inventoryItems.count > 0 {
                                    Text(LocalizationManager.shared.t("items_count_template", supplier.inventoryItems.count))
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
                    Text("select_supplier_title".t)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("select_supplier_subtitle".t)
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
                            Text("supplier_profile_details".t)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    
                    Divider().background(Color.appDivider)
                    
                    Grid(alignment: .leading, horizontalSpacing: APSpacing.lg, verticalSpacing: APSpacing.sm) {
                        detailGridRow(label: "supplier_contact_person".t, value: supplier.contactName ?? "—")
                        detailGridRow(label: "supplier_phone_number".t, value: supplier.phone ?? "—")
                        detailGridRow(label: "supplier_email_address".t, value: supplier.email ?? "—")
                        detailGridRow(label: "supplier_address".t, value: supplier.address ?? "—")
                    }
                }
                .padding(APSpacing.md)
                .apCard()
                
                // Supplied Items list
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    Text("supplied_raw_ingredients".t)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                    
                    let suppliedItems = allInventoryItems.filter { $0.supplier?.id == supplier.id }
                    
                    if suppliedItems.isEmpty {
                        Text("no_supplied_ingredients_linked".t)
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
                                        Text(LocalizationManager.shared.t("cost_per_unit_template", item.costPrice, item.unit))
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.textPrimary)
                                        Text(LocalizationManager.shared.t("on_hand_with_unit_template", item.currentQuantity, item.unit))
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
                            Text("supplier_contact_details_section".t)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            
                            inputRow(label: "company_supplier_name_label".t, placeholder: "company_supplier_name_placeholder".t, text: $name)
                            inputRow(label: "contact_person_name_label".t, placeholder: "contact_person_name_placeholder".t, text: $contactName)
                            inputRow(label: "phone_number_label".t, placeholder: "phone_number_placeholder".t, text: $phone)
                            inputRow(label: "email_address_label".t, placeholder: "email_address_placeholder".t, text: $email)
                            inputRow(label: "full_address_label".t, placeholder: "full_address_placeholder".t, text: $address)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("add_new_supplier_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        dismissAddSheet()
                    }
                    .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add_btn".t) {
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
