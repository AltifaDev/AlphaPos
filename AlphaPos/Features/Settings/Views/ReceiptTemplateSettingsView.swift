import SwiftUI
import SwiftData
import CoreImage
import CoreImage.CIFilterBuiltins

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ReceiptTemplateSettingsView  (v3 — Full Redesign)
// Layout: 3-column iPad | Type sidebar | Settings panel | Live preview
// ─────────────────────────────────────────────────────────────────────────────

struct ReceiptTemplateSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReceiptTemplate.name) private var templates: [ReceiptTemplate]

    // ── Selection ────────────────────────────────────────────────────────────
    @State private var selectedType:     PrintDocType = .receipt
    @State private var selectedTemplate: ReceiptTemplate? = nil
    @State private var isCreatingNew     = false
    @State private var compactSection    = "editor"   // "editor" | "preview"

    // ── Form State (mirrors ReceiptTemplate fields) ───────────────────────────
    @State private var name              = ""
    @State private var headerText        = ""
    @State private var footerText        = ""
    @State private var isDefault         = false
    @State private var paperWidth        = "80mm"
    // Receipt-specific
    @State private var showLogo          = true
    @State private var showTaxId         = true
    @State private var showCustomerInfo  = true
    @State private var showQRCode        = true
    @State private var showServiceCharge = true
    // Shared (kitchen/bar/receipt)
    @State private var showTableInfo     = true
    @State private var showOrderType     = true
    @State private var showItemModifiers = true
    // Sticker-specific
    @State private var stickerSize       = "40x30"

    // ── Store info (AppStorage) ───────────────────────────────────────────────
    @AppStorage("store_name")        private var storeName       = "AlphaPos Restaurant"
    @AppStorage("store_phone")       private var storePhone      = "02-123-4567"
    @AppStorage("store_address")     private var storeAddress    = "123 Sukhumvit Rd, Bangkok"
    @AppStorage("store_tax_id")      private var storeTaxId      = "1234567890123"
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_logo_path")   private var storeLogoPath   = ""
    @AppStorage("promptpay_number")  private var promptPayNumber = ""
    @AppStorage("enable_tax")        private var enableTax       = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true

    // ── Computed ──────────────────────────────────────────────────────────────
    private var templatesForType: [ReceiptTemplate] {
        templates.filter { !$0.isDeleted && $0.templateType == selectedType.rawValue }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Print Document Types
    // ─────────────────────────────────────────────────────────────────────────

    enum PrintDocType: String, CaseIterable {
        case receipt = "receipt"
        case kitchen = "kitchen"
        case bar     = "bar"
        case sticker = "sticker"

        var label: String {
            switch self {
            case .receipt: return "Receipt"
            case .kitchen: return "Kitchen"
            case .bar:     return "Bar"
            case .sticker: return "Sticker"
            }
        }
        var icon: String {
            switch self {
            case .receipt: return "doc.text.fill"
            case .kitchen: return "flame.fill"
            case .bar:     return "cup.and.saucer.fill"
            case .sticker: return "tag.fill"
            }
        }
        var accentHex: String {
            switch self {
            case .receipt: return "6366F1"
            case .kitchen: return "EF4444"
            case .bar:     return "3B82F6"
            case .sticker: return "10B981"
            }
        }
        var description: String {
            switch self {
            case .receipt: return "Tax invoice · Customer receipt"
            case .kitchen: return "Kitchen order ticket (ESC/POS)"
            case .bar:     return "Beverage station ticket (ESC/POS)"
            case .sticker: return "Cup label · TSPL 40×30 mm"
            }
        }
        var previewType: ReceiptLivePreview.PreviewType {
            switch self {
            case .receipt: return .receipt
            case .kitchen: return .kitchen
            case .bar:     return .bar
            case .sticker: return .sticker
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Body
    // ─────────────────────────────────────────────────────────────────────────

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
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("receipt_templates_title".t)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveTemplate()
                } label: {
                    Text(isCreatingNew ? "Create" : "Save")
                        .fontWeight(.bold)
                }
                .disabled(name.isEmpty)
            }
        }
        .onAppear {
            autoSelectTemplate()
        }
        .onChange(of: selectedType) { _, _ in
            autoSelectTemplate()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Regular Layout (iPad — 3 columns)
    // ─────────────────────────────────────────────────────────────────────────

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 0) {

            // ── Col 1: Type Selector (fixed 130pt) ───────────────────────────
            typeSelectorColumn
                .frame(width: 130)

            Divider().background(Color.appDivider)

            // ── Col 2: Template List + Settings (flexible) ───────────────────
            VStack(alignment: .leading, spacing: 0) {
                templateListHeader
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                Divider().background(Color.appDivider)
                HStack(alignment: .top, spacing: 0) {
                    templateListPanel
                        .frame(width: 180)
                    Divider().background(Color.appDivider)
                    settingsPanel
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)

            Divider().background(Color.appDivider)

            // ── Col 3: Live Preview (fixed 380pt) ────────────────────────────
            livePreviewColumn
                .frame(width: 380)
        }
        .background(Color.appBackground)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compact Layout (segmented picker)
    // ─────────────────────────────────────────────────────────────────────────

    private var compactLayout: some View {
        VStack(spacing: 0) {
            // Type + section picker row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PrintDocType.allCases, id: \.self) { type in
                        typeChip(type, compact: true)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)
            .background(Color.appSurface)

            Picker("Section", selection: $compactSection) {
                Text("Settings").tag("editor")
                Text("Preview").tag("preview")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider().background(Color.appDivider)

            if compactSection == "editor" {
                VStack(spacing: 0) {
                    templateListHeader
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().background(Color.appDivider)
                    settingsPanel.frame(maxWidth: .infinity)
                }
            } else {
                livePreviewColumn
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Col 1: Type Selector
    // ─────────────────────────────────────────────────────────────────────────

    private var typeSelectorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PRINT TYPE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.textTertiary)
                .tracking(1.2)
                .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(PrintDocType.allCases, id: \.self) { type in
                        typeChip(type, compact: false)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 16)
            }

            Spacer()
        }
        .background(Color.appSurface)
    }

    @ViewBuilder
    private func typeChip(_ type: PrintDocType, compact: Bool) -> some View {
        let isSelected = selectedType == type
        let accent = Color(hex: type.accentHex)

        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedType = type }
            APHaptic.trigger()
        } label: {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: type.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(type.label)
                        .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                }
                .foregroundColor(isSelected ? .white : .textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? accent : Color.appSurfaceHigh)
                .cornerRadius(20)
            } else {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? accent : Color.appSurfaceHigh)
                            .frame(width: 44, height: 44)
                        Image(systemName: type.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isSelected ? .white : accent.opacity(0.8))
                    }
                    Text(type.label)
                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? accent.opacity(0.08) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
            }
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Col 2a: Template List
    // ─────────────────────────────────────────────────────────────────────────

    private var templateListHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedType.label + " Templates")
                    .font(.headline).foregroundColor(.textPrimary)
                Text(selectedType.description)
                    .font(.caption2).foregroundColor(.textSecondary)
            }
            Spacer()
            Button { setupNewTemplateForm() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.appAccent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var templateListPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if templatesForType.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle).foregroundColor(.textTertiary)
                        Text("No \(selectedType.label) templates")
                            .font(.caption).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                        Button { setupNewTemplateForm() } label: {
                            Label("Create First", systemImage: "plus")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 32).frame(maxWidth: .infinity)
                } else {
                    ForEach(templatesForType) { tmpl in
                        templateRow(tmpl)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func templateRow(_ tmpl: ReceiptTemplate) -> some View {
        let isSelected = selectedTemplate?.id == tmpl.id
        Button { selectTemplate(tmpl) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tmpl.name)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if tmpl.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.appAccent)
                                .cornerRadius(4)
                        }
                        Text(tmpl.paperWidth)
                            .font(.system(size: 9)).foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.appAccent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.appAccent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { deleteTemplate(tmpl) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Col 2b: Settings Panel (type-aware)
    // ─────────────────────────────────────────────────────────────────────────

    private var settingsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // ── Identity ────────────────────────────────────────────────
                settingsSectionHeader("IDENTITY")
                cardGroup {
                    fieldLabel("Template Name")
                    TextField("e.g. Standard Receipt", text: $name).apTemplateTextField()
                    apDivider
                    fieldLabel("Paper Width")
                    Picker("Paper Width", selection: $paperWidth) {
                        if selectedType != .sticker {
                            Text("80 mm Thermal").tag("80mm")
                            Text("58 mm Thermal").tag("58mm")
                        } else {
                            Text("40 × 30 mm").tag("40x30")
                            Text("50 × 25 mm").tag("50x25")
                            Text("62 × 29 mm").tag("62x29")
                        }
                    }
                    .pickerStyle(.segmented)
                    apDivider
                    Toggle(isOn: $isDefault) {
                        toggleLabel("Set as Default",
                                    sub: "Use this template when printing \(selectedType.label)")
                    }.tint(.appAccent)
                }

                // ── Type-specific settings ───────────────────────────────────
                switch selectedType {
                case .receipt:  receiptSpecificSettings
                case .kitchen:  kitchenBarSettings(stationType: "Kitchen")
                case .bar:      kitchenBarSettings(stationType: "Bar")
                case .sticker:  stickerSettings
                }

                // ── Save button ──────────────────────────────────────────────
                Button { saveTemplate() } label: {
                    Text(isCreatingNew ? "Create Template" : "Save Changes")
                        .fontWeight(.bold)
                }
                .apGradientButton(
                    gradient: APGradient.accent,
                    shadow: APShadow.glow,
                    disabled: name.isEmpty
                )
                .disabled(name.isEmpty)
                .padding(.bottom, 24)
            }
            .padding(16)
        }
    }

    // ── Receipt-specific settings ────────────────────────────────────────────
    private var receiptSpecificSettings: some View {
        Group {
            settingsSectionHeader("HEADER & FOOTER")
            cardGroup {
                fieldLabel("Header Text")
                TextField("e.g. Welcome to AlphaPos!", text: $headerText).apTemplateTextField()
                apDivider
                fieldLabel("Footer Text")
                TextField("e.g. Follow us: @alphapos.cafe", text: $footerText).apTemplateTextField()
            }

            settingsSectionHeader("BRANDING & MEDIA")
            cardGroup {
                Toggle(isOn: $showLogo) {
                    toggleLabel("Store Logo",
                                sub: storeLogoPath.isEmpty
                                    ? "⚠ No logo — set in Store Management"
                                    : "✓ Logo configured")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showQRCode) {
                    toggleLabel("PromptPay QR",
                                sub: promptPayNumber.isEmpty
                                    ? "Set PromptPay number in Store Management"
                                    : "PromptPay: \(maskedPromptPay)")
                }.tint(.appAccent)
            }

            settingsSectionHeader("CONTENT VISIBILITY")
            cardGroup {
                Toggle(isOn: $showTaxId) {
                    toggleLabel("Tax ID & Branch Code", sub: "TAX ID · BR: 00000")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showCustomerInfo) {
                    toggleLabel("Customer Info", sub: "Customer name · Tax exemption no.")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showTableInfo) {
                    toggleLabel("Table & Queue", sub: "Table number · Queue number")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showOrderType) {
                    toggleLabel("Order Type Badge", sub: "Dine-in / Take-out / Delivery")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showItemModifiers) {
                    toggleLabel("Item Modifiers", sub: "+ Extra Cheese · Sweet 50%")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showServiceCharge) {
                    toggleLabel("Service Charge Line", sub: "10% service charge row")
                }.tint(.appAccent)
            }
        }
    }

    // ── Kitchen / Bar settings ────────────────────────────────────────────────
    @ViewBuilder
    private func kitchenBarSettings(stationType: String) -> some View {
        settingsSectionHeader("\(stationType.uppercased()) TICKET OPTIONS")
        cardGroup {
            Toggle(isOn: $showTableInfo) {
                toggleLabel("Show Table & Queue", sub: "Table number · Queue number")
            }.tint(.appAccent)
            apDivider
            Toggle(isOn: $showOrderType) {
                toggleLabel("Show Order Type", sub: "Dine-in / Take-out / Delivery")
            }.tint(.appAccent)
            apDivider
            Toggle(isOn: $showItemModifiers) {
                toggleLabel("Show Modifiers & Notes", sub: "Extra options · Special instructions")
            }.tint(.appAccent)
        }

        settingsSectionHeader("HEADER & FOOTER")
        cardGroup {
            fieldLabel("Custom Header Text")
            TextField("e.g. URGENT ORDER", text: $headerText).apTemplateTextField()
            apDivider
            fieldLabel("Custom Footer Text")
            TextField("e.g. Please prepare ASAP", text: $footerText).apTemplateTextField()
        }
    }

    // ── Sticker settings ──────────────────────────────────────────────────────
    private var stickerSettings: some View {
        Group {
            settingsSectionHeader("LABEL OPTIONS")
            cardGroup {
                Toggle(isOn: $showTableInfo) {
                    toggleLabel("Show Table Number", sub: "Printed on top-left of sticker")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showItemModifiers) {
                    toggleLabel("Show Modifiers", sub: "Up to 3 modifier lines")
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showOrderType) {
                    toggleLabel("Show Queue Number", sub: "Printed bottom-right of sticker")
                }.tint(.appAccent)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Col 3: Live Preview Column
    // ─────────────────────────────────────────────────────────────────────────

    private var livePreviewColumn: some View {
        ReceiptLivePreview(
            storeName:         storeName,
            storeAddress:      storeAddress,
            storePhone:        storePhone,
            storeTaxId:        storeTaxId,
            storeBranchCode:   storeBranchCode,
            storeLogoPath:     storeLogoPath,
            promptPayNumber:   promptPayNumber,
            headerText:        headerText,
            footerText:        footerText,
            showTaxId:         showTaxId,
            showCustomerInfo:  showCustomerInfo,
            paperWidth:        paperWidth,
            showLogo:          showLogo,
            showServiceCharge: showServiceCharge,
            showTableInfo:     showTableInfo,
            showQRCode:        showQRCode,
            showItemModifiers: showItemModifiers,
            showOrderType:     showOrderType,
            fixedPreviewType:  selectedType.previewType
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private var maskedPromptPay: String {
        let n = promptPayNumber
        guard n.count >= 4 else { return n }
        return String(n.prefix(3)) + "****" + String(n.suffix(2))
    }

    @ViewBuilder
    private func cardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding()
            .background(Color.appSurface)
            .cornerRadius(APRadius.md)
            .overlay(RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func settingsSectionHeader(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.bold)
            .foregroundColor(.appAccent).tracking(1.0)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.bold).foregroundColor(.textSecondary)
    }

    @ViewBuilder
    private func toggleLabel(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).foregroundColor(.textPrimary)
            Text(sub).font(.caption2).foregroundColor(.textTertiary)
        }
    }

    private var apDivider: some View { Divider().background(Color.appDivider) }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func autoSelectTemplate() {
        if let first = templatesForType.first { selectTemplate(first) }
        else { setupNewTemplateForm() }
    }

    private func selectTemplate(_ tmpl: ReceiptTemplate) {
        selectedTemplate   = tmpl
        name               = tmpl.name
        headerText         = tmpl.headerText ?? ""
        footerText         = tmpl.footerText ?? ""
        showTaxId          = tmpl.showTaxId
        showCustomerInfo   = tmpl.showCustomerInfo
        isDefault          = tmpl.isDefault
        paperWidth         = tmpl.paperWidth
        showLogo           = tmpl.showLogo
        showServiceCharge  = tmpl.showServiceCharge
        showTableInfo      = tmpl.showTableInfo
        showQRCode         = tmpl.showQRCode
        showItemModifiers  = tmpl.showItemModifiers
        showOrderType      = tmpl.showOrderType
        stickerSize        = tmpl.stickerSize
        isCreatingNew      = false
        APHaptic.trigger()
    }

    private func setupNewTemplateForm() {
        selectedTemplate   = nil
        name               = ""
        headerText         = ""
        footerText         = ""
        showTaxId          = true
        showCustomerInfo   = true
        isDefault          = false
        paperWidth         = selectedType == .sticker ? "40x30" : "80mm"
        showLogo           = true
        showServiceCharge  = true
        showTableInfo      = true
        showQRCode         = true
        showItemModifiers  = true
        showOrderType      = true
        stickerSize        = "40x30"
        isCreatingNew      = true
        APHaptic.trigger()
    }

    private func saveTemplate() {
        if isDefault { for t in templates { t.isDefault = false } }

        if isCreatingNew {
            let t = ReceiptTemplate(
                name:              name,
                templateType:      selectedType.rawValue,
                headerText:        headerText.isEmpty ? nil : headerText,
                footerText:        footerText.isEmpty ? nil : footerText,
                showTaxId:         showTaxId,
                showCustomerInfo:  showCustomerInfo,
                isDefault:         isDefault,
                paperWidth:        paperWidth,
                showServiceCharge: showServiceCharge,
                showLogo:          showLogo,
                showTableInfo:     showTableInfo,
                showQRCode:        showQRCode,
                showItemModifiers: showItemModifiers,
                showOrderType:     showOrderType,
                stickerSize:       stickerSize
            )
            modelContext.insert(t)
            selectedTemplate = t
            isCreatingNew    = false
        } else if let t = selectedTemplate {
            t.name             = name
            t.headerText       = headerText.isEmpty ? nil : headerText
            t.footerText       = footerText.isEmpty ? nil : footerText
            t.showTaxId        = showTaxId
            t.showCustomerInfo = showCustomerInfo
            t.isDefault        = isDefault
            t.paperWidth       = paperWidth
            t.showLogo         = showLogo
            t.showServiceCharge = showServiceCharge
            t.showTableInfo    = showTableInfo
            t.showQRCode       = showQRCode
            t.showItemModifiers = showItemModifiers
            t.showOrderType    = showOrderType
            t.stickerSize      = stickerSize
            t.isSynced         = false
            t.updatedAt        = Date()
        }
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
    }

    private func deleteTemplate(_ tmpl: ReceiptTemplate) {
        tmpl.isDeleted = true
        modelContext.saveWithLogging(label: #function)
        if selectedTemplate?.id == tmpl.id { autoSelectTemplate() }
        APHaptic.trigger()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TextField Style Extension
// ─────────────────────────────────────────────────────────────────────────────

extension View {
    /// Styled text field used in template editor panels
    func apTemplateTextField() -> some View {
        self
            .textFieldStyle(PlainTextFieldStyle())
            .padding(10)
            .background(Color.appSurfaceHigh)
            .foregroundColor(Color.textPrimary)
            .cornerRadius(8)
            .font(.body)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ReceiptL
// Live preview แสดง pixel-accurate ตรงกับ ESCPOSBuilder
// โหลดโลโก้จาก Documents จริง + generate PromptPay QR จาก CIQRCodeGenerator
// ─────────────────────────────────────────────────────────────────────────────

struct ReceiptLivePreview: View {
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true

    // Store info
    let storeName:         String
    let storeAddress:      String
    let storePhone:        String
    let storeTaxId:        String
    let storeBranchCode:   String
    let storeLogoPath:     String
    let promptPayNumber:   String

    // Template settings
    let headerText:        String
    let footerText:        String
    let showTaxId:         Bool
    let showCustomerInfo:  Bool
    let paperWidth:        String
    let showLogo:          Bool
    let showServiceCharge: Bool
    let showTableInfo:     Bool
    let showQRCode:        Bool
    let showItemModifiers: Bool
    let showOrderType:     Bool
    /// Fixed preview type driven by parent (overrides selector when set)
    var fixedPreviewType:   PreviewType = .receipt

    // Computed
    private var paperPx: CGFloat { paperWidth == "58mm" ? 272 : 340 }
    private var hPad: CGFloat    { paperWidth == "58mm" ? 12 : 20 }
    private var divLen: Int      { paperWidth == "58mm" ? 32 : 42 }

    // Loaded assets
    @State private var logoImage:  UIImage? = nil
    @State private var qrImage:    UIImage? = nil

    // ── Preview Type Selector ──────────────────────────────────────────────
    enum PreviewType: String, CaseIterable {
        case receipt = "Receipt"
        case kitchen = "Kitchen"
        case bar     = "Bar"
        case sticker = "Sticker"
        var icon: String {
            switch self {
            case .receipt: return "doc.text.fill"
            case .kitchen: return "flame.fill"
            case .bar:     return "cup.and.saucer.fill"
            case .sticker: return "tag.fill"
            }
        }
    }
    // previewType driven by fixedPreviewType (no independent state needed)
    private var previewType: PreviewType { fixedPreviewType }

    var body: some View {
        VStack(spacing: 10) {
            // Toolbar
            HStack {
                Image(systemName: "eye.fill").font(.caption).foregroundColor(.appAccent)
                Text("LIVE PREVIEW")
                    .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1)
                Spacer()
                HStack(spacing: 6) {
                    if !storeLogoPath.isEmpty {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9)).foregroundColor(.appTeal)
                    }
                    if !promptPayNumber.isEmpty {
                        Image(systemName: "qrcode")
                            .font(.system(size: 9)).foregroundColor(.appTeal)
                    }
                    Text(paperWidth)
                        .font(.system(size: 10)).fontWeight(.bold).foregroundColor(.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.appSurfaceHigh).cornerRadius(6)
                }
            }


            // Paper scroll
            if previewType == .sticker {
                // ── Sticker layout (40×30mm หรือ 50×25mm) ──────────────
                stickerPreviewGrid
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        paperTeeth(flip: false)

                        VStack(alignment: .leading, spacing: 0) {
                            switch previewType {
                            case .receipt: receiptBody
                            case .kitchen: kitchenTicketBody(stationLabel: "KITCHEN", accentHex: "EF4444")
                            case .bar:     kitchenTicketBody(stationLabel: "BAR STATION", accentHex: "3B82F6")
                            case .sticker: EmptyView()
                            }
                        }
                        .padding(.horizontal, hPad)
                        .background(Color(hex: "FCFCF9"))

                        paperTeeth(flip: true)
                    }
                    .frame(width: paperPx)
                    .cornerRadius(4)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
            }

            // ─────────────────────────────────────────────────────────

            Text("Preview matches ESC/POS output • What you see is what prints")
                .font(.system(size: 9)).foregroundColor(.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 8)
        }
        .padding()
        .apCard()
        .onAppear { loadAssets() }
        .onChange(of: storeLogoPath)   { _, _ in loadAssets() }
        .onChange(of: promptPayNumber) { _, _ in loadAssets() }
        .onChange(of: showQRCode)      { _, _ in if showQRCode { generateQR() } }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Receipt Body
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - Kitchen / Bar Ticket Preview
    // ─────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func kitchenTicketBody(stationLabel: String, accentHex: String) -> some View {
        let accent = Color(hex: accentHex)

        // ── Station Header ───────────────────────────────────────────────
        VStack(spacing: 2) {
            // Double-size station label (mimics ESC/POS DOUBLE_SIZE_ON)
            Text("[ \(stationLabel) ]")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 14)

            Rectangle()
                .fill(accent.opacity(0.6))
                .frame(height: 2)
                .padding(.vertical, 4)

            // Time + Order (เน้น urgency)
            HStack {
                Text("TIME : 14:32")
                    .fontWeight(.bold)
                Spacer()
                Text("#AP-102546")
                    .fontWeight(.bold)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.black)

            if showTableInfo {
                HStack {
                    Text("TABLE: 08 (Zone A)")
                    Spacer()
                    Text("QUEUE: #32")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.black)
            }
        }
        .padding(.bottom, 6)

        monoDiv

        // ── Items (ตัวใหญ่, bold, ไม่มี price) ──────────────────────────
        let kitchenItems: [(name: String, qty: Int, mods: [String], note: String?)] = stationLabel.contains("BAR") ? [
            ("Matcha Latte (Oat)",     2, ["Sweet 50% (x2)", "Oat Milk (+฿30)"], nil),
            ("Iced Americano",         1, ["No Sugar", "Extra Shot"],             "น้ำแข็งน้อย"),
            ("Strawberry Smoothie",    1, [],                                     nil),
        ] : [
            ("Premium Beef Burger",    2, ["Extra Cheese", "Medium Rare"],        nil),
            ("Crispy French Fries",    1, ["Spicy Seasoning"],                   nil),
            ("Tom Yum Soup (large)",   1, [],                                    "ไม่ใส่เห็ด"),
        ]

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(kitchenItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    // Item name — double-height style
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("x\(item.qty)")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(accent)
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    // Modifiers
                    ForEach(item.mods, id: \.self) { mod in
                        Text("  >> \(mod)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.black.opacity(0.65))
                    }
                    // Note
                    if let note = item.note {
                        Text("  ** \(note)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(accent)
                    }
                }
                .padding(.vertical, 2)

                if item.name != kitchenItems.last?.name {
                    Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                }
            }
        }
        .padding(.vertical, 4)

        monoDiv

        // ── Footer ───────────────────────────────────────────────────────
        Text(stationLabel.contains("BAR") ? "[ BEVERAGE STATION — PLEASE PREPARE ]"
                                           : "[ KITCHEN — PLEASE PREPARE ]")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundColor(accent.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - Sticker Label Preview (TSPL 40×30mm / 50×25mm)
    // ─────────────────────────────────────────────────────────────────────

    private var stickerPreviewGrid: some View {
        // แสดง 3 sticker ตัวอย่าง (1 order × 3 items/cups)
        let stickerItems: [(item: String, mods: [String], note: String?, cupIdx: Int, total: Int)] = [
            ("Matcha Latte (Oat)",  ["Sweet 50%", "Oat Milk"],  nil,             1, 3),
            ("Matcha Latte (Oat)",  ["Sweet 50%", "Oat Milk"],  nil,             2, 3),
            ("Iced Americano",      ["No Sugar", "Extra Shot"], "น้ำแข็งน้อย", 3, 3),
        ]

        return VStack(spacing: 6) {
            // Label size picker label
            HStack {
                Image(systemName: "tag.fill").font(.caption2).foregroundColor(.appAccent)
                Text("40 × 30 mm  (TSPL / Label Printer)")
                    .font(.system(size: 9)).foregroundColor(.textSecondary)
                Spacer()
            }

            ForEach(Array(stickerItems.enumerated()), id: \.offset) { _, s in
                stickerCard(
                    itemName: s.item, mods: s.mods, note: s.note,
                    table: "Table 08", queue: "AP-102546",
                    cupIdx: s.cupIdx, totalCups: s.total,
                    timeStr: "14:32"
                )
            }
        }
    }

    private func stickerCard(
        itemName: String, mods: [String], note: String?,
        table: String, queue: String,
        cupIdx: Int, totalCups: Int,
        timeStr: String
    ) -> some View {
        VStack(spacing: 0) {
            // Row 1: Table (left) + Cup counter (right)
            HStack {
                Text(table)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                Text("\(cupIdx)/\(totalCups)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)

            // Divider bar
            Rectangle().fill(Color.black).frame(height: 1.5)

            // Row 2: Item name (ใหญ่)
            Text(itemName)
                .font(.system(size: itemName.count > 16 ? 12 : 14,
                              weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.top, 5)

            // Row 3+: Modifiers
            VStack(alignment: .leading, spacing: 1) {
                ForEach(mods.prefix(3), id: \.self) { mod in
                    Text("- \(mod)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.black.opacity(0.75))
                }
                if let note = note {
                    Text("* \(note)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.top, 2)

            // Footer bar: เวลา + Queue
            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
                .padding(.top, 5)

            HStack {
                Text(timeStr)
                    .font(.system(size: 8, design: .monospaced))
                Spacer()
                Text("Q: \(queue.prefix(12))")
                    .font(.system(size: 8, design: .monospaced))
            }
            .foregroundColor(.black.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        )
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
        .frame(width: paperPx)
    }

    // ─────────────────────────────────────────────────────────────────────
    // MARK: - Receipt Body (existing)
    // ─────────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var receiptBody: some View {
        if !headerText.isEmpty {
            Text(headerText)
                .font(.system(size: 8, design: .monospaced)).italic()
                .foregroundColor(.black.opacity(0.65)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 2)
        }

        // ── Logo ────────────────────────────────────────────────────────
        VStack(spacing: 4) {
            if showLogo, let img = logoImage {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, headerText.isEmpty ? 14 : 6)
            } else if showLogo {
                // Placeholder เมื่อยังไม่มีโลโก้
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3,2]))
                        .frame(width: 52, height: 52)
                    Image(systemName: "storefront.fill")
                        .font(.title2).foregroundColor(.gray.opacity(0.4))
                }
                .padding(.top, headerText.isEmpty ? 14 : 6)
            } else {
                // showLogo = false — icon เล็กๆ แทน
                Image(systemName: "storefront.fill")
                    .font(.title3).foregroundColor(.gray.opacity(0.3))
                    .padding(.top, 14)
            }

            Text(storeName.uppercased())
                .font(.system(.footnote, design: .monospaced)).fontWeight(.black)
                .foregroundColor(.black).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(storeAddress)
                .font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text("TEL: \(storePhone)")
                .font(.system(size: 7, design: .monospaced)).foregroundColor(.gray)
            Text("TAX INVOICE (ABBREVIATED)")
                .font(.system(size: 8, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(.black).padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity)

        monoDiv

        // ── Tax ID ──────────────────────────────────────────────────────
        if showTaxId {
            HStack {
                Text("TAX ID: \(storeTaxId)")
                Spacer()
                Text("BR: \(storeBranchCode)")
            }
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.black).padding(.vertical, 2)
        }

        // ── Customer Info ───────────────────────────────────────────────
        if showCustomerInfo {
            VStack(alignment: .leading, spacing: 1) {
                Text("CUSTOMER : Somchai V. (Member)")
                Text("TAX EXEMPT: EX-99221")
            }
            .font(.system(size: 8, design: .monospaced)).foregroundColor(.black).padding(.bottom, 2)
        }

        monoDiv

        // ── Order Info ──────────────────────────────────────────────────
        Group {
            mono8("DATE : 2026-06-22  14:32")
            mono8("ORDER: #AP-102546-CN")
            if showTableInfo {
                mono8("TABLE: Table 08 (Zone A)  QUEUE: #32")
            }
            if showOrderType {
                mono8("TYPE : DINE-IN  ·  GUESTS: 3")
            }
        }
        .padding(.vertical, 1)

        monoDiv

        // ── Items Header ────────────────────────────────────────────────
        HStack {
            Text("ITEM").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
            Text("QTY").fontWeight(.bold).frame(width: 28, alignment: .center)
            Text("PRICE").fontWeight(.bold).frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        monoDiv

        // ── Items ───────────────────────────────────────────────────────
        Group {
            itemRow("Premium Beef Burger", qty: 2, price: "440.00")
            if showItemModifiers {
                modRow("+ Extra Cheese (+฿40)")
                modRow("+ Medium Rare")
            }
            itemRow("Crispy French Fries", qty: 1, price: "120.00")
            if showItemModifiers { modRow("+ Spicy Seasoning") }
            itemRow("Matcha Latte (Oat)", qty: 2, price: "220.00")
            if showItemModifiers {
                modRow("+ Sweet 50% (x2)")
                modRow("+ Oat Milk (+฿30)")
            }
        }

        monoDiv

        // ── Totals ──────────────────────────────────────────────────────
        let previewSubtotal = 780.00
        let previewSC = (showServiceCharge && enableServiceCharge) ? 78.00 : 0.00
        let previewDiscount = -39.00
        let previewTotal = previewSubtotal + previewSC + previewDiscount
        
        Group {
            totalRow("SUBTOTAL", value: "780.00")
            if showServiceCharge && enableServiceCharge { totalRow("SERVICE CHARGE (10%)", value: "78.00") }
            if enableTax { totalRow("7% VAT (INCLUSIVE)", value: "59.36") }
            totalRow("DISCOUNT (PROMO)", value: "-39.00")
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1).padding(.vertical, 3)

        HStack {
            Text("GRAND TOTAL").fontWeight(.black)
            Spacer()
            Text(String(format: "฿%.2f", previewTotal)).fontWeight(.black)
        }
        .font(.system(.caption, design: .monospaced)).foregroundColor(.black)

        monoDiv

        // ── Payment + QR ────────────────────────────────────────────────
        VStack(spacing: 4) {
            Text(promptPayNumber.isEmpty ? "PAID VIA CASH / TRANSFER" : "SCAN TO PAY — PROMPTPAY")
                .font(.system(size: 8, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(.black).frame(maxWidth: .infinity, alignment: .center)

            if showQRCode {
                if let qr = qrImage {
                    // QR จริงจาก CIQRCodeGenerator
                    Image(uiImage: qr)
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: 88, height: 88)
                        .padding(4)
                        .background(Color.white)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.black.opacity(0.15), lineWidth: 1))
                        .padding(.vertical, 4)
                    if !promptPayNumber.isEmpty {
                        Text("PromptPay: \(maskedNumber(promptPayNumber))")
                            .font(.system(size: 7, design: .monospaced)).foregroundColor(.gray)
                    }
                } else {
                    // Placeholder ขณะ generating หรือไม่มี promptpay number
                    ZStack {
                        Rectangle().fill(Color.white).frame(width: 88, height: 88)
                            .border(Color.black.opacity(0.2), width: 1)
                        if promptPayNumber.isEmpty {
                            VStack(spacing: 3) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 28)).foregroundColor(.black.opacity(0.15))
                                Text("Set PromptPay\nnumber in\nStore Settings")
                                    .font(.system(size: 6)).foregroundColor(.black.opacity(0.3))
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("THANK YOU FOR YOUR PATRONAGE")
                .font(.system(size: 8, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(.black).padding(.top, 2)

            // Barcode (order number) — แสดงเสมอ ถ้า showQRCode เปิด
            if showQRCode {
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        ForEach(Array(barcodeWidths.enumerated()), id: \.offset) { _, w in
                            Rectangle().fill(Color.black).frame(width: w, height: 22)
                            Rectangle().fill(Color.white).frame(width: 1, height: 22)
                        }
                    }
                    Text("AP-102546-CN")
                        .font(.system(size: 6, design: .monospaced)).foregroundColor(.black)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)

        // ── Footer Text ─────────────────────────────────────────────────
        if !footerText.isEmpty {
            monoDiv
            Text(footerText)
                .font(.system(size: 8, design: .monospaced)).italic()
                .foregroundColor(.black.opacity(0.65))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }

        Spacer().frame(height: 20)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Asset Loading
    // ─────────────────────────────────────────────────────────────────────────

    private func loadAssets() {
        loadLogo()
        generateQR()
    }

    private func loadLogo() {
        guard !storeLogoPath.isEmpty else { logoImage = nil; return }
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var img: UIImage? = nil

            // storeLogoPath อาจเป็น filename หรือ full path
            if fm.fileExists(atPath: storeLogoPath) {
                img = UIImage(contentsOfFile: storeLogoPath)
            } else if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let url = docs.appendingPathComponent(storeLogoPath)
                if let data = try? Data(contentsOf: url) {
                    img = UIImage(data: data)
                }
            }

            let loadedImage = img
            await MainActor.run { self.logoImage = loadedImage }
        }
    }

    private func generateQR() {
        guard showQRCode else { qrImage = nil; return }

        // ถ้าไม่มีเบอร์ PromptPay → ใช้ URL ตัวอย่าง
        let qrString = promptPayNumber.isEmpty
            ? "https://alphapos.app/receipt/preview"
            : buildPromptPayPayload(target: promptPayNumber, amount: 878.00)

        Task.detached(priority: .userInitiated) {
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(qrString.data(using: .utf8), forKey: "inputMessage")
            filter.setValue("Q", forKey: "inputCorrectionLevel")
            guard let ciImage = filter.outputImage else { return }

            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return }
            let result = UIImage(cgImage: cg)

            await MainActor.run { self.qrImage = result }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - PromptPay Payload Builder (mirrors POSView logic)
    // ─────────────────────────────────────────────────────────────────────────

    private func buildPromptPayPayload(target: String, amount: Double) -> String {
        let sanitized = target
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        var accountInfo = "0016A000000677010111"
        if sanitized.count == 13 {
            accountInfo += "0213\(sanitized)"
        } else {
            var phone = sanitized
            if phone.hasPrefix("0") { phone.removeFirst() }
            accountInfo += "0113" + "0066" + phone
        }

        var payload = "000201010212"
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764"
        let amt = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amt.count, amt)
        payload += "5802TH6304"

        let crc = crc16(payload)
        payload += String(format: "%04X", crc)
        return payload
    }

    private func crc16(_ str: String) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in Array(str.utf8) {
            for i in 0..<8 {
                let bit = ((byte >> (7 - i)) & 1) == 1
                let c15 = ((crc >> 15) & 1) == 1
                crc <<= 1
                if c15 != bit { crc ^= 0x1021 }
            }
        }
        return crc
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - View Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private var monoDiv: some View {
        Text(String(repeating: "-", count: divLen))
            .font(.system(size: 7, design: .monospaced)).foregroundColor(.black.opacity(0.25))
            .frame(maxWidth: .infinity).padding(.vertical, 2)
    }

    private func mono8(_ text: String) -> some View {
        Text(text).font(.system(size: 8, design: .monospaced)).foregroundColor(.black)
    }

    private func itemRow(_ name: String, qty: Int, price: String) -> some View {
        HStack {
            Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(qty)").frame(width: 28, alignment: .center)
            Text(price).frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)
    }

    private func modRow(_ text: String) -> some View {
        Text("  \(text)")
            .font(.system(size: 7, design: .monospaced)).foregroundColor(.gray)
    }

    private func totalRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label); Spacer(); Text(value)
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)
    }

    private func maskedNumber(_ n: String) -> String {
        guard n.count >= 4 else { return n }
        return String(n.prefix(3)) + "****" + String(n.suffix(2))
    }

    private let barcodeWidths: [CGFloat] = [2,1,3,1,2,1,1,3,2,1,2,1,3,1,1,2,1,3,1,2,1,1,3,1,2,1,2,1,3,1]

    // ── Paper edges ──────────────────────────────────────────────────────────

    private func paperTeeth(flip: Bool) -> some View {
        ReceiptPaperTeethShape()
            .fill(Color.appDivider.opacity(0.4))
            .frame(height: 8)
            .rotationEffect(flip ? .degrees(180) : .zero)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shapes
// ─────────────────────────────────────────────────────────────────────────────

struct ReceiptPaperTeethShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let w: CGFloat = 8, h: CGFloat = 6
        var x: CGFloat = 0
        while x < rect.width {
            p.addLine(to: CGPoint(x: x + w/2, y: rect.minY + h))
            p.addLine(to: CGPoint(x: x + w,   y: rect.maxY))
            x += w
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
