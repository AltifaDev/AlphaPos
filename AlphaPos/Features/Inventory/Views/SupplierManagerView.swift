// SupplierManagerView.swift
// AlphaPos — Dense supplier master with CRUD + linked inventory items

import SwiftUI
import SwiftData

struct SupplierManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    @Query(sort: \InventoryItem.name) private var allInventoryItems: [InventoryItem]

    @State private var viewModel = InventoryViewModel()
    @State private var selectedSupplier: Supplier?
    @State private var showingEditor = false
    @State private var editingSupplier: Supplier?
    @State private var showingDeleteConfirm = false
    @State private var searchText = ""
    @State private var linkedExpanded = true

    // Editor fields
    @State private var name = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var taxId = ""
    @State private var paymentTerms = ""
    @State private var leadTimeDays = "7"

    private var activeSuppliers: [Supplier] {
        suppliers.filter { !$0.isDeleted }
    }

    private var filteredSuppliers: [Supplier] {
        guard !searchText.isEmpty else { return activeSuppliers }
        return activeSuppliers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.contactName ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.taxId ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.phone ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            supplierListPanel
                .frame(width: 300)
                .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .trailing)

            if let supplier = selectedSupplier, !supplier.isDeleted {
                supplierDetailView(supplier)
            } else {
                compactEmptyDetail
            }
        }
        .sheet(isPresented: $showingEditor) {
            supplierEditorSheet
        }
        .alert("supplier_delete_title".t, isPresented: $showingDeleteConfirm) {
            Button("cancel_btn".t, role: .cancel) {}
            Button("delete_action".t, role: .destructive) {
                if let s = selectedSupplier {
                    viewModel.deleteSupplier(s)
                    selectedSupplier = nil
                }
            }
        } message: {
            Text("supplier_delete_msg".t)
        }
        .onAppear {
            viewModel.modelContext = modelContext
            if selectedSupplier == nil {
                selectedSupplier = activeSuppliers.first
            }
        }
    }

    // MARK: - List

    private var supplierListPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    TextField("search_supplier_placeholder".t, text: $searchText)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button {
                    editingSupplier = nil
                    clearEditorFields()
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(APGradient.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, APSpacing.sm)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            if filteredSuppliers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 22))
                        .foregroundColor(.textTertiary)
                    Text("no_suppliers_found".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Button {
                        editingSupplier = nil
                        clearEditorFields()
                        showingEditor = true
                    } label: {
                        Text("add_new_supplier_title".t)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appTeal)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSuppliers) { supplier in
                            Button {
                                selectedSupplier = supplier
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(supplier.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            if let phone = supplier.phone, !phone.isEmpty {
                                                Text(phone)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            if let tax = supplier.taxId, !tax.isEmpty {
                                                Text("· \(tax)")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.textTertiary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    let linked = linkedItems(for: supplier).count
                                    if linked > 0 {
                                        Text("\(linked)")
                                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                                            .foregroundColor(.appAccent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.appAccent.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, APSpacing.sm)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedSupplier?.id == supplier.id ? Color.appTeal.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.appDivider)
                        }
                    }
                }
                .background(Color.appBackground)
            }
        }
    }

    private var compactEmptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.2")
                .font(.system(size: 28))
                .foregroundColor(.textTertiary)
            Text("select_supplier_title".t)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textSecondary)
            Text("select_supplier_subtitle".t)
                .font(.caption)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Detail

    private func supplierDetailView(_ supplier: Supplier) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(supplier.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.textPrimary)
                        if let contact = supplier.contactName, !contact.isEmpty {
                            Text(contact)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        beginEdit(supplier)
                    } label: {
                        Label("edit_details".t, systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appTeal)
                    }
                    .buttonStyle(.plain)
                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appRose)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    detailCell("supplier_phone_number".t, supplier.phone ?? "—")
                    detailCell("supplier_email_address".t, supplier.email ?? "—")
                    detailCell("supplier_tax_id".t, supplier.taxId ?? "—")
                    detailCell("supplier_payment_terms".t, supplier.paymentTerms ?? "—")
                    detailCell("supplier_lead_time".t, "\(supplier.defaultLeadTimeDays)d")
                    detailCell("supplier_address".t, supplier.address ?? "—")
                }

                DisclosureGroup(isExpanded: $linkedExpanded) {
                    let items = linkedItems(for: supplier)
                    if items.isEmpty {
                        Text("no_supplied_ingredients_linked".t)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Text(item.sku ?? "—")
                                            .font(.system(size: 9))
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.textSecondary)
                                    Text(String(format: "฿%.2f", item.costPrice))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .padding(.vertical, 5)
                                Divider().opacity(0.3)
                            }
                        }
                    }
                } label: {
                    Text("supplied_raw_ingredients".t)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                }
            }
            .padding(APSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func detailCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func linkedItems(for supplier: Supplier) -> [InventoryItem] {
        allInventoryItems.filter { !$0.isDeleted && $0.supplier?.id == supplier.id }
    }

    // MARK: - Editor

    private var supplierEditorSheet: some View {
        NavigationStack {
            Form {
                Section("supplier_contact_details_section".t) {
                    TextField("company_supplier_name_label".t, text: $name)
                    TextField("contact_person_name_label".t, text: $contactName)
                    TextField("phone_number_label".t, text: $phone)
                        .keyboardType(.phonePad)
                    TextField("email_address_label".t, text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("full_address_label".t, text: $address)
                }
                Section("supplier_commercial_section".t) {
                    TextField("supplier_tax_id".t, text: $taxId)
                    TextField("supplier_payment_terms".t, text: $paymentTerms)
                    TextField("supplier_lead_time".t, text: $leadTimeDays)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(editingSupplier == nil ? "add_new_supplier_title".t : "edit_supplier_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { showingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingSupplier == nil ? "add_btn".t : "save_btn".t) {
                        saveEditor()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .apColorScheme()
    }

    private func beginEdit(_ supplier: Supplier) {
        editingSupplier = supplier
        name = supplier.name
        contactName = supplier.contactName ?? ""
        phone = supplier.phone ?? ""
        email = supplier.email ?? ""
        address = supplier.address ?? ""
        taxId = supplier.taxId ?? ""
        paymentTerms = supplier.paymentTerms ?? ""
        leadTimeDays = "\(supplier.defaultLeadTimeDays)"
        showingEditor = true
    }

    private func clearEditorFields() {
        name = ""
        contactName = ""
        phone = ""
        email = ""
        address = ""
        taxId = ""
        paymentTerms = ""
        leadTimeDays = "7"
    }

    private func saveEditor() {
        let lead = Int(leadTimeDays) ?? 7
        let cName = contactName.isEmpty ? nil : contactName
        let ph = phone.isEmpty ? nil : phone
        let em = email.isEmpty ? nil : email
        let addr = address.isEmpty ? nil : address
        let tax = taxId.isEmpty ? nil : taxId
        let terms = paymentTerms.isEmpty ? nil : paymentTerms

        if let existing = editingSupplier {
            viewModel.updateSupplier(
                existing,
                name: name,
                contactName: cName,
                phone: ph,
                email: em,
                address: addr,
                taxId: tax,
                paymentTerms: terms,
                defaultLeadTimeDays: lead
            )
            selectedSupplier = existing
        } else {
            viewModel.addSupplier(
                name: name,
                contactName: cName,
                phone: ph,
                email: em,
                address: addr,
                taxId: tax,
                paymentTerms: terms,
                defaultLeadTimeDays: lead
            )
        }
        showingEditor = false
        clearEditorFields()
        editingSupplier = nil
    }
}
