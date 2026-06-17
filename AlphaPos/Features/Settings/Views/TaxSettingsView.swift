import SwiftUI
import SwiftData

struct TaxSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]
    
    @State private var selectedTax: TaxRate? = nil
    
    // Form States
    @State private var name = ""
    @State private var ratePercentage = ""
    @State private var taxType = "exclusive" // "exclusive", "inclusive"
    @State private var isDefault = false
    @State private var isActive = true
    @State private var isCreatingNew = false
    
    private var activeTaxes: [TaxRate] {
        taxRates.filter { $0.isActive && !$0.isDeleted }
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            HStack(spacing: 24) {
                // LEFT COLUMN: Tax Rates List & Form
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("tax_rates_section".t)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        
                        Button {
                            setupNewTaxForm()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("add_tax_btn".t)
                            }
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.appAccent)
                            .cornerRadius(APRadius.md)
                        }
                    }
                    
                    HStack(spacing: 20) {
                        // Tax Rates Sidebar List
                        ScrollView {
                            VStack(spacing: 12) {
                                if activeTaxes.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "percent")
                                            .font(.largeTitle)
                                            .foregroundColor(.textTertiary)
                                        Text("no_taxes_placeholder".t)
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.vertical, 40)
                                    .frame(maxWidth: .infinity)
                                } else {
                                    ForEach(activeTaxes) { tax in
                                        Button {
                                            selectTax(tax)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(tax.name)
                                                        .font(.body)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(selectedTax?.id == tax.id && !isCreatingNew ? .white : .textPrimary)
                                                    
                                                    Spacer()
                                                    
                                                    if tax.isDefault {
                                                        Text("default_badge".t)
                                                            .font(.system(size: 8))
                                                            .fontWeight(.black)
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 3)
                                                            .background(Color.appTeal)
                                                            .cornerRadius(APRadius.sm)
                                                    }
                                                }
                                                
                                                HStack {
                                                    Text(String(format: "%.2f%%", tax.ratePercentage))
                                                        .font(.caption2)
                                                        .bold()
                                                        .foregroundColor(selectedTax?.id == tax.id && !isCreatingNew ? .white : .textSecondary)
                                                    
                                                    Spacer()
                                                    
                                                    Text(tax.taxType.capitalized)
                                                        .font(.system(size: 9))
                                                        .foregroundColor(selectedTax?.id == tax.id && !isCreatingNew ? .white.opacity(0.8) : .textTertiary)
                                                }
                                            }
                                            .padding(14)
                                            .background(selectedTax?.id == tax.id && !isCreatingNew ? Color.appAccent : Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.md)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: APRadius.md)
                                                    .stroke(selectedTax?.id == tax.id && !isCreatingNew ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deleteTax(tax)
                                            } label: {
                                                Label("delete".t, systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 220)
                        
                        // Separator line
                        Rectangle()
                            .fill(Color.appDivider)
                            .frame(width: 1)
                        
                        // Editor Panel
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(isCreatingNew ? "add_tax_rate_header".t : "edit_tax_rate_header".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                VStack(spacing: 16) {
                                    // Tax Name Field
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("tax_name_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        TextField("e.g. VAT 7%, Service Tax", text: $name)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurface)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    
                                    // Tax Rate Percentage
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("tax_rate_percentage_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        TextField("e.g. 7.0", text: $ratePercentage)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurface)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    
                                    // Tax Type Selector (Inclusive vs Exclusive)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("tax_calculation_type_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        
                                        HStack(spacing: 12) {
                                            Button {
                                                taxType = "exclusive"
                                                APHaptic.trigger()
                                            } label: {
                                                HStack {
                                                    Image(systemName: taxType == "exclusive" ? "largecircle.fill.circle" : "circle")
                                                    Text("tax_exclusive_btn".t)
                                                }
                                                .font(.subheadline)
                                                .foregroundColor(taxType == "exclusive" ? .white : .textSecondary)
                                                .padding()
                                                .frame(maxWidth: .infinity)
                                                .background(taxType == "exclusive" ? Color.appAccent : Color.appSurface)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button {
                                                taxType = "inclusive"
                                                APHaptic.trigger()
                                            } label: {
                                                HStack {
                                                    Image(systemName: taxType == "inclusive" ? "largecircle.fill.circle" : "circle")
                                                    Text("tax_inclusive_btn".t)
                                                }
                                                .font(.subheadline)
                                                .foregroundColor(taxType == "inclusive" ? .white : .textSecondary)
                                                .padding()
                                                .frame(maxWidth: .infinity)
                                                .background(taxType == "inclusive" ? Color.appAccent : Color.appSurface)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    
                                    // Toggles
                                    VStack(spacing: 12) {
                                        Toggle(isOn: $isDefault) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("set_as_default_lbl".t).font(.body).foregroundColor(.textPrimary)
                                                Text("set_as_default_desc".t).font(.caption2).foregroundColor(.textTertiary)
                                            }
                                        }
                                        .tint(Color.appAccent)
                                    }
                                    .padding()
                                    .background(Color.appSurface)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    
                                    // Save Button
                                    Button {
                                        saveTax()
                                    } label: {
                                        Text(isCreatingNew ? "save_tax_btn".t : "save_changes_btn".t)
                                            .fontWeight(.bold)
                                    }
                                    .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: name.isEmpty || Double(ratePercentage) == nil)
                                    .disabled(name.isEmpty || Double(ratePercentage) == nil)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .apCard()
                .frame(maxWidth: .infinity)
                
                // RIGHT COLUMN: Dynamic Checkout Tax Demo Panel
                checkoutTaxDemoPanel
                    .frame(width: 320)
            }
            .padding()
        }
        .navigationTitle("tax_rates_title".t)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            if let first = activeTaxes.first {
                selectTax(first)
            } else {
                setupNewTaxForm()
            }
        }
    }
    
    // MARK: - Helper Actions
    private func selectTax(_ tax: TaxRate) {
        selectedTax = tax
        name = tax.name
        ratePercentage = String(tax.ratePercentage)
        taxType = tax.taxType
        isDefault = tax.isDefault
        isCreatingNew = false
        APHaptic.trigger()
    }
    
    private func setupNewTaxForm() {
        selectedTax = nil
        name = ""
        ratePercentage = ""
        taxType = "exclusive"
        isDefault = false
        isCreatingNew = true
        APHaptic.trigger()
    }
    
    private func saveTax() {
        let rateVal = Double(ratePercentage) ?? 0.0
        
        if isDefault {
            for t in taxRates { t.isDefault = false }
        }
        
        if isCreatingNew {
            let newTax = TaxRate(
                name: name,
                ratePercentage: rateVal,
                taxType: taxType,
                isDefault: isDefault
            )
            modelContext.insert(newTax)
            selectedTax = newTax
            isCreatingNew = false
        } else if let tax = selectedTax {
            tax.name = name
            tax.ratePercentage = rateVal
            tax.taxType = taxType
            tax.isDefault = isDefault
        }
        
        try? modelContext.save()
        APHaptic.trigger()
    }
    
    private func deleteTax(_ tax: TaxRate) {
        tax.isDeleted = true
        tax.isActive = false
        try? modelContext.save()
        if selectedTax?.id == tax.id {
            if let next = activeTaxes.first(where: { !$0.isDeleted }) {
                selectTax(next)
            } else {
                setupNewTaxForm()
            }
        }
    }
    
    // MARK: - Checkout Tax Calculation Demo Panel
    private var checkoutTaxDemoPanel: some View {
        VStack(spacing: 16) {
            Text("tax_calculation_demo_title".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
            
            VStack(spacing: 20) {
                // Calculation Demo parameters
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "cart.fill")
                            .foregroundColor(.appAccent)
                            .font(.title2)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("demo_subtotal_lbl".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                        Text("฿100.00")
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
                
                // Checkout Calculations breakdown
                let rateVal = Double(ratePercentage) ?? 7.0
                let isInclusive = taxType == "inclusive"
                
                let calculatedTax: Double = {
                    if isInclusive {
                        return 100.0 * (rateVal / (100.0 + rateVal))
                    } else {
                        return 100.0 * (rateVal / 100.0)
                    }
                }()
                
                let pricingSubtotal: Double = {
                    if isInclusive {
                        return 100.0 - calculatedTax
                    } else {
                        return 100.0
                    }
                }()
                
                let grandTotal: Double = {
                    if isInclusive {
                        return 100.0
                    } else {
                        return 100.0 + calculatedTax
                    }
                }()
                
                VStack(spacing: 12) {
                    HStack {
                        Text("demo_items_subtotal".t)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "฿%.2f", pricingSubtotal))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        let taxDisplayType = isInclusive ? "INCL".t : "ADD".t
                        let taxNameDisplay = name.isEmpty ? "VAT" : name
                        Text("\(taxNameDisplay) (\(String(format: "%.1f%%", rateVal)) - \(taxDisplayType))")
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "฿%.2f", calculatedTax))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    Divider().background(Color.appDivider)
                    
                    HStack {
                        Text("demo_grand_total".t)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(String(format: "฿%.2f", grandTotal))
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.black)
                            .foregroundColor(.appAccent)
                    }
                }
                .padding()
                .background(Color.appSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                
                // Info Box explaining how it works
                VStack(alignment: .leading, spacing: 6) {
                    Label("info_box_title".t, systemImage: "info.circle.fill")
                        .font(.caption).bold().foregroundColor(.appAccent)
                    
                    Text(isInclusive ? "inclusive_tax_explanation".t : "exclusive_tax_explanation".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineSpacing(4)
                }
                .padding()
                .background(Color.appAccent.opacity(0.05))
                .cornerRadius(8)
            }
            .padding()
            
            Spacer()
        }
        .padding()
        .apCard()
    }
}
