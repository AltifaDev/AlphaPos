import SwiftUI
import SwiftData

struct PurchaseOrderManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let activeBranch: Branch
    
    @Query(sort: \PurchaseOrder.orderDate, order: .reverse) private var allPOs: [PurchaseOrder]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    
    @State private var showingCreateSheet = false
    @State private var selectedPO: PurchaseOrder?
    @State private var showingNoSupplierAlert = false
    
    private var filteredPOs: [PurchaseOrder] {
        allPOs.filter { $0.branch?.id == activeBranch.id }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: APSpacing.lg) {
                    // Quick stats
                    HStack(spacing: APSpacing.md) {
                        statCard(title: "Drafts", count: filteredPOs.filter { $0.status == "draft" }.count, color: .appTeal)
                        statCard(title: "Sent / Pending", count: filteredPOs.filter { $0.status == "sent" || $0.status == "partially_received" }.count, color: .appAmber)
                        statCard(title: "Received", count: filteredPOs.filter { $0.status == "received" }.count, color: .appRose)
                    }
                    .padding(.horizontal)
                    .padding(.top, APSpacing.sm)
                    
                    if suppliers.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.appAmber)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("po_no_suppliers_title".t)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                Text("po_no_suppliers_desc".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.appAmber.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appAmber.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    if filteredPOs.isEmpty {
                        VStack(spacing: APSpacing.md) {
                            Spacer()
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 64))
                                .foregroundColor(.textSecondary.opacity(0.5))
                            Text("po_no_orders_title".t)
                                .font(.headline)
                                .foregroundColor(.textSecondary)
                            Text("po_no_orders_desc".t)
                                .font(.caption)
                                .foregroundColor(.textSecondary.opacity(0.8))
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: APSpacing.md) {
                                ForEach(filteredPOs) { po in
                                    poRow(po)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Purchase Orders — \(activeBranch.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn_label".t) {
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if suppliers.isEmpty {
                            showingNoSupplierAlert = true
                        } else {
                            showingCreateSheet = true
                        }
                    }) {
                        Label("add_new_po_btn".t, systemImage: "plus")
                            .foregroundColor(.appTeal)
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
        }
        .apColorScheme()
    }
    
    @ViewBuilder
    private func statCard(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textSecondary)
            Text("\(count)")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func poRow(_ po: PurchaseOrder) -> some View {
        Button(action: { selectedPO = po }) {
            HStack(spacing: APSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(po.poNumber)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        poStatusBadge(po.status)
                    }
                    
                    Text("Supplier: \(po.supplier?.name ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    
                    Text(String(format: "po_ordered_lbl_template".t, po.orderDate.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "po_items_count_template".t, po.items.count))
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                    
                    let totalCost = po.items.reduce(0.0) { $0 + ($1.quantityOrdered * $1.unitCost) }
                    Text(String(format: "฿%.2f", totalCost))
                        .font(.headline)
                        .foregroundColor(.appTeal)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.textSecondary.opacity(0.5))
            }
            .padding(APSpacing.md)
            .background(Color.appSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private func poStatusBadge(_ status: String) -> some View {
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
    
    let po: PurchaseOrder
    var onComplete: () -> Void
    
    // Key is InventoryItem UUID, value is received quantity and cost
    @State private var receivedData: [UUID: (qty: Double, cost: Double)] = [:]
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
                    }
                }
            }
        }
    }
    
    private func receiveAllItems() {
        for item in po.items {
            if let itemId = item.inventoryItem?.id {
                receivedData[itemId] = (qty: item.quantityOrdered, cost: item.unitCost)
            }
        }
    }
    
    private func handleBarcodeScan(code: String) {
        // Find PO item matching barcode
        if let matchingItem = po.items.first(where: { $0.inventoryItem?.barcode == code || $0.inventoryItem?.sku == code }) {
            if let itemId = matchingItem.inventoryItem?.id {
                let current = receivedData[itemId] ?? (qty: 0.0, cost: matchingItem.unitCost)
                receivedData[itemId] = (qty: current.qty + 1.0, cost: current.cost)
                APHaptic.trigger()
            }
        }
    }
    
    private func commitReceive() {
        let vm = InventoryViewModel(modelContext: modelContext)
        
        var receivedItemsList: [UUID: (qtyReceived: Double, unitCost: Double)] = [:]
        for (key, val) in receivedData {
            receivedItemsList[key] = (qtyReceived: val.qty, unitCost: val.cost)
        }
        
        vm.commitPurchaseOrderReceive(po: po, receivedItems: receivedItemsList, notes: notes)
        dismiss()
        onComplete()
    }
}
