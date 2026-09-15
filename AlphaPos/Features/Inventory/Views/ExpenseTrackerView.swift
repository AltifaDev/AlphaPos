import SwiftUI
import SwiftData

struct ExpenseTrackerView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]
    @Query(sort: \Branch.name) private var branches: [Branch]

    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

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
    @State private var categoryInput = "Consumables"
    @State private var quantityInput = "1.0"
    @State private var unitInput = "pcs"
    @State private var unitPriceInput = "0.0"
    @State private var vatOption = 0 // 0: None, 1: 7% Inclusive, 2: 7% Exclusive
    @State private var selectedSupplierId: UUID? = nil
    @State private var paymentMethodInput = "Cash"
    @State private var statusInput = "Paid"
    @State private var isCapExInput = false
    @State private var recognitionTypeInput = "operating_expense"
    @State private var expenseNatureInput = "other"
    @State private var isVATRecoverableInput = true
    @State private var isRecurringInput = false
    @State private var recurrenceFrequencyInput = "monthly"
    @State private var serviceStartInput = Date()
    @State private var serviceEndInput = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var assetClassInput = "Furniture & Fixtures"
    @State private var availableForUseInput = Date()
    @State private var usefulLifeMonthsInput = "60"
    @State private var residualValueInput = "0"
    @State private var investmentProjectInput = ""
    @State private var monthlyCashBenefitInput = "0"
    @State private var monthlyIncrementalCostInput = "0"
    @State private var notesInput = ""
    @State private var dateInput = Date()

    init() {}

    private var activeBranch: Branch? {
        guard let selectedID = UUID(uuidString: activeBranchId) else { return nil }
        return branches.first(where: { $0.id == selectedID && !$0.isDeleted })
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
            AccountingMath.normalizedExpenseRecognition(expense.recognitionType, legacyIsCapEx: expense.isCapEx) == "operating_expense" &&
            (activeBranch == nil || expense.branch?.id == activeBranch?.id) &&
            calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
        }.reduce(0.0) { total, expense in
            total + max(0, expense.amount - (expense.isVATRecoverable ? expense.vatAmount : 0))
        }
    }

    private var capExTotal: Double {
        let calendar = Calendar.current
        return expenses.filter { expense in
            !expense.isDeleted &&
            AccountingMath.normalizedExpenseRecognition(expense.recognitionType, legacyIsCapEx: expense.isCapEx) == "fixed_asset" &&
            (activeBranch == nil || expense.branch?.id == activeBranch?.id) &&
            calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month)
        }.reduce(0.0) { total, expense in
            total + max(0, expense.amount - (expense.isVATRecoverable ? expense.vatAmount : 0))
        }
    }

    private var monthlyDepreciationTotal: Double {
        expenses.filter {
            !$0.isDeleted &&
            (activeBranch == nil || $0.branch?.id == activeBranch?.id) &&
            AccountingMath.normalizedExpenseRecognition($0.recognitionType, legacyIsCapEx: $0.isCapEx) == "fixed_asset"
        }.reduce(0) { total, asset in
            total + AccountingMath.monthlyStraightLineDepreciation(
                cost: max(0, asset.amount - (asset.isVATRecoverable ? asset.vatAmount : 0)),
                residualValue: asset.residualValue, usefulLifeMonths: asset.usefulLifeMonths
            )
        }
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
        GeometryReader { geometry in
        VStack(spacing: 0) {
            // Native Header
            pageHeader

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

                if geometry.size.width >= 920 {
                    Divider().background(Color.appDivider)

                    // Keep the inspector only when both panes remain readable.
                    detailInspectorView
                        .frame(width: min(380, geometry.size.width * 0.34))
                        .background(Color.appSurface)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(lm.currentLanguage == .thai ? "ค่าใช้จ่ายและสินทรัพย์" : "Expenses & Asset Register")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { openAddExpenseForm() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("expense_add".t)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(APGradient.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingForm) {
            addEditExpenseFormView
        }
        .onAppear {
            if selectedExpense == nil, let first = filteredExpenses.first {
                selectedExpense = first
            }
        }
        }
    }

    // MARK: - Native Header
    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon + Title & Subtitle Badge
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.appAccent, Color(hex: "F59E0B")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(lm.currentLanguage == .thai ? "ค่าใช้จ่ายและสินทรัพย์" : "Expenses & Asset Register")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text("EXPENSES & ASSETS")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(lm.currentLanguage == .thai ? "บันทึกค่าใช้จ่ายร้าน ค่าเช่า ค่าน้ำไฟ ทะเบียนสินทรัพย์ และค่าตัดจำหน่าย" : "Manage OpEx, CapEx, Fixed Asset Register & Amortisation")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            // Summary metrics strip (Compact & Clean)
            HStack(spacing: 10) {
                metricChip(
                    title: lm.currentLanguage == .thai ? "ค่าใช้จ่ายเดือนนี้" : "Monthly Expenses",
                    amount: monthlyTotal,
                    color: .textPrimary,
                    icon: "banknote"
                )
                metricChip(
                    title: lm.currentLanguage == .thai ? "ค่าเสื่อม/เดือน" : "Depreciation/mo",
                    amount: monthlyDepreciationTotal,
                    color: .appAmber,
                    icon: "calendar.badge.minus"
                )
                metricChip(
                    title: "OpEx",
                    amount: opExTotal,
                    color: .appTeal,
                    icon: "briefcase"
                )
                metricChip(
                    title: "CapEx",
                    amount: capExTotal,
                    color: .appAccent,
                    icon: "wrench.and.screwdriver"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }

    private func metricChip(title: String, amount: Double, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
                Text("฿\(amount.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Advanced Filters Toolbar
    private var advancedFilterToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // Search — shared height with filter chips
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                TextField(lm.currentLanguage == .thai ? "ค้นหา (เลขบิล, รายการ, หมายเหตุ)" : "Search (Inv #, Item, Notes)", text: $searchText)
                    .font(.caption)
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.appSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .frame(minWidth: 160, maxWidth: 240)

            // Category — compact menu (same height as search; no oversized system All control)
            Menu {
                Button { selectedCategoryFilter = "All" } label: {
                    labelCheck(selectedCategoryFilter == "All", "expense_category_all".t)
                }
                Button { selectedCategoryFilter = "Raw Materials" } label: {
                    labelCheck(selectedCategoryFilter == "Raw Materials", "expense_category_raw_materials".t)
                }
                Button { selectedCategoryFilter = "Equipment" } label: {
                    labelCheck(selectedCategoryFilter == "Equipment", "expense_category_equipment".t)
                }
                Button { selectedCategoryFilter = "Consumables" } label: {
                    labelCheck(selectedCategoryFilter == "Consumables", "expense_category_consumables".t)
                }
                Button { selectedCategoryFilter = "Maintenance" } label: {
                    labelCheck(selectedCategoryFilter == "Maintenance", "expense_category_maintenance".t)
                }
                Button { selectedCategoryFilter = "Other" } label: {
                    labelCheck(selectedCategoryFilter == "Other", "expense_category_other".t)
                }
            } label: {
                filterChipLabel(
                    title: selectedCategoryFilter == "All"
                        ? "expense_category_all".t
                        : localizedCategoryName(selectedCategoryFilter),
                    systemImage: "line.3.horizontal.decrease"
                )
            }
            .buttonStyle(.plain)

            // Period — short labels so Thai text is never truncated
            HStack(spacing: 0) {
                periodChip(title: "expense_period_today".t, tag: 0)
                periodChip(title: "expense_period_month".t, tag: 1)
            }
            .padding(2)
            .background(Color.appSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )

            Spacer(minLength: 8)

            Button(action: { openAddExpenseForm() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("expense_add".t)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(APGradient.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        }
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)
    }

    private func periodChip(title: String, tag: Int) -> some View {
        Button {
            periodFilter = tag
        } label: {
            Text(title)
                .font(.caption.weight(periodFilter == tag ? .semibold : .medium))
                .foregroundColor(periodFilter == tag ? .white : .textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(periodFilter == tag ? Color.appAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filterChipLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func localizedCategoryName(_ tag: String) -> String {
        switch tag {
        case "Raw Materials": return "expense_category_raw_materials".t
        case "Equipment": return "expense_category_equipment".t
        case "Consumables": return "expense_category_consumables".t
        case "Maintenance": return "expense_category_maintenance".t
        case "Other": return "expense_category_other".t
        default: return tag
        }
    }

    @ViewBuilder
    private func labelCheck(_ selected: Bool, _ title: String) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
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

                        Text(accountingTreatmentLabel(expense))
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

                        if AccountingMath.normalizedExpenseRecognition(expense.recognitionType, legacyIsCapEx: expense.isCapEx) == "fixed_asset" {
                            let netCost = max(0, expense.amount - (expense.isVATRecoverable ? expense.vatAmount : 0))
                            let monthlyDepreciation = AccountingMath.monthlyStraightLineDepreciation(
                                cost: netCost, residualValue: expense.residualValue,
                                usefulLifeMonths: expense.usefulLifeMonths
                            )
                            let accumulated = AccountingMath.accumulatedDepreciation(
                                cost: netCost, residualValue: expense.residualValue,
                                usefulLifeMonths: expense.usefulLifeMonths,
                                availableForUse: expense.availableForUseDate ?? expense.date,
                                asOf: Date()
                            )
                            let payback = AccountingMath.simplePaybackMonths(
                                investment: netCost,
                                monthlyCashBenefit: expense.expectedMonthlyCashBenefit,
                                monthlyIncrementalCost: expense.expectedMonthlyIncrementalCost
                            )
                            let calendar = Calendar.current
                            let available = expense.availableForUseDate ?? expense.date
                            let elapsedMonths = max(0, (calendar.dateComponents([.month], from: calendar.startOfDay(for: available), to: calendar.startOfDay(for: Date())).month ?? 0) + 1)
                            let remainingMonths = max(0, expense.usefulLifeMonths - elapsedMonths)
                            let deprPct = expense.usefulLifeMonths > 0 ? min(100.0, (Double(elapsedMonths) / Double(expense.usefulLifeMonths)) * 100.0) : 0.0

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(lm.currentLanguage == .thai ? "สินทรัพย์และการคืนทุน" : "ASSET & PAYBACK")
                                        .font(.system(size: 8, weight: .bold)).foregroundColor(.appAccent)
                                    Spacer()
                                    Text("\(String(format: "%.0f", deprPct))% " + (lm.currentLanguage == .thai ? "ตัดค่าเสื่อมแล้ว" : "depreciated"))
                                        .font(.system(size: 8, weight: .semibold)).foregroundColor(.textSecondary)
                                }
                                infoRow(label: lm.currentLanguage == .thai ? "ประเภทสินทรัพย์" : "Asset Class", value: expense.assetClass ?? "—")
                                infoRow(label: lm.currentLanguage == .thai ? "โครงการ" : "Project", value: expense.investmentProject ?? "—")
                                infoRow(label: lm.currentLanguage == .thai ? "อายุการใช้งาน" : "Useful Life", value: "\(expense.usefulLifeMonths) " + (lm.currentLanguage == .thai ? "เดือน (เหลืออีก \(remainingMonths) เดือน)" : "mos (\(remainingMonths) mos left)"))
                                infoRow(label: lm.currentLanguage == .thai ? "ค่าเสื่อม/เดือน" : "Depreciation/month", value: String(format: "฿%.2f", monthlyDepreciation))
                                infoRow(label: lm.currentLanguage == .thai ? "ค่าเสื่อมสะสม" : "Accumulated depr.", value: String(format: "฿%.2f", accumulated))
                                infoRow(label: lm.currentLanguage == .thai ? "มูลค่าสุทธิตามบัญชี (NBV)" : "Net Book Value (NBV)", value: String(format: "฿%.2f", max(expense.residualValue, netCost - accumulated)))
                                infoRow(label: lm.currentLanguage == .thai ? "คืนทุนโดยประมาณ" : "Estimated payback", value: payback.map { String(format: "%.1f %@", $0, lm.currentLanguage == .thai ? "เดือน" : "months") } ?? "—")
                            }
                            .padding(APSpacing.sm)
                            .background(Color.appAccent.opacity(0.07))
                            .cornerRadius(APRadius.md)
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

    private func accountingTreatmentLabel(_ expense: Expense) -> String {
        switch AccountingMath.normalizedExpenseRecognition(expense.recognitionType, legacyIsCapEx: expense.isCapEx) {
        case "fixed_asset": return "CAPITAL ASSET (CAPEX)"
        case "prepaid_expense": return "PREPAID EXPENSE"
        case "refundable_deposit": return "REFUNDABLE DEPOSIT"
        default: return "OPERATING EXPENSE (OPEX)"
        }
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
                        Text("expense_category_equipment".t).tag("Equipment")
                        Text("expense_category_consumables".t).tag("Consumables")
                        Text("expense_category_maintenance".t).tag("Maintenance")
                        Text("expense_category_other".t).tag("Other")
                    }
                    .pickerStyle(.menu)

                    Text(lm.currentLanguage == .thai
                         ? "วัตถุดิบอาหารให้บันทึกผ่าน จัดซื้อ/คลังสินค้า เพื่อคำนวณสินค้าคงเหลือและต้นทุนขาย (COGS) โดยไม่ซ้ำรายการนี้ ส่วนค่าแรงให้บันทึกผ่านพนักงาน/บันทึกเวลา"
                         : "Record food ingredients through Purchasing/Inventory for inventory and COGS. Record labor through Employees/Timecards to avoid double counting.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
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
                        Text(lm.currentLanguage == .thai ? "หน่วยนับ" : "Unit of Measure")
                        Spacer()
                        StandardUnitPickerMenu(unit: $unitInput)
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

                    Picker(lm.currentLanguage == .thai ? "การรับรู้ทางบัญชี" : "Accounting Treatment", selection: $recognitionTypeInput) {
                        Text(lm.currentLanguage == .thai ? "ค่าใช้จ่ายดำเนินงาน (OpEx)" : "Operating Expense (OpEx)").tag("operating_expense")
                        Text(lm.currentLanguage == .thai ? "สินทรัพย์ถาวร (CapEx)" : "Fixed Asset (CapEx)").tag("fixed_asset")
                        Text(lm.currentLanguage == .thai ? "ค่าใช้จ่ายจ่ายล่วงหน้า" : "Prepaid Expense").tag("prepaid_expense")
                        Text(lm.currentLanguage == .thai ? "เงินประกัน/เงินมัดจำคืนได้" : "Refundable Deposit").tag("refundable_deposit")
                    }
                    .pickerStyle(.menu)

                    Picker(lm.currentLanguage == .thai ? "ลักษณะค่าใช้จ่าย" : "Expense Nature", selection: $expenseNatureInput) {
                        Text(lm.currentLanguage == .thai ? "ค่าเช่า" : "Rent").tag("rent")
                        Text(lm.currentLanguage == .thai ? "สาธารณูปโภค" : "Utilities").tag("utilities")
                        Text(lm.currentLanguage == .thai ? "ซ่อมบำรุง" : "Repairs & Maintenance").tag("maintenance")
                        Text(lm.currentLanguage == .thai ? "การตลาด" : "Marketing").tag("marketing")
                        Text(lm.currentLanguage == .thai ? "วัสดุสิ้นเปลือง" : "Consumables").tag("consumables")
                        Text(lm.currentLanguage == .thai ? "อื่นๆ" : "Other").tag("other")
                    }.pickerStyle(.menu)

                    Toggle(lm.currentLanguage == .thai ? "VAT ขอคืนได้" : "Recoverable Input VAT", isOn: $isVATRecoverableInput)

                    if recognitionTypeInput == "operating_expense" {
                        Toggle(lm.currentLanguage == .thai ? "รายการประจำ" : "Recurring Expense", isOn: $isRecurringInput)
                        if isRecurringInput {
                            Picker(lm.currentLanguage == .thai ? "ความถี่" : "Frequency", selection: $recurrenceFrequencyInput) {
                                Text(lm.currentLanguage == .thai ? "รายเดือน" : "Monthly").tag("monthly")
                                Text(lm.currentLanguage == .thai ? "รายไตรมาส" : "Quarterly").tag("quarterly")
                                Text(lm.currentLanguage == .thai ? "รายปี" : "Yearly").tag("yearly")
                            }.pickerStyle(.segmented)
                        }
                    }

                    if recognitionTypeInput == "prepaid_expense" {
                        DatePicker(lm.currentLanguage == .thai ? "เริ่มงวดบริการ" : "Service Start", selection: $serviceStartInput, displayedComponents: .date)
                        DatePicker(lm.currentLanguage == .thai ? "สิ้นสุดงวดบริการ" : "Service End", selection: $serviceEndInput, in: serviceStartInput..., displayedComponents: .date)
                    }

                    if recognitionTypeInput == "fixed_asset" {
                        Picker(lm.currentLanguage == .thai ? "ประเภทสินทรัพย์" : "Asset Class", selection: $assetClassInput) {
                            Text(lm.currentLanguage == .thai ? "เฟอร์นิเจอร์และอุปกรณ์ตกแต่ง" : "Furniture & Fixtures").tag("Furniture & Fixtures")
                            Text(lm.currentLanguage == .thai ? "อุปกรณ์ครัว" : "Kitchen Equipment").tag("Kitchen Equipment")
                            Text(lm.currentLanguage == .thai ? "ปรับปรุงสถานที่เช่า" : "Leasehold Improvement").tag("Leasehold Improvement")
                            Text(lm.currentLanguage == .thai ? "คอมพิวเตอร์/POS" : "Computer & POS").tag("Computer & POS")
                            Text(lm.currentLanguage == .thai ? "อื่นๆ" : "Other Asset").tag("Other Asset")
                        }.pickerStyle(.menu)
                        DatePicker(lm.currentLanguage == .thai ? "วันที่พร้อมใช้งาน" : "Available for Use", selection: $availableForUseInput, displayedComponents: .date)
                        HStack {
                            Text(lm.currentLanguage == .thai ? "อายุใช้งาน (เดือน)" : "Useful Life (months)")
                            Spacer(); TextField("60", text: $usefulLifeMonthsInput).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                        HStack {
                            Text(lm.currentLanguage == .thai ? "มูลค่าคงเหลือ" : "Residual Value")
                            Spacer(); TextField("0", text: $residualValueInput).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                        }
                        TextField(lm.currentLanguage == .thai ? "โครงการลงทุน เช่น เพิ่มที่นั่ง 20 ที่" : "Investment project", text: $investmentProjectInput)
                        HStack {
                            Text(lm.currentLanguage == .thai ? "กระแสเงินสดเพิ่ม/เดือน" : "Monthly cash benefit")
                            Spacer(); TextField("0", text: $monthlyCashBenefitInput).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                        }
                        HStack {
                            Text(lm.currentLanguage == .thai ? "ต้นทุนเพิ่ม/เดือน" : "Monthly incremental cost")
                            Spacer(); TextField("0", text: $monthlyIncrementalCostInput).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                        }
                        let payback = AccountingMath.simplePaybackMonths(
                            investment: formCalculatedValues.subtotal,
                            monthlyCashBenefit: Double(monthlyCashBenefitInput) ?? 0,
                            monthlyIncrementalCost: Double(monthlyIncrementalCostInput) ?? 0
                        )
                        LabeledContent(lm.currentLanguage == .thai ? "คืนทุนโดยประมาณ" : "Estimated Payback") {
                            Text(payback.map { String(format: "%.1f %@", $0, lm.currentLanguage == .thai ? "เดือน" : "months") }
                                 ?? (lm.currentLanguage == .thai ? "ยังคำนวณไม่ได้" : "Not yet measurable"))
                                .fontWeight(.semibold)
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
        ScrollView {
        VStack(spacing: APSpacing.md) {
            Spacer().frame(height: 24)
            Image(systemName: "book.pages")
                .font(.system(size: 32))
                .foregroundColor(.textSecondary.opacity(0.6))
                .padding(APSpacing.md)
                .background(Color.appSurfaceHigh)
                .clipShape(Circle())

            Text(lm.currentLanguage == .thai ? "เริ่มต้นทะเบียนค่าใช้จ่ายและสินทรัพย์" : "Start the expense and asset register")
                .font(.headline.weight(.bold))
                .foregroundColor(.textPrimary)

            Text(lm.currentLanguage == .thai
                 ? "บันทึกค่าใช้จ่ายประจำ ค่าใช้จ่ายล่วงหน้า เงินมัดจำ หรือสินทรัพย์ เช่น โต๊ะ เก้าอี้ และอุปกรณ์ร้าน"
                 : "Record operating expenses, prepayments, deposits, or assets such as tables, chairs and store equipment.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                emptyFeature("briefcase.fill", lm.currentLanguage == .thai ? "OpEx และค่าใช้จ่ายประจำ" : "OpEx & recurring")
                emptyFeature("building.2.fill", lm.currentLanguage == .thai ? "สินทรัพย์และค่าเสื่อม" : "Assets & depreciation")
                emptyFeature("clock.arrow.circlepath", lm.currentLanguage == .thai ? "ค่าใช้จ่ายล่วงหน้า" : "Prepaid expenses")
                emptyFeature("chart.line.uptrend.xyaxis", lm.currentLanguage == .thai ? "วิเคราะห์ระยะคืนทุน" : "Payback analysis")
            }
            .frame(maxWidth: 640)

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

            Text(lm.currentLanguage == .thai
                 ? "หลังบันทึก: ดูรายละเอียดสินทรัพย์ด้านขวา และดูผลใน P&L ที่ การเงิน & กำไร → กำไร/ขาดทุน"
                 : "After saving: inspect the asset here, then open Finance & Profit → P&L for recognised expenses.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        }
    }

    private func emptyFeature(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.appAccent).frame(width: 20)
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.textPrimary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
    }

    // MARK: - Helpers & Database Mutations
    private func openAddExpenseForm() {
        editingExpense = nil
        titleInput = ""
        invoiceNoInput = ""
        categoryInput = "Consumables"
        quantityInput = "1.0"
        unitInput = "pcs"
        unitPriceInput = "0.00"
        vatOption = 0
        selectedSupplierId = nil
        paymentMethodInput = "Cash"
        statusInput = "Paid"
        isCapExInput = false
        recognitionTypeInput = "operating_expense"; expenseNatureInput = "other"
        isVATRecoverableInput = true; isRecurringInput = false; recurrenceFrequencyInput = "monthly"
        serviceStartInput = Date(); serviceEndInput = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        assetClassInput = "Furniture & Fixtures"; availableForUseInput = Date(); usefulLifeMonthsInput = "60"
        residualValueInput = "0"; investmentProjectInput = ""; monthlyCashBenefitInput = "0"; monthlyIncrementalCostInput = "0"
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
        recognitionTypeInput = AccountingMath.normalizedExpenseRecognition(expense.recognitionType, legacyIsCapEx: expense.isCapEx)
        expenseNatureInput = expense.expenseNature
        isVATRecoverableInput = expense.isVATRecoverable
        isRecurringInput = expense.isRecurring; recurrenceFrequencyInput = expense.recurrenceFrequency
        serviceStartInput = expense.serviceStartDate ?? expense.date
        serviceEndInput = expense.serviceEndDate ?? (Calendar.current.date(byAdding: .month, value: 1, to: expense.date) ?? expense.date)
        assetClassInput = expense.assetClass ?? "Furniture & Fixtures"
        availableForUseInput = expense.availableForUseDate ?? expense.date
        usefulLifeMonthsInput = String(expense.usefulLifeMonths > 0 ? expense.usefulLifeMonths : 60)
        residualValueInput = String(format: "%.2f", expense.residualValue)
        investmentProjectInput = expense.investmentProject ?? ""
        monthlyCashBenefitInput = String(format: "%.2f", expense.expectedMonthlyCashBenefit)
        monthlyIncrementalCostInput = String(format: "%.2f", expense.expectedMonthlyIncrementalCost)
        notesInput = expense.notes ?? ""
        dateInput = expense.date
        showingForm = true
    }

    private func saveFormExpense() {
        guard sessionManager.can(.expensesManage) else { return }
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
            editing.recognitionType = recognitionTypeInput
            editing.isCapEx = recognitionTypeInput == "fixed_asset"
            editing.expenseNature = expenseNatureInput; editing.isVATRecoverable = isVATRecoverableInput
            editing.isRecurring = isRecurringInput; editing.recurrenceFrequency = isRecurringInput ? recurrenceFrequencyInput : "none"
            editing.serviceStartDate = recognitionTypeInput == "prepaid_expense" ? serviceStartInput : nil
            editing.serviceEndDate = recognitionTypeInput == "prepaid_expense" ? serviceEndInput : nil
            editing.assetClass = recognitionTypeInput == "fixed_asset" ? assetClassInput : nil
            editing.availableForUseDate = recognitionTypeInput == "fixed_asset" ? availableForUseInput : nil
            editing.usefulLifeMonths = recognitionTypeInput == "fixed_asset" ? (Int(usefulLifeMonthsInput) ?? 0) : 0
            editing.residualValue = recognitionTypeInput == "fixed_asset" ? (Double(residualValueInput) ?? 0) : 0
            editing.investmentProject = investmentProjectInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : investmentProjectInput
            editing.expectedMonthlyCashBenefit = Double(monthlyCashBenefitInput) ?? 0
            editing.expectedMonthlyIncrementalCost = Double(monthlyIncrementalCostInput) ?? 0
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
                isVATRecoverable: isVATRecoverableInput,
                paymentMethod: paymentMethodInput,
                status: statusInput,
                isCapEx: recognitionTypeInput == "fixed_asset",
                recognitionType: recognitionTypeInput,
                expenseNature: expenseNatureInput,
                isRecurring: isRecurringInput,
                recurrenceFrequency: isRecurringInput ? recurrenceFrequencyInput : "none",
                serviceStartDate: recognitionTypeInput == "prepaid_expense" ? serviceStartInput : nil,
                serviceEndDate: recognitionTypeInput == "prepaid_expense" ? serviceEndInput : nil,
                assetClass: recognitionTypeInput == "fixed_asset" ? assetClassInput : nil,
                availableForUseDate: recognitionTypeInput == "fixed_asset" ? availableForUseInput : nil,
                usefulLifeMonths: recognitionTypeInput == "fixed_asset" ? (Int(usefulLifeMonthsInput) ?? 0) : 0,
                residualValue: recognitionTypeInput == "fixed_asset" ? (Double(residualValueInput) ?? 0) : 0,
                investmentProject: investmentProjectInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : investmentProjectInput,
                expectedMonthlyCashBenefit: Double(monthlyCashBenefitInput) ?? 0,
                expectedMonthlyIncrementalCost: Double(monthlyIncrementalCostInput) ?? 0,
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
        guard sessionManager.can(.expensesManage) else { return }
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
