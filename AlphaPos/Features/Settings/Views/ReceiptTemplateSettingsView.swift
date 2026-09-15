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
    @AppStorage("store_address")     private var storeAddress    = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id")      private var storeTaxId      = ""
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_logo_path")   private var storeLogoPath   = ""
    @AppStorage("promptpay_number")  private var promptPayNumber = ""
    @AppStorage("store_receipt_header") private var storeReceiptHeader = ""
    @AppStorage("store_receipt_footer") private var storeReceiptFooter = ""
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
            case .receipt: return "tpl_type_receipt".t
            case .kitchen: return "tpl_type_kitchen".t
            case .bar:     return "tpl_type_bar".t
            case .sticker: return "tpl_type_sticker".t
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
            case .receipt: return "tpl_type_receipt_desc".t
            case .kitchen: return "tpl_type_kitchen_desc".t
            case .bar:     return "tpl_type_bar_desc".t
            case .sticker: return "tpl_type_sticker_desc".t
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
                    Text(isCreatingNew ? "tpl_create".t : "save".t)
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
                Text("template_tab_edit".t).tag("editor")
                Text("template_tab_preview".t).tag("preview")
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
            Text("tpl_print_type".t)
                .font(.system(size: 12, weight: .bold))
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
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
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
                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
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
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.textPrimary)
                Text(selectedType.description)
                    .font(.system(size: 12)).foregroundColor(.textSecondary)
            }
            Spacer()
            Button { setupNewTemplateForm() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
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
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.textTertiary)
                        Text(LocalizationManager.shared.t("tpl_no_templates", selectedType.label))
                            .font(.system(size: 12)).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                        Button { setupNewTemplateForm() } label: {
                            Label("tpl_create_first".t, systemImage: "plus")
                                .font(.system(size: 12)).fontWeight(.bold)
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
                        .font(.system(size: 12))
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if tmpl.isDefault {
                            Text("tpl_default_badge".t)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.appAccent)
                                .cornerRadius(4)
                        }
                        Text(tmpl.paperWidth)
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
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
                Label("delete".t, systemImage: "trash")
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
                settingsSectionHeader("tpl_identity".t)
                cardGroup {
                    fieldLabel("tpl_name_lbl".t)
                    TextField("tpl_name_ph".t, text: $name).apTemplateTextField()
                    apDivider
                    fieldLabel("tpl_paper_width".t)
                    Picker("tpl_paper_width".t, selection: $paperWidth) {
                        if selectedType != .sticker {
                            Text("printer_paper_80".t).tag("80mm")
                            Text("printer_paper_58".t).tag("58mm")
                        } else {
                            Text("tpl_paper_40x30".t).tag("40x30")
                            Text("tpl_paper_50x25".t).tag("50x25")
                            Text("tpl_paper_62x29".t).tag("62x29")
                        }
                    }
                    .pickerStyle(.segmented)
                    apDivider
                    Toggle(isOn: $isDefault) {
                        toggleLabel("set_as_default_lbl".t,
                                    sub: LocalizationManager.shared.t("tpl_set_default_sub", selectedType.label))
                    }.tint(.appAccent)
                }

                // ── Type-specific settings ───────────────────────────────────
                switch selectedType {
                case .receipt:  receiptSpecificSettings
                case .kitchen:  kitchenBarSettings(stationType: "kds_route_kitchen".t)
                case .bar:      kitchenBarSettings(stationType: "kds_route_bar".t)
                case .sticker:  stickerSettings
                }

                // ── Save button ──────────────────────────────────────────────
                Button { saveTemplate() } label: {
                    Text(isCreatingNew ? "tpl_create_template".t : "tpl_save_changes".t)
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
            settingsSectionHeader("tpl_section_header_footer".t)
            cardGroup {
                fieldLabel("header_text_lbl".t)
                TextField("tpl_header_ph".t, text: $headerText).apTemplateTextField()
                apDivider
                fieldLabel("footer_text_lbl".t)
                TextField("tpl_footer_ph".t, text: $footerText).apTemplateTextField()
            }

            settingsSectionHeader("tpl_section_branding".t)
            cardGroup {
                Toggle(isOn: $showLogo) {
                    toggleLabel("tpl_store_logo".t, sub: "tpl_store_logo_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showQRCode) {
                    toggleLabel("tpl_prebill_qr".t, sub: "tpl_prebill_qr_sub".t)
                }.tint(.appAccent)
            }

            settingsSectionHeader("tpl_section_visibility".t)
            cardGroup {
                Toggle(isOn: $showTaxId) {
                    toggleLabel("tpl_tax_branch".t, sub: "tpl_tax_branch_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showCustomerInfo) {
                    toggleLabel("tpl_customer_info".t, sub: "tpl_customer_info_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showTableInfo) {
                    toggleLabel("tpl_table_queue".t, sub: "tpl_table_queue_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showOrderType) {
                    toggleLabel("tpl_order_type".t, sub: "tpl_order_type_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showItemModifiers) {
                    toggleLabel("tpl_modifiers".t, sub: "tpl_modifiers_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showServiceCharge) {
                    toggleLabel("tpl_service_line".t, sub: "tpl_service_line_sub".t)
                }.tint(.appAccent)
            }
        }
    }

    // ── Kitchen / Bar settings ────────────────────────────────────────────────
    @ViewBuilder
    private func kitchenBarSettings(stationType: String) -> some View {
        settingsSectionHeader(LocalizationManager.shared.t("tpl_section_ticket_options", stationType))
        cardGroup {
            Toggle(isOn: $showTableInfo) {
                toggleLabel("tpl_show_table_queue".t, sub: "tpl_table_queue_sub".t)
            }.tint(.appAccent)
            apDivider
            Toggle(isOn: $showOrderType) {
                toggleLabel("tpl_show_order_type".t, sub: "tpl_order_type_sub".t)
            }.tint(.appAccent)
            apDivider
            Toggle(isOn: $showItemModifiers) {
                toggleLabel("tpl_show_modifiers_notes".t, sub: "tpl_show_modifiers_notes_sub".t)
            }.tint(.appAccent)
        }

        settingsSectionHeader("tpl_section_header_footer".t)
        cardGroup {
            fieldLabel("tpl_custom_header".t)
            TextField("tpl_header_ph".t, text: $headerText).apTemplateTextField()
            apDivider
            fieldLabel("tpl_custom_footer".t)
            TextField("tpl_footer_ph".t, text: $footerText).apTemplateTextField()
        }
    }

    // ── Sticker settings ──────────────────────────────────────────────────────
    private var stickerSettings: some View {
        Group {
            settingsSectionHeader("tpl_section_label_options".t)
            cardGroup {
                Toggle(isOn: $showTableInfo) {
                    toggleLabel("tpl_show_table_num".t, sub: "tpl_show_table_num_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showItemModifiers) {
                    toggleLabel("tpl_show_mods_sticker".t, sub: "tpl_show_mods_sticker_sub".t)
                }.tint(.appAccent)
                apDivider
                Toggle(isOn: $showOrderType) {
                    toggleLabel("tpl_show_queue".t, sub: "tpl_show_queue_sub".t)
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
            headerText:        headerText.isEmpty ? storeReceiptHeader : headerText,
            footerText:        footerText.isEmpty ? storeReceiptFooter : footerText,
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
        Text(text).font(.system(size: 12)).fontWeight(.bold)
            .foregroundColor(.appAccent).tracking(1.0)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).fontWeight(.bold).foregroundColor(.textSecondary)
    }

    @ViewBuilder
    private func toggleLabel(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundColor(.textPrimary)
            Text(sub).font(.system(size: 12)).foregroundColor(.textTertiary)
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
        if isDefault {
            for t in templates where t.templateType == selectedType.rawValue {
                t.isDefault = false
            }
        }

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
            .font(.system(size: 12))
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
    @AppStorage("store_tax_type") private var storeTaxType = "inclusive"

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
    /// Accent for toolbar title / eye icon (Store Settings uses teal).
    var accentColor: Color = .appAccent

    // Computed
    private var paperPx: CGFloat { paperWidth == "58mm" ? 272 : 340 }
    private var hPad: CGFloat    { paperWidth == "58mm" ? 12 : 20 }
    private var divLen: Int      { paperWidth == "58mm" ? 32 : 42 }
    private var isTaxInvoice: Bool {
        storeTaxType == "inclusive" && ReceiptComplianceGate.canIssueAbbreviatedTaxInvoice(
            vatEnabled: enableTax,
            taxId: storeTaxId
        )
    }

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
                Image(systemName: "eye.fill").font(.system(size: 12)).foregroundColor(accentColor)
                Text("tpl_live_preview".t)
                    .font(.system(size: 12)).fontWeight(.bold).foregroundColor(accentColor).tracking(1)
                Spacer()
                HStack(spacing: 6) {
                    if !storeLogoPath.isEmpty {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 12)).foregroundColor(.appTeal)
                    }
                    if !promptPayNumber.isEmpty {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12)).foregroundColor(.appTeal)
                    }
                    Text(paperWidth)
                        .font(.system(size: 12)).fontWeight(.bold).foregroundColor(.textSecondary)
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

            Text("tpl_preview_hint".t)
                .font(.system(size: 12)).foregroundColor(.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 8)
        }
        .padding()
        .apCard()
        .onAppear { loadAssets() }
        .onChange(of: storeLogoPath)   { _, _ in loadAssets() }
        .onChange(of: promptPayNumber) { _, _ in loadAssets() }
        .onChange(of: showQRCode)      { _, _ in if showQRCode { generateQR() } }
        .onChange(of: fixedPreviewType) { _, _ in generateQR() }
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
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.black)

            if showTableInfo {
                HStack {
                    Text("TABLE: 08 (Zone A)")
                    Spacer()
                    Text("QUEUE: #32")
                }
                .font(.system(size: 12, design: .monospaced))
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
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(accent)
                        Text(item.name)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    // Modifiers
                    ForEach(item.mods, id: \.self) { mod in
                        Text("  >> \(mod)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.black.opacity(0.65))
                    }
                    // Note
                    if let note = item.note {
                        Text("  ** \(note)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
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
                Image(systemName: "tag.fill").font(.system(size: 12)).foregroundColor(.appAccent)
                Text("40 × 30 mm  (TSPL / Label Printer)")
                    .font(.system(size: 12)).foregroundColor(.textSecondary)
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
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                Text("\(cupIdx)/\(totalCups)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.black.opacity(0.75))
                }
                if let note = note {
                    Text("* \(note)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
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

        // ── Logo & Store Header (Centered) ──────────────────────────────
        VStack(spacing: 3) {
            if showLogo, let img = logoImage {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(width: paperWidth == "58mm" ? 80 : 110, height: paperWidth == "58mm" ? 80 : 110)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, headerText.isEmpty ? 12 : 4)
            }

            Text(storeName)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.black).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(storeAddress)
                .font(.system(size: 7.5, design: .monospaced)).foregroundColor(.black.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Text("TEL: \(storePhone)")
                .font(.system(size: 7.5, design: .monospaced)).foregroundColor(.black.opacity(0.78))
            if showTaxId && !storeTaxId.isEmpty {
                Text("TAX ID: \(storeTaxId)  BRANCH: \(storeBranchCode)")
                    .font(.system(size: 7.5, design: .monospaced)).foregroundColor(.black.opacity(0.85))
            }
            Text(isTaxInvoice ? "ใบกำกับภาษีอย่างย่อ" : "ใบเสร็จรับเงิน")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(.black).padding(.top, 2)
            if showTableInfo {
                Text("คิวที่ #32")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.black).padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity)

        monoDiv

        // ── Customer & Order Info ───────────────────────────────────────
        VStack(alignment: .leading, spacing: 1.5) {
            if showCustomerInfo {
                mono8("ลูกค้า (Customer): สมชาย ว. (Member)")
                mono8("TAX ID ลูกค้า: 0105559876543")
                monoDiv
            }

            mono8("วันที่ (Date): 2026-06-22 14:32")
            mono8("เลขที่ใบเสร็จ: RCP-20260622-0001")
            mono8("ออเดอร์ (Order): #AP-102546")
            if showTableInfo {
                mono8("โต๊ะ (Table): 08 (Zone A)")
            }
            if showOrderType {
                mono8("ประเภท: ทานที่ร้าน (Dine-In) | จำนวน: 3 ท่าน")
            }
            mono8("พนักงาน (Cashier): แอดมิน (Admin)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)

        monoDiv

        // ── Items Header ────────────────────────────────────────────────
        HStack {
            Text("รายการ / ITEM").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
            Text("จำนวน").fontWeight(.bold).frame(width: 32, alignment: .trailing)
            Text("รวมเงิน").fontWeight(.bold).frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        monoDiv

        // ── Items ───────────────────────────────────────────────────────
        Group {
            itemRow("Premium Beef Burger", qty: 2, price: "440.00")
            unitPriceRow(qty: 2, unitPrice: "220.00")
            if showItemModifiers {
                modRow("+ Extra Cheese (+฿40)")
                modRow("+ Medium Rare")
            }
            itemRow("Crispy French Fries", qty: 1, price: "120.00")
            unitPriceRow(qty: 1, unitPrice: "120.00")
            if showItemModifiers { modRow("+ Spicy Seasoning") }
            itemRow("Matcha Latte (Oat)", qty: 2, price: "220.00")
            unitPriceRow(qty: 2, unitPrice: "110.00")
            if showItemModifiers {
                modRow("+ Sweet 50% (x2)")
                modRow("+ Oat Milk (+฿30)")
            }
        }

        monoDiv

        // ── Totals ──────────────────────────────────────────────────────
        let previewCalculation = ReceiptCalculationEngine.calculate(.init(
            lines: [
                .init(id: "burger", name: "Premium Beef Burger", quantity: 2, unitPrice: 220, taxRate: enableTax ? 7 : 0, taxInclusive: storeTaxType == "inclusive"),
                .init(id: "fries", name: "Crispy French Fries", quantity: 1, unitPrice: 120, taxRate: enableTax ? 7 : 0, taxInclusive: storeTaxType == "inclusive"),
                .init(id: "latte", name: "Matcha Latte (Oat)", quantity: 2, unitPrice: 110, taxRate: enableTax ? 7 : 0, taxInclusive: storeTaxType == "inclusive")
            ],
            discount: 39,
            serviceChargeRate: 10,
            serviceChargeEnabled: showServiceCharge && enableServiceCharge,
            serviceChargeTaxable: true,
            serviceChargeTaxRate: enableTax ? 7 : 0,
            serviceChargeTaxInclusive: storeTaxType == "inclusive",
            customerTaxExempt: false,
            roundingMode: .perLine
        ))
        let previewSubtotal = NSDecimalNumber(decimal: previewCalculation.subtotal).doubleValue
        let previewSC = NSDecimalNumber(decimal: previewCalculation.serviceCharge).doubleValue
        let previewTax = NSDecimalNumber(decimal: previewCalculation.tax).doubleValue
        let previewTaxableBase = NSDecimalNumber(decimal: previewCalculation.taxableBase).doubleValue
        let previewTotal = NSDecimalNumber(decimal: previewCalculation.total).doubleValue
        
        Group {
            totalRow("ยอดรวม (SUBTOTAL)", value: String(format: "%.2f", previewSubtotal))
            if showServiceCharge && enableServiceCharge {
                totalRow("ค่าบริการ (SERVICE 10%)", value: String(format: "%.2f", previewSC))
            }
            totalRow("ส่วนลด (DISCOUNT)", value: "-39.00")
            if enableTax {
                totalRow("ฐานภาษี (TAX BASE)", value: String(format: "%.2f", previewTaxableBase))
                totalRow(storeTaxType == "inclusive" ? "ภาษี VAT 7% (INCLUDED)" : "ภาษี VAT 7%", value: String(format: "%.2f", previewTax))
            }
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1).padding(.vertical, 3)

        HStack {
            Text("ยอดรวมสุทธิ (TOTAL)").fontWeight(.black)
            Spacer()
            Text(String(format: "THB %.2f", previewTotal)).fontWeight(.black)
        }
        .font(.system(.caption, design: .monospaced)).foregroundColor(.black)

        monoDiv

        // ── Payment & Change Breakdown ──────────────────────────────────
        VStack(alignment: .leading, spacing: 2) {
            totalRow("ชำระโดย (เงินสด / CASH)", value: String(format: "%.2f", previewTotal))
            totalRow("  รับเงินมา (TENDERED)", value: "1000.00")
            totalRow("  เงินทอน (CHANGE)", value: String(format: "%.2f", max(0, 1000.00 - previewTotal)))
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        monoDiv

        // ── Enhanced Footer ─────────────────────────────────────────────
        VStack(spacing: 3) {
            Text("ขอบคุณที่ใช้บริการ")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
            Text("THANK YOU FOR YOUR PATRONAGE")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
            Text("โปรดตรวจสอบรายการและเงินทอนก่อนออกจากร้าน")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.black.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)

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
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var img: UIImage? = nil

            // storeLogoPath อาจเป็น filename หรือ full path
            if let fileURL = URL(string: storeLogoPath), fileURL.isFileURL {
                img = UIImage(contentsOfFile: fileURL.path)
            } else if fm.fileExists(atPath: storeLogoPath) {
                img = UIImage(contentsOfFile: storeLogoPath)
            } else if !storeLogoPath.isEmpty,
                      let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let url = docs.appendingPathComponent(storeLogoPath)
                if let data = try? Data(contentsOf: url) {
                    img = UIImage(data: data)
                }
            }

            // ร้านที่ซิงก์มาจาก server เก็บโลโก้เป็น remote URL แทน local path
            if img == nil,
               let rawURL = UserDefaults.standard.string(forKey: "store_logo_url"),
               let remoteURL = URL(string: rawURL),
               let data = try? Data(contentsOf: remoteURL),
               let remoteImage = UIImage(data: data) {
                img = remoteImage
                if let cacheURL = ESCPOSBuilder.remoteLogoCacheURL() {
                    try? data.write(to: cacheURL, options: .atomic)
                }
            }

            if img == nil,
               let cacheURL = ESCPOSBuilder.remoteLogoCacheURL(),
               let data = try? Data(contentsOf: cacheURL) {
                img = UIImage(data: data)
            }

            let loadedImage = img
            await MainActor.run { self.logoImage = loadedImage }
        }
    }

    private func generateQR() {
        guard showQRCode else { qrImage = nil; return }

        let qrString: String
        if previewType == .receipt {
            qrString = "ALPHAPOS-RECEIPT:RCP-20260622-0001"
        } else {
            qrString = promptPayNumber.isEmpty
                ? "https://alphapos.app/receipt/preview"
                : buildPromptPayPayload(target: promptPayNumber, amount: 878.00)
        }

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
            Text("\(qty)").frame(width: 32, alignment: .trailing)
            Text(price).frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)
    }

    private func unitPriceRow(qty: Int, unitPrice: String) -> some View {
        Text("  \(qty) × THB \(unitPrice) / unit")
            .font(.system(size: 7, design: .monospaced))
            .foregroundColor(.black.opacity(0.65))
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
