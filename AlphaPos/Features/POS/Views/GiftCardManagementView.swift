import SwiftUI
import SwiftData

struct GiftCardManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \GiftCard.updatedAt, order: .reverse) private var giftCards: [GiftCard]
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var searchText = ""
    @State private var selectedCard: GiftCard?
    @State private var showingIssueSheet = false
    @State private var showingTopUpSheet = false
    @State private var showingRedeemSheet = false
    @State private var showingVoidConfirm = false

    private var activeCards: [GiftCard] {
        giftCards.filter { !$0.isDeleted }
    }

    private var filteredCards: [GiftCard] {
        let cards = activeCards
        guard !searchText.isEmpty else { return cards }
        let query = searchText.lowercased()
        return cards.filter {
            $0.cardNumber.lowercased().contains(query) ||
            ($0.customer?.name.lowercased().contains(query) ?? false) ||
            ($0.customer?.phone?.contains(query) ?? false)
        }
    }

    private var totalOutstanding: Double {
        activeCards.filter { $0.status == "active" }.reduce(0) { $0 + $1.balance }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.appDivider)

                HStack(spacing: 0) {
                    listPanel
                    Divider().background(Color.appDivider)
                    detailPanel
                }
            }
        }
        .navigationTitle("gift_cards_title".t)
        .apNavBar(background: Color.appBackground)
        .sheet(isPresented: $showingIssueSheet) {
            GiftCardIssueSheet(customers: customers) { card in
                modelContext.insert(card)
                try? modelContext.save()
                selectedCard = card
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        }
        .sheet(isPresented: $showingTopUpSheet) {
            if let selectedCard {
                GiftCardAmountSheet(title: "top_up_gift_card_title".t, actionTitle: "add_balance_btn".t, icon: "plus.circle.fill") { amount, note in
                    selectedCard.balance += amount
                    if selectedCard.initialValue <= 0 { selectedCard.initialValue = amount }
                    selectedCard.status = "active"
                    selectedCard.isSynced = false
                    selectedCard.updatedAt = Date()
                    insertAudit(action: "gift_card_topup", amount: amount, card: selectedCard, note: note)
                    try? modelContext.save()
                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                }
            }
        }
        .sheet(isPresented: $showingRedeemSheet) {
            if let selectedCard {
                GiftCardAmountSheet(title: "redeem_gift_card_title".t, actionTitle: "redeem_btn".t, icon: "minus.circle.fill", maxAmount: selectedCard.balance) { amount, note in
                    selectedCard.balance = max(0, selectedCard.balance - amount)
                    selectedCard.status = selectedCard.balance <= 0.001 ? "exhausted" : "active"
                    selectedCard.isSynced = false
                    selectedCard.updatedAt = Date()
                    insertAudit(action: "gift_card_redeem", amount: amount, card: selectedCard, note: note)
                    try? modelContext.save()
                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                }
            }
        }
        .alert("void_gift_card_alert_title".t, isPresented: $showingVoidConfirm) {
            Button("cancel_btn".t, role: .cancel) {}
            Button("void_btn".t, role: .destructive) {
                guard let selectedCard else { return }
                selectedCard.status = "disabled"
                selectedCard.balance = 0
                selectedCard.isDeleted = true
                selectedCard.isSynced = false
                selectedCard.updatedAt = Date()
                insertAudit(action: "gift_card_void", amount: 0, card: selectedCard, note: "Card disabled from Gift Card Management")
                try? modelContext.save()
                self.selectedCard = nil
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        } message: {
            Text("void_gift_card_alert_message".t)
        }
    }

    private var header: some View {
        HStack(spacing: APSpacing.md) {
            metricCard(title: "outstanding_label".t, value: "฿\(totalOutstanding.formatted(.number.precision(.fractionLength(0))))", icon: "giftcard.fill", color: .appAccent)
            metricCard(title: "active_cards_label".t, value: "\(activeCards.filter { $0.status == "active" }.count)", icon: "checkmark.circle.fill", color: .appTeal)
            metricCard(title: "disabled_label".t, value: "\(activeCards.filter { $0.status != "active" }.count)", icon: "pause.circle.fill", color: .appRose)

            Spacer()

            Button {
                showingIssueSheet = true
            } label: {
                Label("issue_card_btn".t, systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundColor(.textTertiary)
                Text(value).font(.headline.weight(.bold)).foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.appSurfaceHigh)
        .cornerRadius(8)
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("lookup_card_placeholder".t, text: $searchText)
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

            if filteredCards.isEmpty {
                emptyState(title: "no_gift_cards".t, icon: "giftcard")
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(filteredCards) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                HStack(spacing: APSpacing.md) {
                                    Image(systemName: "giftcard.fill")
                                        .foregroundColor(card.status == "active" ? .appAccent : .textTertiary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(card.cardNumber)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.textPrimary)
                                        Text(card.customer?.name ?? "unassigned".t)
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("฿\(card.balance, specifier: "%.2f")")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.textPrimary)
                                        Text(card.status.capitalized)
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(card.status == "active" ? .appTeal : .appRose)
                                    }
                                }
                                .padding(APSpacing.md)
                                .background(selectedCard?.id == card.id ? Color.appAccent.opacity(0.12) : Color.appSurface)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedCard?.id == card.id ? Color.appAccent : Color.appBorderSubtle, lineWidth: 1))
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
        if let card = selectedCard {
            VStack(alignment: .leading, spacing: APSpacing.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.cardNumber)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text(card.customer?.name ?? "no_linked_customer".t)
                        .font(.headline)
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: APSpacing.md) {
                    metricCard(title: "balance_label".t, value: "฿\(card.balance.formatted(.number.precision(.fractionLength(2))))", icon: "wallet.pass.fill", color: .appTeal)
                    metricCard(title: "initial_value_label".t, value: "฿\(card.initialValue.formatted(.number.precision(.fractionLength(2))))", icon: "banknote.fill", color: .appAccent)
                    metricCard(title: "status_label".t, value: card.status.capitalized, icon: "flag.fill", color: card.status == "active" ? .appTeal : .appRose)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("actions_header".t)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textSecondary)
                    HStack(spacing: APSpacing.md) {
                        actionButton("top_up_btn".t, icon: "plus.circle.fill", color: .appTeal) { showingTopUpSheet = true }
                        actionButton("redeem_btn".t, icon: "minus.circle.fill", color: .appAccent) { showingRedeemSheet = true }
                            .disabled(card.balance <= 0 || card.status != "active")
                        actionButton("void_btn".t, icon: "xmark.octagon.fill", color: .appRose) { showingVoidConfirm = true }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("details_header".t)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.textSecondary)
                    detailRow("updated_label".t, card.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    detailRow("expiry_label".t, card.expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "no_expiry_label".t)
                    detailRow("customer_phone_label".t, card.customer?.phone ?? "-")
                }
                .apCard()

                Spacer()
            }
            .padding(APSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyState(title: "select_gift_card_prompt".t, icon: "giftcard.fill")
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color.opacity(0.14))
                .foregroundColor(color)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.textSecondary)
            Spacer()
            Text(value).foregroundColor(.textPrimary).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func emptyState(title: String, icon: String) -> some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insertAudit(action: String, amount: Double, card: GiftCard, note: String) {
        let log = AuditLog(
            actionType: action,
            details: "\(card.cardNumber) ฿\(String(format: "%.2f", amount)) \(note)",
            originalValue: card.initialValue,
            newValue: card.balance
        )
        modelContext.insert(log)
    }
}

