import SwiftUI
import SwiftData

struct PurchaseOrderManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let activeBranch: Branch
    /// When true (Inventory hub), skip NavigationStack chrome / Close button.
    var embedded: Bool = false
    var onScanDocument: (() -> Void)? = nil
    
    @Query(filter: #Predicate<PurchaseOrder> { !$0.isDeleted }, sort: \PurchaseOrder.orderDate, order: .reverse) private var allPOs: [PurchaseOrder]
    @Query(filter: #Predicate<Supplier> { !$0.isDeleted }, sort: \Supplier.name) private var allSuppliers: [Supplier]
    
    @State private var showingCreateSheet = false
    @State private var selectedPO: PurchaseOrder?
    @State private var showingNoSupplierAlert = false

    private var suppliers: [Supplier] { allSuppliers }
    
    private var filteredPOs: [PurchaseOrder] {
        allPOs.filter { $0.branch?.id == activeBranch.id }
    }

    private var draftCount: Int { filteredPOs.filter { $0.status == "draft" }.count }
    private var pendingCount: Int { filteredPOs.filter { $0.status == "sent" || $0.status == "partially_received" }.count }
    private var receivedCount: Int { filteredPOs.filter { $0.status == "received" }.count }
    
    var body: some View {
        Group {
            if embedded {
                poContent
            } else {
                NavigationStack {
                    poContent
                        .navigationTitle("Purchase Orders — \(activeBranch.name)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { sheetToolbar }
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePurchaseOrderSheet(activeBranch: activeBranch)
        }
        .sheet(item: $selectedPO) { po in
            PurchaseOrderDetailView(po: po)
        }
        .alert("No Suppliers Found", isPresented: $showingNoSupplierAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("po_must_register_supplier_desc".t)
        }
        .apColorScheme()
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("close_btn_label".t) { dismiss() }
                .foregroundColor(.textPrimary)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: addPOTapped) {
                Label("add_new_po_btn".t, systemImage: "plus")
                    .foregroundColor(.appTeal)
            }
        }
    }

    private var poContent: some View {
        VStack(spacing: 0) {
            // Single compact toolbar: scan + KPI chips + add
            HStack(spacing: 6) {
                if let onScanDocument {
                    Button(action: onScanDocument) {
                        Label("stock_scan_title".t, systemImage: "sparkles.rectangle.stack")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appTeal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.appTeal.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                poStatusChip("Drafts", draftCount, .appTeal)
                poStatusChip("Sent", pendingCount, .appAmber)
                poStatusChip("Received", receivedCount, .appRose)

                Spacer(minLength: 4)

                if suppliers.isEmpty {
                    Text("po_no_suppliers_title".t)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.appAmber)
                        .lineLimit(1)
                }

                if embedded {
                    Button(action: addPOTapped) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.appTeal)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            if filteredPOs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("po_no_orders_title".t)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                    Text("po_no_orders_desc".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    if !suppliers.isEmpty {
                        Button(action: addPOTapped) {
                            Text("add_new_po_btn".t)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.appTeal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                // Column header
                HStack(spacing: 0) {
                    Text("PO #").frame(width: 110, alignment: .leading)
                    Text("po_supplier_label".t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Date").frame(width: 72, alignment: .trailing)
                    Text("inv_stock_value_col".t).frame(width: 88, alignment: .trailing)
                    Text("status_label".t).frame(width: 72, alignment: .center)
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh.opacity(0.5))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPOs) { po in
                            poRow(po)
                        }
                    }
                }
                .background(Color.appBackground)
            }
        }
        .background(Color.appBackground)
    }

    private func addPOTapped() {
        if suppliers.isEmpty {
            showingNoSupplierAlert = true
        } else {
            showingCreateSheet = true
        }
    }

    private func poStatusChip(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
    
    @ViewBuilder
    private func poRow(_ po: PurchaseOrder) -> some View {
        let lineTotal = po.items.reduce(0.0) { $0 + ($1.quantityOrdered * $1.unitCost) }
        let displayTotal = po.grandTotal ?? lineTotal

        Button(action: { selectedPO = po }) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(po.poNumber)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let inv = po.invoiceNumber, !inv.isEmpty {
                        Text(inv)
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 110, alignment: .leading)

                Text(po.supplier?.name ?? "—")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(po.orderDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.textSecondary)
                    .frame(width: 72, alignment: .trailing)

                Text(String(format: "฿%.0f", displayTotal))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(.textPrimary)
                    .frame(width: 88, alignment: .trailing)

                poStatusBadge(po.status)
                    .frame(width: 72, alignment: .center)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Divider().background(Color.appDivider), alignment: .bottom)
    }
    
    @ViewBuilder
    private func poStatusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case "draft": return ("Draft", .appTeal)
            case "sent": return ("Sent", .appAmber)
            case "received": return ("Received", .appRose)
            case "partially_received": return ("Partial", .appAmber)
            case "cancelled": return ("X", .textSecondary)
            default: return (status.capitalized, .textSecondary)
            }
        }()
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// ── CREATE PURCHASE ORDER SHEET ──────────────────────────────────────────────
struct CreatePurchaseOrderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let activeBranch: Branch
    
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    
    @State private var selectedSupplier: Supplier?
    @State private var poNumber = ""
    @State private var notes = ""
    
    // Add item fields
    @State private var selectedItem: InventoryItem?
    @State private var quantityText = ""
    @State private var unitCostText = ""
    
    @State private var lineItems: [(item: InventoryItem, qty: Double, cost: Double)] = []
    
    private var branchItems: [InventoryItem] {
        allItems.filter { $0.branch?.id == activeBranch.id }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.lg) {
                        
                        // Metadata Block
                        VStack(spacing: APSpacing.md) {
                            HStack(spacing: APSpacing.md) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("po_number_label".t)
                                        .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal)
                                    TextField("e.g. PO-2026-0001", text: $poNumber)
                                        .padding(APSpacing.sm)
                                        .background(Color.appBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("po_supplier_label".t)
                                        .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal)
                                    Picker("Supplier", selection: $selectedSupplier) {
                                        Text("po_select_supplier_placeholder".t).tag(nil as Supplier?)
                                        ForEach(suppliers) { sup in
                                            Text(sup.name).tag(sup as Supplier?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.appTeal)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("po_notes_label".t)
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary)
                                TextField("Add special orders, delivery terms...", text: $notes)
                                    .padding(APSpacing.sm)
                                    .background(Color.appBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                            }
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        // Line items section
                        Text("po_details_header".t)
                            .font(.caption).fontWeight(.bold).foregroundColor(.textSecondary).tracking(1.0)
                        
                        VStack(spacing: APSpacing.md) {
                            // Line items list
                            if lineItems.isEmpty {
                                Text("po_no_items_added".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(lineItems.indices, id: \.self) { idx in
                                    let line = lineItems[idx]
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(line.item.name)
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundColor(.textPrimary)
                                            Text("Cost: ฿\(String(format: "%.2f", line.cost)) | Qty: \(String(format: "%.2f", line.qty)) \(line.item.unit)")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        
                                        Text(String(format: "฿%.2f", line.qty * line.cost))
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.appTeal)
                                        
                                        Button(action: { lineItems.remove(at: idx) }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.appRose)
                                        }
                                        .padding(.leading, 8)
                                    }
                                    Divider().background(Color.appDivider)
                                }
                            }
                            
                            // Add item form
                            VStack(spacing: APSpacing.sm) {
                                Picker("Item", selection: $selectedItem) {
                                    Text("po_choose_ingredient_placeholder".t).tag(nil as InventoryItem?)
                                    ForEach(branchItems) { item in
                                        Text(item.name).tag(item as InventoryItem?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.appTeal)
                                .onChange(of: selectedItem) { _, newItem in
                                    if let item = newItem {
                                        unitCostText = String(format: "%.2f", item.costPrice)
                                    }
                                }
                                
                                HStack(spacing: APSpacing.md) {
                                    TextField("Quantity", text: $quantityText)
                                        .keyboardType(.decimalPad)
                                        .padding(APSpacing.sm)
                                        .background(Color.appBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                    
                                    TextField("Unit Cost", text: $unitCostText)
                                        .keyboardType(.decimalPad)
                                        .padding(APSpacing.sm)
                                        .background(Color.appBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                    
                                    Button("add_btn_label".t) {
                                        addLineItem()
                                    }
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, APSpacing.lg)
                                    .padding(.vertical, APSpacing.sm)
                                    .background(Color.appTeal)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                    .disabled(selectedItem == nil || quantityText.isEmpty || unitCostText.isEmpty)
                                }
                            }
                            .padding(APSpacing.md)
                            .background(Color.appBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                    .padding()
                }
            }
            .navigationTitle("new_po_draft_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }.foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("save_draft_btn".t) {
                        saveDraft()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.appTeal)
                    .disabled(poNumber.isEmpty || selectedSupplier == nil || lineItems.isEmpty)
                }
            }
            .onAppear {
                poNumber = "PO-\(DateFormatter.orderDateFormat().string(from: Date()))-\(Int.random(in: 10...99))"
            }
        }
    }
    
    private func addLineItem() {
        guard let item = selectedItem,
              let qty = Double(quantityText), qty > 0,
              let cost = Double(unitCostText), cost >= 0 else {
            return
        }
        
        lineItems.append((item: item, qty: qty, cost: cost))
        quantityText = ""
        selectedItem = nil
    }
    
    private func saveDraft() {
        guard let supplier = selectedSupplier else { return }
        let vm = InventoryViewModel(modelContext: modelContext)
        
        let tupleList = lineItems.map { (item: $0.item, qtyOrdered: $0.qty, unitCost: $0.cost) }
        vm.createPurchaseOrder(poNumber: poNumber, supplier: supplier, branch: activeBranch, itemsList: tupleList, notes: notes.isEmpty ? nil : notes)
        dismiss()
    }
}

// ── PURCHASE ORDER DETAIL VIEW ───────────────────────────────────────────────
struct PurchaseOrderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let po: PurchaseOrder
    @State private var showingReceiveSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.lg) {
                        
                        // Summary Card
                        VStack(alignment: .leading, spacing: APSpacing.md) {
                            HStack {
                                Text(po.poNumber)
                                    .font(.title2).fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                detailStatusBadge(po.status)
                            }
                            
                            Divider().background(Color.appDivider)
                            
                            VStack(alignment: .leading, spacing: APSpacing.xs) {
                                Text("po_detail_supplier_template".t) + Text(" ") + Text(po.supplier?.name ?? "Unknown").bold()
                                Text("po_detail_branch_template".t) + Text(" ") + Text(po.branch?.name ?? "Unknown").bold()
                                Text("po_detail_ordered_template".t) + Text(" ") + Text(po.orderDate.formatted(date: .abbreviated, time: .shortened)).bold()
                                if let del = po.deliveryDate {
                                    Text("po_detail_delivery_template".t) + Text(" ") + Text(del.formatted(date: .abbreviated, time: .shortened)).bold()
                                }
                                if let inv = po.invoiceNumber, !inv.isEmpty {
                                    Text("po_invoice_lbl".t) + Text(" ") + Text(inv).bold()
                                }
                                if let taxInv = po.taxInvoiceNumber, !taxInv.isEmpty {
                                    Text("po_tax_invoice_lbl".t) + Text(" ") + Text(taxInv).bold()
                                }
                                let lineTotal = po.items.reduce(0.0) { $0 + ($1.quantityOrdered * $1.unitCost) }
                                let total = po.grandTotal ?? lineTotal
                                Text("po_grand_total_lbl".t) + Text(" ") + Text(String(format: "฿%.2f", total)).bold()
                                if let tax = po.taxAmount, tax > 0 {
                                    Text("po_tax_amount_lbl".t) + Text(" ") + Text(String(format: "฿%.2f", tax)).bold()
                                }
                                if let note = po.notes, !note.isEmpty {
                                    Text(String(format: "po_detail_notes_template".t, note))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .padding(.top, 4)
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        // Action panel
                        if po.status == "draft" {
                            Button(action: sendPO) {
                                Label("send_po_to_supplier".t, systemImage: "paperplane")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appTeal)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                            }
                        } else if po.status == "sent" || po.status == "partially_received" {
                            Button(action: { showingReceiveSheet = true }) {
                                Label("receive_order_deliveries".t, systemImage: "shippingbox")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appTeal)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                            }
                        }
                        
                        // PO Items List
                        Text("po_ordered_products_header".t)
                            .font(.caption).fontWeight(.bold).foregroundColor(.textSecondary).tracking(1.0)
                        
                        VStack(spacing: APSpacing.md) {
                            ForEach(po.items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.inventoryItem?.name ?? "Unknown")
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                        Text(String(format: "Cost: ฿%.2f | Ordered: %.2f %@", item.unitCost, item.quantityOrdered, item.inventoryItem?.unit ?? ""))
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    
                                    if po.status == "received" {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(String(format: "Received: %.2f %@", item.quantityReceived, item.inventoryItem?.unit ?? ""))
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundColor(.appTeal)
                                            Text(String(format: "Total: ฿%.2f", item.quantityReceived * item.unitCost))
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                    } else {
                                        Text(String(format: "฿%.2f", item.quantityOrdered * item.unitCost))
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.appTeal)
                                    }
                                }
                                Divider().background(Color.appDivider)
                            }
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        // Cancel Button (Draft / Sent / Partially Received)
                        if po.status == "draft" || po.status == "sent" || po.status == "partially_received" {
                            Button(action: cancelPO) {
                                Label("cancel_purchase_order".t, systemImage: "xmark.circle")
                                    .foregroundColor(.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                                    .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                            }
                        }
                        
                        // Delete Button (Draft / Sent only)
                        if po.status != "received" && po.status != "cancelled" {
                            Button(role: .destructive, action: deletePO) {
                                Label("delete_purchase_order".t, systemImage: "trash")
                                    .foregroundColor(.appRose)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appRose.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("po_info_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn_label".t) { dismiss() }.foregroundColor(.textPrimary)
                }
            }
            .sheet(isPresented: $showingReceiveSheet) {
                ReceivePurchaseOrderSheet(po: po) {
                    dismiss()
                }
            }
        }
    }
    
    private func sendPO() {
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.sendPurchaseOrder(po: po)
        dismiss()
    }
    
    private func deletePO() {
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.deletePurchaseOrder(po: po)
        dismiss()
    }
    
    private func cancelPO() {
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.cancelPurchaseOrder(po: po)
        dismiss()
    }
    
    @ViewBuilder
    private func detailStatusBadge(_ status: String) -> some View {
        switch status {
        case "draft":
            APBadge(text: "Draft", color: .appTeal, icon: "pencil")
        case "sent":
            APBadge(text: "Sent", color: .appAmber, icon: "paperplane.fill")
        case "received":
            APBadge(text: "Received", color: .appRose, icon: "shippingbox.fill")
        case "partially_received":
            APBadge(text: "Partial", color: .appAmber, icon: "shippingbox")
        case "cancelled":
            APBadge(text: "Cancelled", color: .textSecondary, icon: "xmark.circle.fill")
        default:
            APBadge(text: status.capitalized, color: .textSecondary, icon: "questionmark")
        }
    }
}

