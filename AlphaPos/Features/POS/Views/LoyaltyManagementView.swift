import SwiftUI
import SwiftData

struct LoyaltyManagementView: View {
    var embedded = false

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \LoyaltyTransaction.updatedAt, order: .reverse) private var transactions: [LoyaltyTransaction]
    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]

    @State private var searchText = ""
    @State private var selectedCustomer: Customer?
    @State private var showingAdjustSheet = false
    @State private var pointsPerBahtText = UserDefaults.standard.string(forKey: "loyalty_points_per_baht") ?? "0.05"
    @State private var redeemValueText = UserDefaults.standard.string(forKey: "loyalty_redeem_value_per_point") ?? "0.25"

    private var activeCustomers: [Customer] {
        customers.filter { !$0.isDeleted }
    }

    private var filteredCustomers: [Customer] {
        guard !searchText.isEmpty else { return activeCustomers }
        let query = searchText.lowercased()
        return activeCustomers.filter {
            $0.name.lowercased().contains(query) ||
            ($0.phone ?? "").contains(query) ||
            ($0.email ?? "").lowercased().contains(query)
        }
    }

    private var totalPoints: Int {
        activeCustomers.reduce(0) { $0 + $1.loyaltyPoints }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.appDivider)

                HStack(spacing: 0) {
                    customersPanel
                    Divider().background(Color.appDivider)
                    detailPanel
                }
            }
        }
        .navigationTitle(embedded ? "customer_value_title".t : "tab_loyalty".t)
        .apNavBar(background: Color.appBackground)
        .sheet(isPresented: $showingAdjustSheet) {
            if let selectedCustomer {
                LoyaltyAdjustmentSheet(customer: selectedCustomer) { type, points, note in
                    applyAdjustment(customer: selectedCustomer, type: type, points: points, note: note)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: APSpacing.md) {
            metricCard(title: "loyalty_members".t, value: "\(activeCustomers.count)", icon: "person.2.fill", color: .appAccent)
            metricCard(title: "loyalty_open_points".t, value: "\(totalPoints)", icon: "star.fill", color: Color(hex: "F59E0B"))
            metricCard(title: "loyalty_transactions".t, value: "\(transactions.filter { !$0.isDeleted }.count)", icon: "list.bullet.rectangle", color: .appTeal)

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Text("loyalty_earn_rate".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    TextField("0.05", text: $pointsPerBahtText)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Text("pt/฿")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                HStack {
                    Text("loyalty_redeem_rate".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    TextField("0.25", text: $redeemValueText)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Text("฿/pt")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .onChange(of: pointsPerBahtText) { UserDefaults.standard.set(pointsPerBahtText, forKey: "loyalty_points_per_baht") }
            .onChange(of: redeemValueText) { UserDefaults.standard.set(redeemValueText, forKey: "loyalty_redeem_value_per_point") }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.textSecondary)
                Text(value).font(.title3.weight(.bold)).foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var customersPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("loyalty_search_placeholder".t, text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(10)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
            .padding(APSpacing.md)

            if filteredCustomers.isEmpty {
                emptyState(
                    title: searchText.isEmpty ? "loyalty_no_members".t : "customer_value_no_results".t,
                    subtitle: searchText.isEmpty ? "loyalty_no_members_hint".t : "customer_value_search_hint".t,
                    icon: "person.2"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                    ForEach(filteredCustomers) { customer in
                        Button {
                            selectedCustomer = customer
                        } label: {
                            HStack(spacing: APSpacing.md) {
                                ZStack {
                                    Circle().fill(tierColor(customer.membershipTier).opacity(0.2)).frame(width: 42, height: 42)
                                    Text(String(customer.name.prefix(1)).uppercased())
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(tierColor(customer.membershipTier))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(customer.name)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.textPrimary)
                                    Text("tier_\(customer.membershipTier.lowercased())".t)
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Text("\(customer.loyaltyPoints) \("loyalty_points".t.lowercased())")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(Color(hex: "F59E0B"))
                            }
                            .padding(APSpacing.md)
                            .background(selectedCustomer?.id == customer.id ? Color.appAccent.opacity(0.12) : Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selectedCustomer?.id == customer.id ? Color.appAccent : Color.appBorderSubtle, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    }
                    .padding([.horizontal, .bottom], APSpacing.md)
                }
            }
        }
        .frame(width: 400)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let customer = selectedCustomer {
            let customerTxns = transactions.filter { !$0.isDeleted && $0.customer?.id == customer.id }
            let customerOrders = orders.filter { !$0.isDeleted && $0.customer?.id == customer.id }

            VStack(alignment: .leading, spacing: APSpacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(customer.name)
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.textPrimary)
                        Text(LocalizationManager.shared.t("loyalty_visits_spend_template", "tier_\(customer.membershipTier.lowercased())".t, customer.visitCount, customer.totalSpend))
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        showingAdjustSheet = true
                    } label: {
                        Label("loyalty_adjust_points".t, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }

                HStack(spacing: APSpacing.md) {
                    metricCard(title: "loyalty_points".t, value: "\(customer.loyaltyPoints)", icon: "star.fill", color: Color(hex: "F59E0B"))
                    metricCard(title: "loyalty_redeem_value".t, value: "฿\(String(format: "%.2f", redeemValue(customer.loyaltyPoints)))", icon: "tag.fill", color: .appTeal)
                    metricCard(title: "loyalty_history".t, value: "\(customerTxns.count)", icon: "clock.arrow.circlepath", color: .appAccent)
                }

                HStack(spacing: 0) {
                    profileItem(icon: "phone.fill", label: "customer_phone_label".t, value: customer.phone ?? "—")
                    Divider().frame(height: 34)
                    profileItem(icon: "envelope.fill", label: "email_label".t, value: customer.email ?? "—")
                    Divider().frame(height: 34)
                    profileItem(icon: "calendar", label: "member_since_label".t, value: customer.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Divider().frame(height: 34)
                    profileItem(icon: "arrow.triangle.2.circlepath", label: "updated_label".t, value: customer.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .padding(.vertical, 12)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))

                HStack(alignment: .top, spacing: APSpacing.lg) {
                    historySection(transactions: customerTxns)
                    orderSection(orders: customerOrders)
                }
            }
            .padding(APSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState(
                title: "loyalty_select_customer_prompt".t,
                subtitle: "loyalty_select_customer_hint".t,
                icon: "star.circle.fill"
            )
        }
    }

    private func emptyState(title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.appAccent.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            .frame(width: 72, height: 72)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(Color.appAccent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(Color.textTertiary)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }

    private func historySection(transactions: [LoyaltyTransaction]) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("loyalty_history_section".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
            if transactions.isEmpty {
                emptyCard("loyalty_no_transactions".t)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(transactions) { txn in
                            HStack {
                                Image(systemName: icon(for: txn.transactionType))
                                    .foregroundColor(color(for: txn.transactionType))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("txn_type_\(txn.transactionType.lowercased())".t)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.textPrimary)
                                    Text(txn.transactionDescription ?? txn.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(txn.points > 0 ? "+" : "")\(txn.points)")
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(txn.points >= 0 ? .appTeal : .appRose)
                                    Text(LocalizationManager.shared.t("loyalty_bal_template", txn.pointsBalanceAfter))
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .padding(APSpacing.md)
                            .background(Color.appSurface)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func orderSection(orders: [Order]) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("loyalty_customer_orders".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
            if orders.isEmpty {
                emptyCard("loyalty_no_orders".t)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(orders.prefix(20)) { order in
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
                                Text("฿\(order.total, specifier: "%.2f")")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.appTeal)
                            }
                            .padding(APSpacing.md)
                            .background(Color.appSurface)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(Color.appSurface)
            .cornerRadius(8)
    }

    private func applyAdjustment(customer: Customer, type: String, points: Int, note: String) {
        let signedPoints = type == "redeem" || type == "expire" ? -abs(points) : points
        customer.loyaltyPoints = max(0, customer.loyaltyPoints + signedPoints)
        customer.membershipTier = tier(for: customer.loyaltyPoints)
        customer.isSynced = false
        customer.updatedAt = Date()

        let txn = LoyaltyTransaction(
            customer: customer,
            transactionType: type,
            points: signedPoints,
            pointsBalanceAfter: customer.loyaltyPoints,
            transactionDescription: note.isEmpty ? "loyalty_manual_txn_type_\(type)".t : note
        )
        modelContext.insert(txn)
        modelContext.saveWithLogging(label: #function)
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }

    private func redeemValue(_ points: Int) -> Double {
        Double(points) * (Double(redeemValueText) ?? 0.25)
    }

    private func tier(for points: Int) -> String {
        if points >= 5000 { return "platinum" }
        if points >= 2000 { return "gold" }
        if points >= 500 { return "silver" }
        return "standard"
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier.lowercased() {
        case "platinum": return Color(hex: "A78BFA")
        case "gold": return Color(hex: "F59E0B")
        case "silver": return Color(hex: "9CA3AF")
        default: return .appAccent
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "redeem": return "minus.circle.fill"
        case "adjust": return "slider.horizontal.3"
        case "expire": return "clock.badge.xmark.fill"
        default: return "plus.circle.fill"
        }
    }

    private func color(for type: String) -> Color {
        switch type {
        case "redeem", "expire": return .appRose
        case "adjust": return .appAccent
        default: return .appTeal
        }
    }
}

private struct LoyaltyAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    let onSave: (String, Int, String) -> Void

    @State private var type = "adjust"
    @State private var pointsText = ""
    @State private var note = ""

    private let types = ["earn", "redeem", "adjust", "expire"]
    private var points: Int { Int(pointsText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name) {
                    Picker("loyalty_transaction_type".t, selection: $type) {
                        ForEach(types, id: \.self) { Text("txn_type_\($0)".t).tag($0) }
                    }
                    TextField("loyalty_points".t, text: $pointsText)
                        .keyboardType(.numberPad)
                    TextField("loyalty_reason_note".t, text: $note)
                }
            }
            .navigationTitle("loyalty_adjust_loyalty_title".t)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel".t) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".t) {
                        onSave(type, points, note)
                        dismiss()
                    }
                    .disabled(points <= 0)
                }
            }
        }
    }
}
