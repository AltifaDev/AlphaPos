import SwiftUI
import SwiftData

struct TaxSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]

    @AppStorage("store_tax_rate") private var storeTaxRate = 7.0
    @AppStorage("store_tax_type") private var storeTaxType = "inclusive"
    @AppStorage("store_service_charge_rate") private var storeServiceChargeRate = 10.0
    @AppStorage("tax_profile_kind") private var profileKind = TaxProfile.restaurantVAT.rawValue
    @AppStorage("tax_price_basis") private var priceBasis = TaxPriceBasis.itemDefault.rawValue
    @AppStorage("tax_rounding_mode") private var roundingMode = TaxRoundingMode.perLine.rawValue
    @AppStorage("tax_service_charge_taxable") private var serviceChargeTaxable = true
    @AppStorage("tax_apply_dine_in") private var applyDineIn = true
    @AppStorage("tax_apply_take_out") private var applyTakeOut = true
    @AppStorage("tax_apply_delivery") private var applyDelivery = true
    @AppStorage("tax_allow_item_exemptions") private var allowItemExemptions = true

    @State private var selectedTax: TaxRate?
    @State private var name = ""
    @State private var ratePercentage = ""
    @State private var taxType = "inclusive"
    @State private var isDefault = false
    @State private var isCreatingNew = false
    @State private var sampleOrderType = "dine_in"
    @State private var compactSection = "profile"

    private enum TaxProfile: String, CaseIterable, Identifiable {
        case restaurantVAT
        case quickService
        case retailSalesTax
        case marketplaceDelivery
        case taxExempt
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .restaurantVAT: return "Restaurant VAT"
            case .quickService: return "Quick Service"
            case .retailSalesTax: return "Retail Sales Tax"
            case .marketplaceDelivery: return "Delivery Marketplace"
            case .taxExempt: return "Tax Exempt"
            case .custom: return "Custom"
            }
        }

        var subtitle: String {
            switch self {
            case .restaurantVAT: return "Dine-in, service charge, VAT invoice"
            case .quickService: return "Counter sales with tax included"
            case .retailSalesTax: return "Tax added at checkout"
            case .marketplaceDelivery: return "Delivery fees, GP, channel rules"
            case .taxExempt: return "No tax collected by default"
            case .custom: return "Manual policy for mixed shops"
            }
        }

        var icon: String {
            switch self {
            case .restaurantVAT: return "fork.knife"
            case .quickService: return "takeoutbag.and.cup.and.straw.fill"
            case .retailSalesTax: return "bag.fill"
            case .marketplaceDelivery: return "scooter"
            case .taxExempt: return "checkmark.shield.fill"
            case .custom: return "slider.horizontal.3"
            }
        }

        var accent: Color {
            switch self {
            case .restaurantVAT: return .appAccent
            case .quickService: return .appTeal
            case .retailSalesTax: return .appAmber
            case .marketplaceDelivery: return .purple
            case .taxExempt: return .textSecondary
            case .custom: return .appRose
            }
        }
    }

    private enum TaxPriceBasis: String, CaseIterable, Identifiable {
        case itemDefault
        case forceInclusive
        case forceExclusive

        var id: String { rawValue }
        var title: String {
            switch self {
            case .itemDefault: return "ตามสินค้า"
            case .forceInclusive: return "รวมภาษี"
            case .forceExclusive: return "บวกภาษี"
            }
        }
    }

    private enum TaxRoundingMode: String, CaseIterable, Identifiable {
        case perLine
        case perOrder

        var id: String { rawValue }
        var title: String {
            switch self {
            case .perLine: return "ปัดต่อรายการ"
            case .perOrder: return "ปัดท้ายบิล"
            }
        }
    }

    private struct TaxPreview {
        let itemsSubtotal: Double
        let serviceCharge: Double
        let taxableBase: Double
        let tax: Double
        let grandTotal: Double
        let effectiveRate: Double
        let isInclusive: Bool
        let taxApplies: Bool
    }

    private var activeTaxes: [TaxRate] {
        taxRates.filter { $0.isActive && !$0.isDeleted }
    }

    private var currentProfile: TaxProfile {
        TaxProfile(rawValue: profileKind) ?? .restaurantVAT
    }

    private var selectedBasis: TaxPriceBasis {
        TaxPriceBasis(rawValue: priceBasis) ?? .itemDefault
    }

    private var selectedRounding: TaxRoundingMode {
        TaxRoundingMode(rawValue: roundingMode) ?? .perLine
    }

    private var isValidForm: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(ratePercentage) != nil
    }

    private var preview: TaxPreview {
        calculatePreview(orderType: sampleOrderType)
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 1120

            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar(compact: isCompact)

                    if isCompact {
                        compactLayout
                    } else {
                        regularLayout
                    }
                }
            }
        }
        .navigationTitle("ตั้งค่าภาษีร้านค้า")
        .apNavBar(background: Color.appBackground)
        .onAppear {
            ensureInitialSelection()
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            profileColumn
                .frame(width: 300)

            policyColumn
                .frame(maxWidth: .infinity)

            previewColumn
                .frame(width: 360)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var compactLayout: some View {
        VStack(spacing: 12) {
            Picker("Tax Section", selection: $compactSection) {
                Text("Profile").tag("profile")
                Text("Policy").tag("policy")
                Text("Rates").tag("rates")
                Text("Preview").tag("preview")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            ScrollView {
                compactContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch compactSection {
        case "policy":
            policySection
        case "rates":
            taxRatesSection(compact: true)
        case "preview":
            previewColumn
        default:
            profileColumn
        }
    }

    private func headerBar(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 0) {
            HStack(spacing: 14) {
                Image(systemName: "building.columns.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tax Control Center")
                        .font(.title3.weight(.black))
                        .foregroundColor(.textPrimary)
                    Text("โครงสร้างภาษี, service charge, ช่องทางขาย และตัวอย่างใบเสร็จ")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(compact ? 2 : 1)
                }

                Spacer()

                if !compact {
                    compactMetric(title: "Default Tax", value: String(format: "%.2f%%", storeTaxRate), icon: "percent")
                    compactMetric(title: "Mode", value: storeTaxType == "inclusive" ? "Inclusive" : "Exclusive", icon: "number")
                    compactMetric(title: "Service", value: String(format: "%.1f%%", storeServiceChargeRate), icon: "fork.knife.circle")
                }
            }

            if compact {
                HStack(spacing: 8) {
                    compactMetric(title: "Default Tax", value: String(format: "%.2f%%", storeTaxRate), icon: "percent")
                    compactMetric(title: "Mode", value: storeTaxType == "inclusive" ? "Inclusive" : "Exclusive", icon: "number")
                    compactMetric(title: "Service", value: String(format: "%.1f%%", storeServiceChargeRate), icon: "fork.knife.circle")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 16)
    }

    private var profileColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("ประเภทร้านค้า", icon: "square.grid.2x2.fill")

            VStack(spacing: 8) {
                ForEach(TaxProfile.allCases) { profile in
                    profileButton(profile)
                }
            }

            Divider().background(Color.appDivider)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("ช่องทางที่คิดภาษี", icon: "arrow.triangle.branch")

                taxToggle("ทานที่ร้าน", icon: "fork.knife", isOn: $applyDineIn)
                taxToggle("สั่งกลับบ้าน", icon: "takeoutbag.and.cup.and.straw", isOn: $applyTakeOut)
                taxToggle("เดลิเวอรี", icon: "scooter", isOn: $applyDelivery)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var policyColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                policySection
                taxRatesSection(compact: false)
            }
        }
    }

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("นโยบายภาษีหลัก", icon: "checklist.checked")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    defaultTaxField
                    serviceChargeField
                }

                VStack(spacing: 12) {
                    defaultTaxField
                    serviceChargeField
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Tax Calculation")
                Picker("Tax Calculation", selection: $storeTaxType) {
                    Text("รวมในราคา (Inclusive)").tag("inclusive")
                    Text("บวกเพิ่มตอนคิดเงิน (Exclusive)").tag("exclusive")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Price Source")
                Picker("Price Source", selection: $priceBasis) {
                    ForEach(TaxPriceBasis.allCases) { basis in
                        Text(basis.title).tag(basis.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Rounding")
                Picker("Rounding", selection: $roundingMode) {
                    ForEach(TaxRoundingMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    taxToggle("คิดภาษีบน Service Charge", icon: "percent", isOn: $serviceChargeTaxable)
                    taxToggle("อนุญาตสินค้ายกเว้นภาษี", icon: "tag.slash", isOn: $allowItemExemptions)
                }

                VStack(spacing: 10) {
                    taxToggle("คิดภาษีบน Service Charge", icon: "percent", isOn: $serviceChargeTaxable)
                    taxToggle("อนุญาตสินค้ายกเว้นภาษี", icon: "tag.slash", isOn: $allowItemExemptions)
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var defaultTaxField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Default Tax Rate")
            HStack {
                TextField("7.0", value: $storeTaxRate, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                Text("%")
                    .foregroundColor(.textSecondary)
            }
            .inputShell()
        }
    }

    private var serviceChargeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Service Charge")
            HStack {
                TextField("10.0", value: $storeServiceChargeRate, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                Text("%")
                    .foregroundColor(.textSecondary)
            }
            .inputShell()
        }
    }

    private func taxRatesSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("อัตราภาษี", icon: "percent")
                Spacer()
                Button {
                    setupNewTaxForm()
                } label: {
                    Label("เพิ่มภาษี", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            }

            if compact {
                VStack(spacing: 14) {
                    taxRatesList
                    taxEditor
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    taxRatesList
                        .frame(width: 280)

                    taxEditor
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var taxRatesList: some View {
        VStack(spacing: 8) {
            if activeTaxes.isEmpty {
                emptyTaxState
            } else {
                ForEach(activeTaxes) { tax in
                    taxRateRow(tax)
                }
            }
        }
    }

    private var taxEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCreatingNew ? "เพิ่มอัตราภาษี" : "แก้ไขอัตราภาษี")
                .font(.headline.weight(.bold))
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("ชื่อภาษี")
                TextField("VAT 7%, GST, Sales Tax", text: $name)
                    .textFieldStyle(.plain)
                    .inputShell()
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("อัตราภาษี (%)")
                TextField("7.0", text: $ratePercentage)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .inputShell()
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("รูปแบบการคำนวณ")
                Picker("Tax Type", selection: $taxType) {
                    Text("Exclusive").tag("exclusive")
                    Text("Inclusive").tag("inclusive")
                }
                .pickerStyle(.segmented)
            }

            defaultTaxSelector

            Button {
                saveTax()
            } label: {
                Label(isCreatingNew ? "บันทึกภาษี" : "บันทึกการแก้ไข", systemImage: "checkmark.circle.fill")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: !isValidForm)
            .disabled(!isValidForm)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.appSurfaceHigh.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var defaultTaxSelector: some View {
        Button {
            isDefault.toggle()
            APHaptic.trigger()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundColor(isDefault ? .white : .appAmber)
                    .frame(width: 34, height: 34)
                    .background(isDefault ? Color.white.opacity(0.18) : Color.appAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ค่าเริ่มต้นของร้าน")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isDefault ? .white : .textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ใช้ภาษีนี้เป็นค่าเริ่มต้นตอนคิดเงิน")
                        .font(.caption2)
                        .foregroundColor(isDefault ? .white.opacity(0.82) : .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isDefault ? .white : .textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(isDefault ? Color.appAccent : Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDefault ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Tax Audit Preview", icon: "doc.text.magnifyingglass")

            Picker("Order Type", selection: $sampleOrderType) {
                Text("Dine-in").tag("dine_in")
                Text("Takeout").tag("take_out")
                Text("Delivery").tag("delivery")
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                receiptRow("ยอดสินค้า", value: preview.itemsSubtotal)
                receiptRow("Service Charge", value: preview.serviceCharge)
                receiptRow("ฐานภาษี", value: preview.taxableBase)
                receiptRow("ภาษี \(String(format: "%.2f", preview.effectiveRate))%", value: preview.tax, emphasized: true)

                Divider().background(Color.appDivider)

                HStack {
                    Text("ยอดสุทธิ")
                        .font(.headline.weight(.black))
                    Spacer()
                    Text(currency(preview.grandTotal))
                        .font(.system(.title3, design: .monospaced).weight(.black))
                        .foregroundColor(.appAccent)
                }
                .foregroundColor(.textPrimary)
            }
            .padding(16)
            .background(Color.appSurfaceHigh.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 10) {
                complianceLine(
                    title: "Invoice Mode",
                    value: preview.isInclusive ? "Tax Included" : "Tax Added",
                    ok: true
                )
                complianceLine(
                    title: "Order Type Applies",
                    value: preview.taxApplies ? "Taxable" : "No Tax",
                    ok: preview.taxApplies
                )
                complianceLine(
                    title: "Rounding",
                    value: selectedRounding.title,
                    ok: true
                )
                complianceLine(
                    title: "Item Exemptions",
                    value: allowItemExemptions ? "Enabled" : "Disabled",
                    ok: allowItemExemptions
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("มาตรฐานที่รองรับ", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.appTeal)
                Text("รองรับ VAT/GST แบบรวมภาษี, Sales Tax แบบบวกเพิ่ม, ร้านอาหารที่มี service charge, ร้านขายปลีก, เดลิเวอรี และร้านที่ยกเว้นภาษี")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
            }
            .padding(12)
            .background(Color.appTeal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var emptyTaxState: some View {
        VStack(spacing: 10) {
            Image(systemName: "percent")
                .font(.title)
                .foregroundColor(.textTertiary)
            Text("ยังไม่มีอัตราภาษี")
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.appSurfaceHigh.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func profileButton(_ profile: TaxProfile) -> some View {
        let selected = currentProfile == profile

        return Button {
            applyProfile(profile)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: profile.icon)
                    .font(.headline)
                    .foregroundColor(selected ? .white : profile.accent)
                    .frame(width: 34, height: 34)
                    .background((selected ? Color.white : profile.accent).opacity(selected ? 0.18 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(selected ? .white : .textPrimary)
                    Text(profile.subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(selected ? .white.opacity(0.82) : .textSecondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(10)
            .background(selected ? profile.accent : Color.appSurfaceHigh.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func taxRateRow(_ tax: TaxRate) -> some View {
        let selected = selectedTax?.id == tax.id && !isCreatingNew

        return Button {
            selectTax(tax)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tax.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(selected ? .white : .textPrimary)
                        if tax.isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(selected ? .white : .appAmber)
                        }
                    }
                    Text("\(String(format: "%.2f%%", tax.ratePercentage)) • \(tax.taxType.capitalized)")
                        .font(.caption2)
                        .foregroundColor(selected ? .white.opacity(0.8) : .textSecondary)
                }

                Spacer()

                Button(role: .destructive) {
                    deleteTax(tax)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(selected ? .white : .appRose)
            }
            .padding(12)
            .background(selected ? Color.appAccent : Color.appSurfaceHigh.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func taxToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
        .tint(.appAccent)
        .padding(10)
        .background(Color.appSurfaceHigh.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.appAccent)
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(.textPrimary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundColor(.textSecondary)
    }

    private func compactMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.appAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                Text(value)
                    .font(.caption.weight(.black))
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func receiptRow(_ title: String, value: Double, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? .subheadline.weight(.bold) : .subheadline)
                .foregroundColor(emphasized ? .textPrimary : .textSecondary)
            Spacer()
            Text(currency(value))
                .font(.system(.subheadline, design: .monospaced).weight(emphasized ? .black : .semibold))
                .foregroundColor(emphasized ? .appAccent : .textPrimary)
        }
    }

    private func complianceLine(title: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundColor(ok ? .appTeal : .textTertiary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(.textPrimary)
        }
        .padding(10)
        .background(Color.appSurfaceHigh.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ensureInitialSelection() {
        if let defaultTax = activeTaxes.first(where: { $0.isDefault }) {
            selectTax(defaultTax)
        } else if let first = activeTaxes.first {
            selectTax(first)
        } else {
            setupNewTaxForm()
        }
    }

    private func selectTax(_ tax: TaxRate) {
        selectedTax = tax
        name = tax.name
        ratePercentage = String(format: "%.2f", tax.ratePercentage)
        taxType = tax.taxType
        isDefault = tax.isDefault
        isCreatingNew = false
        APHaptic.trigger()
    }

    private func setupNewTaxForm() {
        selectedTax = nil
        name = defaultTaxName(for: currentProfile)
        ratePercentage = String(format: "%.2f", storeTaxRate)
        taxType = storeTaxType
        isDefault = activeTaxes.isEmpty
        isCreatingNew = true
        APHaptic.trigger()
    }

    private func saveTax() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rateVal = max(0, Double(ratePercentage) ?? 0)

        if isDefault {
            for tax in taxRates {
                tax.isDefault = false
            }
            storeTaxRate = rateVal
            storeTaxType = taxType
        }

        if isCreatingNew {
            let newTax = TaxRate(
                name: trimmedName,
                ratePercentage: rateVal,
                taxType: taxType,
                isDefault: isDefault
            )
            modelContext.insert(newTax)
            selectedTax = newTax
            isCreatingNew = false
        } else if let tax = selectedTax {
            tax.name = trimmedName
            tax.ratePercentage = rateVal
            tax.taxType = taxType
            tax.isDefault = isDefault
            tax.isSynced = false
            tax.updatedAt = Date()
        }

        try? modelContext.save()
        APHaptic.trigger()
    }

    private func deleteTax(_ tax: TaxRate) {
        tax.isDeleted = true
        tax.isActive = false
        tax.isSynced = false
        tax.updatedAt = Date()
        try? modelContext.save()

        if selectedTax?.id == tax.id {
            if let next = activeTaxes.first(where: { $0.id != tax.id }) {
                selectTax(next)
            } else {
                setupNewTaxForm()
            }
        }
    }

    private func applyProfile(_ profile: TaxProfile) {
        profileKind = profile.rawValue

        switch profile {
        case .restaurantVAT:
            storeTaxRate = 7.0
            storeTaxType = "inclusive"
            storeServiceChargeRate = 10.0
            serviceChargeTaxable = true
            applyDineIn = true
            applyTakeOut = true
            applyDelivery = true
            allowItemExemptions = true
            priceBasis = TaxPriceBasis.itemDefault.rawValue
        case .quickService:
            storeTaxRate = 7.0
            storeTaxType = "inclusive"
            storeServiceChargeRate = 0.0
            serviceChargeTaxable = false
            applyDineIn = true
            applyTakeOut = true
            applyDelivery = true
            allowItemExemptions = true
            priceBasis = TaxPriceBasis.forceInclusive.rawValue
        case .retailSalesTax:
            storeTaxRate = 7.0
            storeTaxType = "exclusive"
            storeServiceChargeRate = 0.0
            serviceChargeTaxable = false
            applyDineIn = true
            applyTakeOut = true
            applyDelivery = false
            allowItemExemptions = true
            priceBasis = TaxPriceBasis.forceExclusive.rawValue
        case .marketplaceDelivery:
            storeTaxRate = 7.0
            storeTaxType = "inclusive"
            storeServiceChargeRate = 0.0
            serviceChargeTaxable = false
            applyDineIn = false
            applyTakeOut = true
            applyDelivery = true
            allowItemExemptions = true
            priceBasis = TaxPriceBasis.itemDefault.rawValue
        case .taxExempt:
            storeTaxRate = 0.0
            storeTaxType = "inclusive"
            storeServiceChargeRate = 0.0
            serviceChargeTaxable = false
            applyDineIn = false
            applyTakeOut = false
            applyDelivery = false
            allowItemExemptions = true
            priceBasis = TaxPriceBasis.forceInclusive.rawValue
        case .custom:
            break
        }

        taxType = storeTaxType
        ratePercentage = String(format: "%.2f", storeTaxRate)
        APHaptic.trigger()
    }

    private func calculatePreview(orderType: String) -> TaxPreview {
        let itemsSubtotal = 100.0
        let serviceCharge = orderType == "dine_in" ? itemsSubtotal * max(0, storeServiceChargeRate) / 100.0 : 0.0
        let taxApplies = taxApplies(to: orderType) && storeTaxRate > 0
        let isInclusive = effectiveTaxType() == "inclusive"
        let serviceTaxBase = serviceChargeTaxable ? serviceCharge : 0.0
        let base = itemsSubtotal + serviceTaxBase

        let rawTax: Double
        if taxApplies {
            rawTax = isInclusive ? base * (storeTaxRate / (100.0 + storeTaxRate)) : base * (storeTaxRate / 100.0)
        } else {
            rawTax = 0.0
        }

        let tax = rounded(rawTax)
        let grandTotal = isInclusive ? itemsSubtotal + serviceCharge : itemsSubtotal + serviceCharge + tax

        return TaxPreview(
            itemsSubtotal: itemsSubtotal,
            serviceCharge: serviceCharge,
            taxableBase: isInclusive ? max(0, base - tax) : base,
            tax: tax,
            grandTotal: rounded(grandTotal),
            effectiveRate: taxApplies ? storeTaxRate : 0,
            isInclusive: isInclusive,
            taxApplies: taxApplies
        )
    }

    private func taxApplies(to orderType: String) -> Bool {
        switch orderType {
        case "dine_in": return applyDineIn
        case "take_out": return applyTakeOut
        case "delivery": return applyDelivery
        default: return true
        }
    }

    private func effectiveTaxType() -> String {
        switch selectedBasis {
        case .forceInclusive: return "inclusive"
        case .forceExclusive: return "exclusive"
        case .itemDefault: return storeTaxType
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func currency(_ value: Double) -> String {
        String(format: "฿%.2f", value)
    }

    private func defaultTaxName(for profile: TaxProfile) -> String {
        switch profile {
        case .restaurantVAT, .quickService, .marketplaceDelivery: return "VAT 7%"
        case .retailSalesTax: return "Sales Tax"
        case .taxExempt: return "No Tax"
        case .custom: return "Custom Tax"
        }
    }
}

private extension View {
    func inputShell() -> some View {
        self
            .padding(12)
            .background(Color.appSurfaceHigh)
            .foregroundColor(.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}
