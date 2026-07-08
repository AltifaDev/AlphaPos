import SwiftUI
import SwiftData

struct ExpenseTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    @Query(sort: \Branch.name) private var branches: [Branch]

    @AppStorage("active_branch_id") private var activeBranchId = ""

    // Filters & Navigation States
    @State private var searchText = ""
    @State private var selectedCategoryFilter = "All"
    @State private var periodFilter = 1 // 0: Daily, 1: Monthly (Default to Monthly ledger)
    @State private var selectedExpense: Expense? = nil

    // Sheet States
    @State private var showingForm = false
    @State private var editingExpense: Expense? = nil

    // Form Inputs
    @State private var titleInput = ""
    @State private var invoiceNoInput = ""
    @State private var categoryInput = "Raw Materials"
    @State private var quantityInput = "1.0"
    @State private var unitInput = "pcs"
    @State private var unitPriceInput = "0.0"
    @State private var vatOption = 0 // 0: None, 1: 7% Inclusive, 2: 7% Exclusive
    @State private var selectedSupplierId: UUID? = nil
    @State private var paymentMethodInput = "Cash"
    @State private var statusInput = "Paid"
    @State private var isCapExInput = false
    @State private var notesInput = ""
    @State private var dateInput = Date()

    init() {}

    private var activeBranch: Branch? {
        branches.first(where: { $0.id.uuidString == activeBranchId })
    }

    // Filtered Ledger List
    private var filteredExpenses: [Expense] {
        let branchFiltered = expenses.filter { expense in
            if expense.isDeleted { return false }
            if let branch = activeBranch {
                return expense.branch?.id == branch.id
            }
            return true
        }

        let searchFiltered = branchFiltered.filter { expense in
            if searchText.isEmpty { return true }
            let term = searchText.lowercased()
            return expense.title.lowercased().contains(term) ||
                   (expense.invoiceNo ?? "").lowercased().contains(term) ||
                   (expense.notes ?? "").lowercased().contains(term)
        }

        let categoryFiltered = searchFiltered.filter { expense in
            if selectedCategoryFilter == "All" { return true }
            return expense.category == selectedCategoryFilter
        }

        let periodFiltered = categoryFiltered.filter { expense in
            let calendar = Calendar.current
            if periodFilter == 0 {
                // Today
                return calendar.isDateInToday(expense.date)
            } else {
                // This month
                return calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
            }
        }

        return periodFiltered
    }

    // Computed Summary Metrics
    private var monthlyTotal: Double {
        let calendar = Calendar.current
        return expenses.filter { expense in
            !expense.isDeleted &&
            (activeBranch == nil || expense.branch?.id == activeBranch?.id) &&
            calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
        }.reduce(0.0) { $0 + $1.amount }
    }

    private var opExTotal: Double {
        let calendar = Calendar.current
        return expenses.filter { expense in
            !expense.isDeleted &&
            !expense.isCapEx &&
            (activeBranch == nil || expense.branch?.id == activeBranch?.id) &&
            calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
        }.reduce(0.0) { $0 + $1.amount }
    }

    private var capExTotal: Double {
        let calendar = Calendar.current
        return expenses.filter { expense in
            !expense.isDeleted &&
            expense.isCapEx &&
            (activeBranch == nil || expense.branch?.id == activeBranch?.id) &&
            calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
        }.reduce(0.0) { $0 + $1.amount }
    }

    // Dynamic values computed during Form entry
    private var formCalculatedValues: (subtotal: Double, vat: Double, total: Double) {
        let qty = Double(quantityInput) ?? 0.0
        let price = Double(unitPriceInput) ?? 0.0
        let baseAmount = qty * price

        switch vatOption {
        case 1: // 7% Inclusive
            let total = baseAmount
            let vat = total - (total / 1.07)
            let subtotal = total - vat
            return (subtotal, vat, total)
        case 2: // 7% Exclusive
            let subtotal = baseAmount
            let vat = subtotal * 0.07
            let total = subtotal + vat
            return (subtotal, vat, total)
        default: // None
            return (baseAmount, 0.0, baseAmount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sleek Compact Header (Metrics Bar)
            compactMetricsBar

            Divider().background(Color.appDivider)

            // Advanced Filters Toolbar
            advancedFilterToolbar

            Divider().background(Color.appDivider)

            // Master-Detail Split Workspace
            HStack(spacing: 0) {
                // Left Panel: Ledger Table (Master List)
                VStack(spacing: 0) {
                    if filteredExpenses.isEmpty {
                        emptyStateView
                    } else {
                        ledgerTableListView
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().background(Color.appDivider)

                // Right Panel: Detail Inspector (Detail Panel)
                detailInspectorView
                    .frame(width: 380)
                    .background(Color.appSurface)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showingForm) {
            addEditExpenseFormView
        }
        .onAppear {
            if selectedExpense == nil, let first = filteredExpenses.first {
                selectedExpense = first
            }
        }
    }

    // MARK: - Compact Metrics Bar
    private var compactMetricsBar: some View {
        HStack(spacing: APSpacing.lg) {
            HStack(spacing: APSpacing.xs) {
                Image(systemName: "banknote")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 10))
                Text("expense_monthly".t + ":")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                Text(String(format: "฿%.2f", monthlyTotal))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }

            HStack(spacing: APSpacing.xs) {
                Image(systemName: "briefcase")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 10))
                Text("OpEx:")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                Text(String(format: "฿%.2f", opExTotal))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.appTeal)
            }

            HStack(spacing: APSpacing.xs) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 10))
                Text("CapEx:")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                Text(String(format: "฿%.2f", capExTotal))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.appAccent)
            }

            Spacer()
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.vertical, 6)
        .background(Color.appSurface)
    }

    // MARK: - Advanced Filters Toolbar
    private var advancedFilterToolbar: some View {
        HStack(spacing: APSpacing.sm) {
            // Search Text Field
            HStack(spacing: APSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 9))
                TextField("search_hint".t + " (Inv #, Item)", text: $searchText)
                    .font(.system(size: 10))
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                            .font(.system(size: 9))
                    }
                }
            }
            .padding(4)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .frame(width: 200)

            // Category Selector
            Picker("Category", selection: $selectedCategoryFilter) {
                Text("All").tag("All")
                Text("expense_category_raw_materials".t).tag("Raw Materials")
                Text("expense_category_equipment".t).tag("Equipment")
                Text("expense_category_consumables".t).tag("Consumables")
                Text("expense_category_maintenance".t).tag("Maintenance")
                Text("expense_category_other".t).tag("Other")
            }
            .pickerStyle(.menu)
            .font(.system(size: 9))
            .padding(.horizontal, APSpacing.xs)
            .padding(.vertical, 3)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )

            // Period Segmented View
            Picker("Period", selection: $periodFilter) {
                Text("expense_today".t).tag(0)
                Text("expense_monthly".t).tag(1)
            }
            .pickerStyle(.segmented)
            .scaleEffect(0.9)
            .frame(width: 160)

            Spacer()

            // Add Expense Button
            Button(action: { openAddExpenseForm() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("expense_add".t)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, 4)
                .background(APGradient.accent)
                .cornerRadius(APRadius.pill)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.sm)
        .background(Color.appSurface)
    }

    // MARK: - Ledger Table List
    private var ledgerTableListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Table Columns Header
                HStack(spacing: 0) {
                    Text("expense_date".t)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(width: 70, alignment: .leading)

                    Text("Ref No")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(width: 80, alignment: .leading)

                    Text("expense_title".t)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("expense_category".t)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(width: 90, alignment: .leading)

                    Text("expense_amount".t)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(width: 80, alignment: .trailing)

                    Text("Status")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh.opacity(0.4))

                // Rows
                ForEach(filteredExpenses) { expense in
                    HStack(spacing: 0) {
                        // Date
                        Text(formatShortDate(expense.date))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                            .frame(width: 70, alignment: .leading)

                        // Invoice No
                        Text(expense.invoiceNo ?? "—")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .frame(width: 80, alignment: .leading)

                        // Title
                        VStack(alignment: .leading, spacing: 1) {
                            Text(expense.title)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.textPrimary)
                            if let supplierName = expense.supplier?.name {
                                Text("Supplier: \(supplierName)")
                                    .font(.system(size: 7))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Category Tag
                        HStack(spacing: 3) {
                            Circle()
                                .fill(getCategoryColor(expense.category))
                                .frame(width: 4, height: 4)
                            Text(getLocalizedCategoryName(expense.category))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(getCategoryColor(expense.category).opacity(0.1))
                        .cornerRadius(APRadius.sm)
                        .frame(width: 90, alignment: .leading)

                        // Amount
                        Text(String(format: "฿%.2f", expense.amount))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .frame(width: 80, alignment: .trailing)

                        // Status Badge
                        Text(expense.status.uppercased())
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(expense.status == "Paid" ? .appTeal : .appRose)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(expense.status == "Paid" ? Color.appTeal.opacity(0.12) : Color.appRose.opacity(0.12))
                            .cornerRadius(APRadius.sm)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, APSpacing.sm)
                    .padding(.vertical, 6)
                    .background(selectedExpense?.id == expense.id ? Color.appAccent.opacity(0.08) : Color.appSurface)
                    .overlay(
                        Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedExpense = expense
                    }
                }
            }
        }
    }

    // MARK: - Detail Inspector View
    private var detailInspectorView: some View {
        VStack(spacing: 0) {
            if let expense = selectedExpense {
                // Header Details
                VStack(alignment: .leading, spacing: APSpacing.xs) {
                    Text("EXPENSE DETAILS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textSecondary)

                    Text(expense.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)

                    if let invNo = expense.invoiceNo {
                        Text(formatLongDate(expense.date) + " | #" + invNo)
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                    } else {
                        Text(formatLongDate(expense.date))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                    }

                    HStack(spacing: 4) {
                        Text(getLocalizedCategoryName(expense.category))
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(getCategoryColor(expense.category).opacity(0.12))
                            .cornerRadius(APRadius.sm)

                        Text(expense.isCapEx ? "CAPITAL ASSET (CAPEX)" : "OPERATING EXPENSE (OPEX)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(expense.isCapEx ? .appAccent : .appTeal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(expense.isCapEx ? Color.appAccent.opacity(0.12) : Color.appTeal.opacity(0.12))
                            .cornerRadius(APRadius.sm)
                    }
                }
                .padding(APSpacing.sm)

                Divider().background(Color.appDivider)

                // Content Information
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.sm) {
                        // Supplier Info
                        if let supplier = expense.supplier {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Supplier")
                                    .font(.system(size: 8)).foregroundColor(.textSecondary)
                                Text(supplier.name)
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.textPrimary)
                                if let contact = supplier.contactName {
                                    Text("Contact: " + contact)
                                        .font(.system(size: 8)).foregroundColor(.textSecondary)
                                }
                            }
                        }

                        // Item Details & Quantities
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Line Calculations")
                                .font(.system(size: 8)).foregroundColor(.textSecondary)

                            HStack {
                                Text("Qty:")
                                    .font(.system(size: 9))
                                Spacer()
                                Text(String(format: "%.1f %@", expense.quantity, expense.unit ?? ""))
                                    .font(.system(size: 9, weight: .medium))
                            }

                            HStack {
                                Text("Unit Price:")
                                    .font(.system(size: 9))
                                Spacer()
                                Text(String(format: "฿%.2f", expense.unitPrice))
                                    .font(.system(size: 9, weight: .medium))
                            }

                            HStack {
                                Text("Subtotal:")
                                    .font(.system(size: 9))
                                Spacer()
                                Text(String(format: "฿%.2f", expense.amount - expense.vatAmount))
                                    .font(.system(size: 9, weight: .medium))
                            }

                            HStack {
                                Text(String(format: "VAT (%.0f%%):", expense.vatRate))
                                    .font(.system(size: 9))
                                Spacer()
                                Text(String(format: "+ ฿%.2f", expense.vatAmount))
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                            }

                            Divider()

                            HStack {
                                Text("Total Amount:")
                                    .font(.system(size: 9, weight: .bold))
                                Spacer()
                                Text(String(format: "฿%.2f", expense.amount))
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        .padding(APSpacing.sm)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)

                        // Payment Details
                        VStack(alignment: .leading, spacing: 2) {
                            infoRow(label: "Payment Method", value: expense.paymentMethod)
                            infoRow(label: "Status", value: expense.status)
                        }

                        // Notes
                        if let notes = expense.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notes")
                                    .font(.system(size: 8)).foregroundColor(.textSecondary)
                                Text(notes)
                                    .font(.system(size: 9))
                                    .foregroundColor(.textPrimary)
                                    .padding(APSpacing.xs)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                            }
                        }
                    }
                    .padding(APSpacing.sm)
                }

                Spacer()

                Divider().background(Color.appDivider)

                // Action Buttons
                HStack(spacing: APSpacing.sm) {
                    Button(action: { deleteSelectedExpense(expense) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.appRose)
                            .font(.system(size: 10))
                            .padding(8)
                            .background(Color.appRose.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { openEditExpenseForm(expense) }) {
                        HStack {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                            Text("Edit Expense")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(APGradient.accent)
                        .cornerRadius(APRadius.md)
                    }
                    .buttonStyle(.plain)
                }
                .padding(APSpacing.sm)
            } else {
                Spacer()
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.5))
                    .padding()
                Text("Select an item to view details")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 8)).foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .semibold)).foregroundColor(.textPrimary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add/Edit Expense Form View
    private var addEditExpenseFormView: some View {
        NavigationStack {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Title (e.g. Wooden Chairs)", text: $titleInput)
                        .foregroundColor(.textPrimary)

                    TextField("Invoice / Ref Number", text: $invoiceNoInput)
                        .foregroundColor(.textPrimary)

                    Picker("Category", selection: $categoryInput) {
                        Text("expense_category_raw_materials".t).tag("Raw Materials")
                        Text("expense_category_equipment".t).tag("Equipment")
                        Text("expense_category_consumables".t).tag("Consumables")
                        Text("expense_category_maintenance".t).tag("Maintenance")
                        Text("expense_category_other".t).tag("Other")
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Quantities & Cost (Calculated)")) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("1.0", text: $quantityInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.textPrimary)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Unit of Measure")
                        Spacer()
                        TextField("pcs", text: $unitInput)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.textPrimary)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Unit Price")
                        Spacer()
                        TextField("0.00", text: $unitPriceInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.textPrimary)
                            .frame(width: 150)
                    }

                    Picker("VAT Taxation", selection: $vatOption) {
                        Text("None (0%)").tag(0)
                        Text("7% Inclusive").tag(1)
                        Text("7% Exclusive").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    // Live Calculation Display
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subtotal: ฿\(formCalculatedValues.subtotal, specifier: "%.2f")")
                                .font(.caption).foregroundColor(.textSecondary)
                            Text("VAT (7%): ฿\(formCalculatedValues.vat, specifier: "%.2f")")
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Text("Net Total: ฿\(formCalculatedValues.total, specifier: "%.2f")")
                            .font(.system(.body, design: .rounded)).fontWeight(.heavy)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.vertical, 6)
                }

                Section(header: Text("Accounting & Supplier Details")) {
                    Picker("Supplier", selection: $selectedSupplierId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(suppliers.filter { !$0.isDeleted }) { supplier in
                            Text(supplier.name).tag(supplier.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Payment Method", selection: $paymentMethodInput) {
                        Text("Cash").tag("Cash")
                        Text("Credit Card").tag("Credit Card")
                        Text("Bank Transfer").tag("Bank Transfer")
                        Text("Accounts Payable (Unpaid)").tag("Accounts Payable")
                    }
                    .pickerStyle(.menu)

                    Picker("Payment Status", selection: $statusInput) {
                        Text("Paid").tag("Paid")
                        Text("Unpaid").tag("Unpaid")
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $isCapExInput) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Capital Expenditure (CapEx)")
                                .fontWeight(.medium)
                            Text("Check if asset lasts >1 year (furniture, computers, machines)")
                                .font(.caption2).foregroundColor(.textSecondary)
                        }
                    }

                    DatePicker("Expense Date", selection: $dateInput, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Notes")) {
                    TextField("Write any specific details...", text: $notesInput, axis: .vertical)
                        .lineLimit(3...5)
                        .foregroundColor(.textPrimary)
                }
            }
            .navigationTitle(editingExpense == nil ? "expense_add".t : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        showingForm = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        saveFormExpense()
                    }
                    .disabled(titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(quantityInput) == nil || Double(unitPriceInput) == nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var emptyStateView: some View {
        VStack(spacing: APSpacing.sm) {
            Spacer().frame(height: 40)
            Image(systemName: "book.pages")
                .font(.system(size: 32))
                .foregroundColor(.textSecondary.opacity(0.6))
                .padding(APSpacing.md)
                .background(Color.appSurfaceHigh)
                .clipShape(Circle())

            Text("No Expense Records Found")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("Add expense records to track invoice details, suppliers, VAT and equipment purchases.")
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button(action: { openAddExpenseForm() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("expense_add".t)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, 6)
                .background(APGradient.accent)
                .cornerRadius(APRadius.pill)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Helpers & Database Mutations
    private func openAddExpenseForm() {
        editingExpense = nil
        titleInput = ""
        invoiceNoInput = ""
        categoryInput = "Raw Materials"
        quantityInput = "1.0"
        unitInput = "pcs"
        unitPriceInput = "0.00"
        vatOption = 0
        selectedSupplierId = nil
        paymentMethodInput = "Cash"
        statusInput = "Paid"
        isCapExInput = false
        notesInput = ""
        dateInput = Date()
        showingForm = true
    }

    private func openEditExpenseForm(_ expense: Expense) {
        editingExpense = expense
        titleInput = expense.title
        invoiceNoInput = expense.invoiceNo ?? ""
        categoryInput = expense.category
        quantityInput = String(format: "%.1f", expense.quantity)
        unitInput = expense.unit ?? "pcs"
        unitPriceInput = String(format: "%.2f", expense.unitPrice)

        // Match VAT options
        if expense.vatRate > 0 {
            // Check if amount == subtotal + vat or inclusive
            let computedSub = expense.quantity * expense.unitPrice
            if abs(expense.amount - computedSub) < 1.0 {
                // VAT inclusive (amount is equal to qty*price)
                vatOption = 1
            } else {
                vatOption = 2 // VAT Exclusive
            }
        } else {
            vatOption = 0
        }

        selectedSupplierId = expense.supplier?.id
        paymentMethodInput = expense.paymentMethod
        statusInput = expense.status
        isCapExInput = expense.isCapEx
        notesInput = expense.notes ?? ""
        dateInput = expense.date
        showingForm = true
    }

    private func saveFormExpense() {
        let calculations = formCalculatedValues
        let qty = Double(quantityInput) ?? 1.0
        let price = Double(unitPriceInput) ?? 0.0
        let vatRateValue = vatOption > 0 ? 7.0 : 0.0

        let targetSupplier = suppliers.first(where: { $0.id == selectedSupplierId })

        if let editing = editingExpense {
            // Edit mode
            editing.title = titleInput.trimmingCharacters(in: .whitespacesAndNewlines)
            editing.invoiceNo = invoiceNoInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if editing.invoiceNo?.isEmpty == true { editing.invoiceNo = nil }
            editing.category = categoryInput
            editing.quantity = qty
            editing.unit = unitInput.trimmingCharacters(in: .whitespacesAndNewlines)
            editing.unitPrice = price
            editing.amount = calculations.total
            editing.vatRate = vatRateValue
            editing.vatAmount = calculations.vat
            editing.paymentMethod = paymentMethodInput
            editing.status = statusInput
            editing.isCapEx = isCapExInput
            editing.notes = notesInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if editing.notes?.isEmpty == true { editing.notes = nil }
            editing.supplier = targetSupplier
            editing.date = dateInput

            editing.isSynced = false
            editing.updatedAt = Date()

            // Re-assign selected to trigger UI updates
            selectedExpense = editing
        } else {
            // Add mode
            let newExpense = Expense(
                invoiceNo: invoiceNoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : invoiceNoInput.trimmingCharacters(in: .whitespacesAndNewlines),
                title: titleInput.trimmingCharacters(in: .whitespacesAndNewlines),
                category: categoryInput,
                quantity: qty,
                unit: unitInput.trimmingCharacters(in: .whitespacesAndNewlines),
                unitPrice: price,
                amount: calculations.total,
                vatRate: vatRateValue,
                vatAmount: calculations.vat,
                paymentMethod: paymentMethodInput,
                status: statusInput,
                isCapEx: isCapExInput,
                notes: notesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesInput.trimmingCharacters(in: .whitespacesAndNewlines),
                supplier: targetSupplier,
                branch: activeBranch
            )

            modelContext.insert(newExpense)
            selectedExpense = newExpense
        }

        showingForm = false
    }

    private func deleteSelectedExpense(_ expense: Expense) {
        expense.isDeleted = true
        expense.updatedAt = Date()
        expense.isSynced = false

        // Select another row
        if let idx = filteredExpenses.firstIndex(where: { $0.id == expense.id }) {
            if filteredExpenses.count > 1 {
                if idx > 0 {
                    selectedExpense = filteredExpenses[idx - 1]
                } else {
                    selectedExpense = filteredExpenses[idx + 1]
                }
            } else {
                selectedExpense = nil
            }
        } else {
            selectedExpense = filteredExpenses.first
        }
    }

    // Formatting Helpers
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date)
    }

    private func formatLongDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func getLocalizedCategoryName(_ rawValue: String) -> String {
        switch rawValue {
        case "Raw Materials": return "expense_category_raw_materials".t
        case "Equipment":     return "expense_category_equipment".t
        case "Consumables":   return "expense_category_consumables".t
        case "Maintenance":   return "expense_category_maintenance".t
        default:              return "expense_category_other".t
        }
    }

    private func getCategoryColor(_ rawValue: String) -> Color {
        switch rawValue {
        case "Raw Materials": return Color.appTeal
        case "Equipment":     return Color.appAccent
        case "Consumables":   return Color.orange
        case "Maintenance":   return Color.purple
        default:              return Color.secondary
        }
    }
}