private struct GiftCardIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let customers: [Customer]
    let onIssue: (GiftCard) -> Void

    @State private var cardNumber = "GC-\(Int.random(in: 100000...999999))"
    @State private var amountText = ""
    @State private var selectedCustomerId = ""
    @State private var hasExpiry = false
    @State private var expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    private var amount: Double { Double(amountText) ?? 0 }
    private var selectedCustomer: Customer? {
        customers.first { $0.id.uuidString == selectedCustomerId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("card_section".t) {
                    TextField("card_number_placeholder".t, text: $cardNumber)
                    TextField("initial_value_placeholder".t, text: $amountText)
                        .keyboardType(.decimalPad)
                    Toggle("set_expiry_date_toggle".t, isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("expires_label".t, selection: $expiresAt, displayedComponents: .date)
                    }
                }
                Section("customer_section".t) {
                    Picker("linked_customer_label".t, selection: $selectedCustomerId) {
                        Text("unassigned".t).tag("")
                        ForEach(customers.filter { !$0.isDeleted }) { customer in
                            Text(customer.name).tag(customer.id.uuidString)
                        }
                    }
                }
            }
            .navigationTitle("issue_gift_card_title".t)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel_btn".t) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("issue_btn".t) {
                        let card = GiftCard(
                            cardNumber: cardNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                            balance: amount,
                            initialValue: amount,
                            customer: selectedCustomer,
                            status: amount > 0 ? "active" : "exhausted",
                            expiresAt: hasExpiry ? expiresAt : nil
                        )
                        onIssue(card)
                        dismiss()
                    }
                    .disabled(cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0)
                }
            }
        }
    }
}

private struct GiftCardAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let icon: String
    var maxAmount: Double? = nil
    let onSave: (Double, String) -> Void

    @State private var amountText = ""
    @State private var note = ""

    private var amount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool {
        amount > 0 && maxAmount.map { amount <= $0 + 0.001 } ?? true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    TextField("amount_placeholder".t, text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("note_placeholder".t, text: $note)
                    if let maxAmount {
                        Text(LocalizationManager.shared.t("available_balance_template", maxAmount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("cancel_btn".t) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(amount, note)
                        dismiss()
                    } label: {
                        Label(actionTitle, systemImage: icon)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