// ── RECEIVE PURCHASE ORDER SHEET ─────────────────────────────────────────────
struct ReceivePurchaseOrderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager
    
    let po: PurchaseOrder
    var onComplete: () -> Void
    
    // Key is InventoryItem UUID, value is received quantity, cost, expiry date, lot number
    @State private var receivedData: [UUID: (qty: Double, cost: Double)] = [:]
    @State private var expiryData: [UUID: (hasExpiry: Bool, expiryDate: Date, lotNumber: String)] = [:]
    @State private var notes = ""
    @State private var showingScanner = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.lg) {
                        
                        // Alert Box
                        VStack(alignment: .leading, spacing: 4) {
                            Text("po_delivery_verification_title".t)
                                .font(.headline).foregroundColor(.textPrimary)
                            Text("po_delivery_verification_desc".t)
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        // Receive Controls
                        HStack {
                            Button(action: receiveAllItems) {
                                Label("receive_all_items_btn".t, systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, APSpacing.md)
                                    .padding(.vertical, APSpacing.sm)
                                    .background(Color.appTeal)
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            Button(action: { showingScanner = true }) {
                                Label("scan_barcode_btn".t, systemImage: "barcode.viewfinder")
                                    .font(.subheadline)
                                    .foregroundColor(.appTeal)
                                    .padding(.horizontal, APSpacing.md)
                                    .padding(.vertical, APSpacing.sm)
                                    .background(Color.appTeal.opacity(0.1))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.appTeal, lineWidth: 1))
                            }
                        }
                        
                        // PO Items to receive
                        VStack(spacing: APSpacing.md) {
                            ForEach(po.items) { item in
                                let itemId = item.inventoryItem?.id ?? UUID()
                                let data = receivedData[itemId] ?? (qty: 0.0, cost: item.unitCost)
                                
                                VStack(alignment: .leading, spacing: APSpacing.sm) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.inventoryItem?.name ?? "Unknown")
                                                .font(.headline)
                                                .foregroundColor(.textPrimary)
                                            if let barcode = item.inventoryItem?.barcode {
                                                Text(String(format: "po_verify_barcode_template".t, barcode))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.appTeal)
                                            }
                                            Text(String(format: "Ordered: %.2f | Cost: ฿%.2f", item.quantityOrdered, item.unitCost))
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    HStack(spacing: APSpacing.md) {
                                        // Qty Input
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("po_verify_qty_received".t)
                                                .font(.system(size: 9, weight: .semibold)).foregroundColor(.textSecondary)
                                            HStack {
                                                TextField("0.0", value: Binding(
                                                    get: { data.qty },
                                                    set: { newQty in receivedData[itemId] = (qty: newQty, cost: data.cost) }
                                                ), format: .number)
                                                .keyboardType(.decimalPad)
                                                .padding(6)
                                                .background(Color.appBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                                .multilineTextAlignment(.center)
                                                .foregroundColor(.textPrimary)
                                                
                                                Text(item.inventoryItem?.unit ?? "")
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                            }
                                        }
                                        
                                        // Cost Input
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("po_verify_unit_cost".t)
                                                .font(.system(size: 9, weight: .semibold)).foregroundColor(.textSecondary)
                                            TextField("0.0", value: Binding(
                                                get: { data.cost },
                                                set: { newCost in receivedData[itemId] = (qty: data.qty, cost: newCost) }
                                            ), format: .number)
                                            .keyboardType(.decimalPad)
                                            .padding(6)
                                            .background(Color.appBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(.textPrimary)
                                        }
                                    }
                                    
                                    // ── Expiry / Lot fields ──
                                    let expiry = expiryData[itemId] ?? (hasExpiry: false, expiryDate: Date(), lotNumber: "PO-\(po.poNumber)")
                                    
                                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                                        Toggle(isOn: Binding(
                                            get: { expiry.hasExpiry },
                                            set: { newVal in expiryData[itemId] = (hasExpiry: newVal, expiryDate: expiry.expiryDate, lotNumber: expiry.lotNumber) }
                                        )) {
                                            Text("po_verify_has_expiry".t)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.textSecondary)
                                        }
                                        .tint(.appTeal)
                                        
                                        if expiry.hasExpiry {
                                            HStack(spacing: APSpacing.md) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("po_verify_expiry_date".t)
                                                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.textSecondary)
                                                    DatePicker(
                                                        "",
                                                        selection: Binding(
                                                            get: { expiry.expiryDate },
                                                            set: { newDate in expiryData[itemId] = (hasExpiry: true, expiryDate: newDate, lotNumber: expiry.lotNumber) }
                                                        ),
                                                        displayedComponents: .date
                                                    )
                                                    .labelsHidden()
                                                    .padding(4)
                                                    .background(Color.appBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("po_verify_lot_number".t)
                                                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.textSecondary)
                                                    TextField("PO-\(po.poNumber)", text: Binding(
                                                        get: { expiry.lotNumber },
                                                        set: { newLot in expiryData[itemId] = (hasExpiry: true, expiryDate: expiry.expiryDate, lotNumber: newLot) }
                                                    ))
                                                    .padding(6)
                                                    .background(Color.appBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                                    .foregroundColor(.textPrimary)
                                                }
                                            }
                                        }
                                    }
                                }
                                Divider().background(Color.appDivider)
                            }
                        }
                        .padding(APSpacing.md)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
                        
                        // Invoice notes
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("po_verify_notes_label".t)
                                .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary)
                            TextField("Enter invoice reference, discrepancies...", text: $notes)
                                .padding(APSpacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("receive_delivery_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }.foregroundColor(.textPrimary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("commit_btn".t) {
                        commitReceive()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.appTeal)
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(onScan: handleBarcodeScan)
            }
            .onAppear {
                // Pre-populate keys
                for item in po.items {
                    if let itemId = item.inventoryItem?.id {
                        let remaining = max(0.0, item.quantityOrdered - item.quantityReceived)
                        receivedData[itemId] = (qty: remaining, cost: item.unitCost)
                        expiryData[itemId] = (hasExpiry: false, expiryDate: Date(), lotNumber: "PO-\(po.poNumber)")
                    }
                }
            }
        }
    }
    
    private func receiveAllItems() {
        for item in po.items {
            if let itemId = item.inventoryItem?.id {
                let remaining = max(0.0, item.quantityOrdered - item.quantityReceived)
                receivedData[itemId] = (qty: remaining, cost: item.unitCost)
                if expiryData[itemId] == nil {
                    expiryData[itemId] = (hasExpiry: false, expiryDate: Date(), lotNumber: "PO-\(po.poNumber)")
                }
            }
        }
    }
    
    private func handleBarcodeScan(code: String) {
        // Find PO item matching barcode
        if let matchingItem = po.items.first(where: { $0.inventoryItem?.barcode == code || $0.inventoryItem?.sku == code }) {
            if let itemId = matchingItem.inventoryItem?.id {
                let current = receivedData[itemId] ?? (qty: 0.0, cost: matchingItem.unitCost)
                receivedData[itemId] = (qty: current.qty + 1.0, cost: current.cost)
                if expiryData[itemId] == nil {
                    expiryData[itemId] = (hasExpiry: false, expiryDate: Date(), lotNumber: "PO-\(po.poNumber)")
                }
                APHaptic.trigger()
            }
        }
    }
    
    private func commitReceive() {
        guard sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage) else { return }
        let vm = InventoryViewModel(modelContext: modelContext)
        
        var receivedItemsList: [UUID: (qtyReceived: Double, unitCost: Double, expiryDate: Date?, lotNumber: String?)] = [:]
        for (key, val) in receivedData {
            let exp = expiryData[key]
            receivedItemsList[key] = (
                qtyReceived: val.qty,
                unitCost: val.cost,
                expiryDate: exp?.hasExpiry == true ? exp?.expiryDate : nil,
                lotNumber: exp?.lotNumber
            )
        }
        
        vm.commitPurchaseOrderReceive(po: po, receivedItems: receivedItemsList, notes: notes)
        dismiss()
        onComplete()
    }
}
