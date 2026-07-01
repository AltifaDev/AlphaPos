import SwiftUI
import SwiftData

struct CurrencySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CurrencyExchangeRate.targetCurrency) private var rates: [CurrencyExchangeRate]
    
    @State private var selectedRate: CurrencyExchangeRate? = nil
    
    // Form States
    @State private var targetCurrency = ""
    @State private var exchangeRate = ""
    @State private var isActive = true
    @State private var isCreatingNew = false
    
    // Live Calculator State
    @State private var calculatorInput = "100"
    @State private var compactSection = "rates"
    
    private var activeRates: [CurrencyExchangeRate] {
        rates.filter { !$0.isDeleted }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 900

            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
        }
        .navigationTitle("currencies_exchange_title".t)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            if let first = activeRates.first {
                selectRate(first)
            } else {
                setupNewRateForm()
            }
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 24) {
            exchangeRatesPanel(compact: false)
                .frame(maxWidth: .infinity)

            exchangeCalculatorPanel
                .frame(width: 320)
        }
        .padding()
    }

    private var compactLayout: some View {
        VStack(spacing: 12) {
            Picker("Currency Section", selection: $compactSection) {
                Text("Rates").tag("rates")
                Text("Calculator").tag("calculator")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                if compactSection == "calculator" {
                    exchangeCalculatorPanel
                } else {
                    exchangeRatesPanel(compact: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func exchangeRatesPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("currencies_exchange_section".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()

                Button {
                    setupNewRateForm()
                } label: {
                    Label("add_rate_btn".t, systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            }

            if compact {
                VStack(spacing: 16) {
                    ratesList
                    rateEditor
                }
            } else {
                HStack(spacing: 20) {
                    ratesList
                        .frame(width: 220)

                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(width: 1)

                    ScrollView {
                        rateEditor
                    }
                }
            }
        }
        .padding()
        .apCard()
    }

    private var ratesList: some View {
        VStack(spacing: 12) {
            if activeRates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle")
                        .font(.largeTitle)
                        .foregroundColor(.textTertiary)
                    Text("no_rates_placeholder".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
                .background(Color.appSurfaceHigh.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(activeRates) { rate in
                    rateRow(rate)
                }
            }
        }
    }

    private var rateEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isCreatingNew ? "add_exchange_rate_header".t : "edit_exchange_rate_header".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("target_currency_lbl".t)
                        .font(.caption).bold().foregroundColor(.textSecondary)
                    TextField("e.g. USD, EUR", text: $targetCurrency)
                        .textFieldStyle(PlainTextFieldStyle())
                        .textInputAutocapitalization(.characters)
                        .inputShell()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("exchange_rate_lbl".t)
                        .font(.caption).bold().foregroundColor(.textSecondary)
                    TextField("e.g. 0.0272", text: $exchangeRate)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(PlainTextFieldStyle())
                        .inputShell()
                }

                Toggle(isOn: $isActive) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("active_status_lbl".t)
                            .font(.body)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("active_status_desc".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.appAccent)
                .padding()
                .background(Color.appSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))

                Button {
                    saveRate()
                } label: {
                    Text(isCreatingNew ? "save_rate_btn".t : "save_changes_btn".t)
                        .fontWeight(.bold)
                }
                .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: targetCurrency.isEmpty || Double(exchangeRate) == nil)
                .disabled(targetCurrency.isEmpty || Double(exchangeRate) == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateRow(_ rate: CurrencyExchangeRate) -> some View {
        let selected = selectedRate?.id == rate.id && !isCreatingNew

        return Button {
            selectRate(rate)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rate.targetCurrency)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(selected ? .white : .textPrimary)

                    Spacer()

                    Circle()
                        .fill(rate.isActive ? Color.appTeal : Color.textTertiary)
                        .frame(width: 8, height: 8)
                }

                Text("1 THB = \(String(format: "%.4f", rate.exchangeRate)) \(rate.targetCurrency)")
                    .font(.caption2)
                    .foregroundColor(selected ? .white.opacity(0.8) : .textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.appAccent : Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(selected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteRate(rate)
            } label: {
                Label("delete".t, systemImage: "trash")
            }
        }
    }
    
    // MARK: - Helper Actions
    private func selectRate(_ rate: CurrencyExchangeRate) {
        selectedRate = rate
        targetCurrency = rate.targetCurrency
        exchangeRate = String(rate.exchangeRate)
        isActive = rate.isActive
        isCreatingNew = false
        APHaptic.trigger()
    }
    
    private func setupNewRateForm() {
        selectedRate = nil
        targetCurrency = ""
        exchangeRate = ""
        isActive = true
        isCreatingNew = true
        APHaptic.trigger()
    }
    
    private func saveRate() {
        let rateVal = Double(exchangeRate) ?? 1.0
        
        if isCreatingNew {
            let newRate = CurrencyExchangeRate(
                targetCurrency: targetCurrency.uppercased(),
                exchangeRate: rateVal,
                isActive: isActive
            )
            modelContext.insert(newRate)
            selectedRate = newRate
            isCreatingNew = false
        } else if let rate = selectedRate {
            rate.targetCurrency = targetCurrency.uppercased()
            rate.exchangeRate = rateVal
            rate.isActive = isActive
        }
        
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
    }
    
    private func deleteRate(_ rate: CurrencyExchangeRate) {
        rate.isDeleted = true
        rate.isActive = false
        modelContext.saveWithLogging(label: #function)
        if selectedRate?.id == rate.id {
            if let next = activeRates.first(where: { !$0.isDeleted }) {
                selectRate(next)
            } else {
                setupNewRateForm()
            }
        }
    }
    
    // MARK: - Live Calculator Panel
    private var exchangeCalculatorPanel: some View {
        VStack(spacing: 16) {
            Text("exchange_calculator_title".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
            
            VStack(spacing: 20) {
                // Exchange Info Board
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.left.and.right.circle.fill")
                            .foregroundColor(.appAccent)
                            .font(.title2)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        let target = targetCurrency.isEmpty ? "USD" : targetCurrency.uppercased()
                        let rateVal = Double(exchangeRate) ?? 0.0272
                        Text("base_currency_display".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                        Text("1 THB = \(String(format: "%.6f", rateVal)) \(target)")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                
                // Input Amount in THB
                VStack(alignment: .leading, spacing: 6) {
                    Text("amount_in_thb_lbl".t)
                        .font(.caption2).bold().foregroundColor(.textSecondary)
                    HStack {
                        Text("฿").foregroundColor(.textTertiary).font(.headline)
                        TextField("100", text: $calculatorInput)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.textPrimary)
                            .font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    }
                    .padding()
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                
                // Result Panel
                let inputVal = Double(calculatorInput) ?? 0.0
                let rateVal = Double(exchangeRate) ?? 0.0272
                let resultVal = inputVal * rateVal
                let target = targetCurrency.isEmpty ? "USD" : targetCurrency.uppercased()
                
                VStack(spacing: 6) {
                    Text("converted_amount_lbl".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .bold()
                    
                    Text("\(String(format: "%.2f", resultVal)) \(target)")
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.black)
                        .foregroundColor(.appAccent)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.appAccent.opacity(0.06))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appAccent.opacity(0.12), lineWidth: 1.5))
            }
            .padding()
            
            Spacer()
        }
        .padding()
        .apCard()
    }
}

private extension View {
    func inputShell() -> some View {
        self
            .padding()
            .background(Color.appSurface)
            .foregroundColor(.textPrimary)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}
