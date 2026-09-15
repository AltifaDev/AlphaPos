import SwiftUI
import SwiftData

struct TaxSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaxRate.name) private var taxRates: [TaxRate]

    @AppStorage("store_tax_rate") private var storeTaxRate = 7.0
    @AppStorage("store_tax_type") private var storeTaxType = "inclusive"
    @AppStorage("store_service_charge_rate") private var storeServiceChargeRate = 10.0
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true
    @AppStorage("tax_profile_kind") private var profileKind = TaxProfile.restaurantVAT.rawValue
    @AppStorage("tax_price_basis") private var priceBasis = TaxPriceBasis.itemDefault.rawValue
    @AppStorage("tax_rounding_mode") private var roundingMode = TaxRoundingMode.perLine.rawValue
    @AppStorage("tax_service_charge_taxable") private var serviceChargeTaxable = true
    @AppStorage("tax_apply_dine_in") private var applyDineIn = true
    @AppStorage("tax_apply_take_out") private var applyTakeOut = true
    @AppStorage("tax_apply_delivery") private var applyDelivery = true
    @AppStorage("service_charge_apply_dine_in") private var serviceApplyDineIn = true
    @AppStorage("service_charge_apply_take_out") private var serviceApplyTakeOut = false
    @AppStorage("service_charge_apply_delivery") private var serviceApplyDelivery = false
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
            case .restaurantVAT: return "tax_profile_restaurant_vat".t
            case .quickService: return "tax_profile_quick_service".t
            case .retailSalesTax: return "tax_profile_retail".t
            case .marketplaceDelivery: return "tax_profile_delivery".t
            case .taxExempt: return "tax_profile_exempt".t
            case .custom: return "tax_profile_custom".t
            }
        }

        var subtitle: String {
            switch self {
            case .restaurantVAT: return "tax_profile_restaurant_vat_sub".t
            case .quickService: return "tax_profile_quick_service_sub".t
            case .retailSalesTax: return "tax_profile_retail_sub".t
            case .marketplaceDelivery: return "tax_profile_delivery_sub".t
            case .taxExempt: return "tax_profile_exempt_sub".t
            case .custom: return "tax_profile_custom_sub".t
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
            case .itemDefault: return "tax_basis_item_default".t
            case .forceInclusive: return "tax_basis_force_inclusive".t
            case .forceExclusive: return "tax_basis_force_exclusive".t
            }
        }
    }

    private enum TaxRoundingMode: String, CaseIterable, Identifiable {
        case perLine
        case perOrder

        var id: String { rawValue }
        var title: String {
            switch self {
            case .perLine: return "tax_round_per_line".t
            case .perOrder: return "tax_round_per_order".t
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
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rate = Double(ratePercentage) else { return false }
        return (0...100).contains(rate)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.appAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("tax_control_center_title".t)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.textPrimary)
                    Text("tax_control_center_subtitle".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineLimit(compact ? 2 : 1)
                }

                Spacer()

                if !compact {
                    compactMetric(title: "tax_metric_default".t, value: String(format: "%.2f%%", storeTaxRate), icon: "percent")
                    compactMetric(title: "tax_metric_mode".t, value: storeTaxType == "inclusive" ? "tax_inclusive_btn".t : "tax_exclusive_btn".t, icon: "number")
                    compactMetric(title: "tax_metric_service".t, value: String(format: "%.1f%%", storeServiceChargeRate), icon: "fork.knife.circle")
                }
            }

            if compact {
                HStack(spacing: 8) {
                    compactMetric(title: "tax_metric_default".t, value: String(format: "%.2f%%", storeTaxRate), icon: "percent")
                    compactMetric(title: "tax_metric_mode".t, value: storeTaxType == "inclusive" ? "tax_inclusive_btn".t : "tax_exclusive_btn".t, icon: "number")
                    compactMetric(title: "tax_metric_service".t, value: String(format: "%.1f%%", storeServiceChargeRate), icon: "fork.knife.circle")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 16)
    }

    private var profileColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("tax_section_shop_type".t, icon: "square.grid.2x2.fill")

            VStack(spacing: 8) {
                ForEach(TaxProfile.allCases) { profile in
                    profileButton(profile)
                }
            }

            Divider().background(Color.appDivider)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("tax_section_channels".t, icon: "arrow.triangle.branch")

                taxToggle("sales_dine_in".t, icon: "fork.knife", isOn: $applyDineIn)
                taxToggle("sales_take_out".t, icon: "takeoutbag.and.cup.and.straw", isOn: $applyTakeOut)
                taxToggle("sales_delivery".t, icon: "scooter", isOn: $applyDelivery)
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
            sectionTitle("tax_section_policy".t, icon: "checklist.checked")

            Toggle("store_enable_vat".t, isOn: $enableTax)
                .tint(.appAccent)
            
            Toggle("store_enable_service_charge".t, isOn: $enableServiceCharge)
                .tint(.appAccent)

            if enableServiceCharge {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("ใช้ค่าบริการกับประเภทออร์เดอร์")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            taxToggle("sales_dine_in".t, icon: "fork.knife", isOn: $serviceApplyDineIn)
                            taxToggle("sales_take_out".t, icon: "takeoutbag.and.cup.and.straw", isOn: $serviceApplyTakeOut)
                            taxToggle("sales_delivery".t, icon: "scooter", isOn: $serviceApplyDelivery)
                        }
                        VStack(spacing: 8) {
                            taxToggle("sales_dine_in".t, icon: "fork.knife", isOn: $serviceApplyDineIn)
                            taxToggle("sales_take_out".t, icon: "takeoutbag.and.cup.and.straw", isOn: $serviceApplyTakeOut)
                            taxToggle("sales_delivery".t, icon: "scooter", isOn: $serviceApplyDelivery)
                        }
                    }
                }
            }
            
            Divider().background(Color.appDivider)

            if enableTax || enableServiceCharge {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        if enableTax { defaultTaxField }
                        if enableServiceCharge { serviceChargeField }
                    }

                    VStack(spacing: 12) {
                        if enableTax { defaultTaxField }
                        if enableServiceCharge { serviceChargeField }
                    }
                }
            }

            if enableTax {
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
            }

            if enableTax || enableServiceCharge {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        if enableTax && enableServiceCharge {
                            taxToggle("คิดภาษีบน Service Charge", icon: "percent", isOn: $serviceChargeTaxable)
                        }
                        if enableTax {
                            taxToggle("อนุญาตสินค้ายกเว้นภาษี", icon: "tag.slash", isOn: $allowItemExemptions)
                        }
                    }

                    VStack(spacing: 10) {
                        if enableTax && enableServiceCharge {
                            taxToggle("คิดภาษีบน Service Charge", icon: "percent", isOn: $serviceChargeTaxable)
                        }
                        if enableTax {
                            taxToggle("อนุญาตสินค้ายกเว้นภาษี", icon: "tag.slash", isOn: $allowItemExemptions)
                        }
                    }
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
                    .onChange(of: storeTaxRate) { _, value in
                        storeTaxRate = min(100, max(0, value))
                    }
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
                    .onChange(of: storeServiceChargeRate) { _, value in
                        storeServiceChargeRate = min(100, max(0, value))
                    }
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
                        .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 12, weight: .bold))
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
                    Text("tax_exclusive_btn".t).tag("exclusive")
                    Text("tax_inclusive_btn".t).tag("inclusive")
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDefault ? .white : .appAmber)
                    .frame(width: 34, height: 34)
                    .background(isDefault ? Color.white.opacity(0.18) : Color.appAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ค่าเริ่มต้นของร้าน")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isDefault ? .white : .textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ใช้ภาษีนี้เป็นค่าเริ่มต้นตอนคิดเงิน")
                        .font(.system(size: 12))
                        .foregroundColor(isDefault ? .white.opacity(0.82) : .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12, weight: .black))
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.appTeal)
                Text("รองรับ VAT/GST แบบรวมภาษี, Sales Tax แบบบวกเพิ่ม, ร้านอาหารที่มี service charge, ร้านขายปลีก, เดลิเวอรี และร้านที่ยกเว้นภาษี")
                    .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textTertiary)
            Text("ยังไม่มีอัตราภาษี")
                .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : profile.accent)
                    .frame(width: 34, height: 34)
                    .background((selected ? Color.white : profile.accent).opacity(selected ? 0.18 : 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selected ? .white : .textPrimary)
                    Text(profile.subtitle)
                        .font(.system(size: 12))
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selected ? .white : .textPrimary)
                        if tax.isDefault {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(selected ? .white : .appAmber)
                        }
                    }
                    Text("\(String(format: "%.2f%%", tax.ratePercentage)) • \(tax.taxType.capitalized)")
                        .font(.system(size: 12))
                        .foregroundColor(selected ? .white.opacity(0.8) : .textSecondary)
                }

                Spacer()

                Button(role: .destructive) {
                    deleteTax(tax)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.textPrimary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.textSecondary)
    }

    private func compactMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.appAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                Text(value)
                    .font(.system(size: 12, weight: .black))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold))
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
        guard isValidForm, let rateVal = Double(ratePercentage) else { return }

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

        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
    }

    private func deleteTax(_ tax: TaxRate) {
        tax.isDeleted = true
        tax.isActive = false
        tax.isSynced = false
        tax.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)

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
            serviceApplyDineIn = true
            serviceApplyTakeOut = false
            serviceApplyDelivery = false
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
            serviceApplyDineIn = false
            serviceApplyTakeOut = false
            serviceApplyDelivery = false
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
            serviceApplyDineIn = false
            serviceApplyTakeOut = false
            serviceApplyDelivery = false
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
            serviceApplyDineIn = false
            serviceApplyTakeOut = false
            serviceApplyDelivery = false
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
            serviceApplyDineIn = false
            serviceApplyTakeOut = false
            serviceApplyDelivery = false
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
        let serviceCharge = enableServiceCharge && serviceChargeApplies(to: orderType)
            ? itemsSubtotal * max(0, storeServiceChargeRate) / 100.0
            : 0.0
        let taxApplies = enableTax && taxApplies(to: orderType) && storeTaxRate > 0
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

    private func serviceChargeApplies(to orderType: String) -> Bool {
        switch orderType {
        case "dine_in": return serviceApplyDineIn
        case "take_out": return serviceApplyTakeOut
        case "delivery": return serviceApplyDelivery
        default: return false
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
