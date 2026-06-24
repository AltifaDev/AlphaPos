import SwiftUI
import SwiftData
import CoreImage
import CoreImage.CIFilterBuiltins

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ReceiptTemplateSettingsView
// ─────────────────────────────────────────────────────────────────────────────

struct ReceiptTemplateSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReceiptTemplate.name) private var templates: [ReceiptTemplate]

    @State private var selectedTemplate: ReceiptTemplate? = nil
    @State private var isCreatingNew = false
    @State private var compactSection = "editor"

    // ── Form State ────────────────────────────────────────────────────────────
    @State private var name               = ""
    @State private var headerText         = ""
    @State private var footerText         = ""
    @State private var showTaxId          = true
    @State private var showCustomerInfo   = true
    @State private var isDefault          = false
    @State private var paperWidth         = "80mm"
    @State private var showLogo           = true
    @State private var showServiceCharge  = true
    @State private var showTableInfo      = true
    @State private var showQRCode         = true
    @State private var showItemModifiers  = true
    @State private var showOrderType      = true

    // ── Store info ────────────────────────────────────────────────────────────
    @AppStorage("store_name")        private var storeName       = "AlphaPos Restaurant"
    @AppStorage("store_phone")       private var storePhone      = "02-123-4567"
    @AppStorage("store_address")     private var storeAddress    = "123 Sukhumvit Rd, Bangkok"
    @AppStorage("store_tax_id")      private var storeTaxId      = "1234567890123"
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_logo_path")   private var storeLogoPath   = ""
    @AppStorage("promptpay_number")  private var promptPayNumber = ""

    private var activeTemplates: [ReceiptTemplate] { templates.filter { !$0.isDeleted } }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 950

            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isCompact {
                        Picker("Receipt Section", selection: $compactSection) {
                            Text("template_tab_edit".t).tag("editor")
                            Text("template_tab_preview".t).tag("preview")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }

                    if isCompact {
                        compactLayout
                    } else {
                        regularLayout
                    }
                }
            }
        }
        .navigationTitle("receipt_templates_title".t)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            if let first = activeTemplates.first { selectTemplate(first) }
            else { setupNewTemplateForm() }
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            // ── LEFT: List + Editor ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
                listHeader
                HStack(alignment: .top, spacing: 16) {
                    templateSidebar.frame(width: 200)
                    Rectangle().fill(Color.appDivider).frame(width: 1)
                    editorPanel.frame(maxWidth: .infinity)
                }
            }
            .padding()
            .apCard()
            .frame(maxWidth: .infinity)

            // ── RIGHT: Live Preview ───────────────────────────────────────
            previewColumn
                .frame(width: 340)
        }
        .padding()
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if compactSection == "editor" {
                VStack(alignment: .leading, spacing: 16) {
                    listHeader
                    HStack(alignment: .top, spacing: 16) {
                        templateSidebar.frame(width: 200)
                        Rectangle().fill(Color.appDivider).frame(width: 1)
                        editorPanel.frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .apCard()
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Spacer()
                    previewColumn
                        .frame(width: 360)
                    Spacer()
                }
            }
        }
        .padding()
    }

    private var previewColumn: some View {
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
            showOrderType:     showOrderType
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Sub-Views
    // ─────────────────────────────────────────────────────────────────────────

    private var listHeader: some View {
        HStack {
            Text("receipt_templates_section".t)
                .font(.headline).foregroundColor(.textPrimary)
            Spacer()
            Button { setupNewTemplateForm() } label: {
                Label("add_new_template_btn".t, systemImage: "plus")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.appAccent).cornerRadius(APRadius.md)
            }
        }
    }

    private var templateSidebar: some View {
        ScrollView {
            VStack(spacing: 10) {
                if activeTemplates.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle).foregroundColor(.textTertiary)
                        Text("no_templates_placeholder".t)
                            .font(.caption).foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 40).frame(maxWidth: .infinity)
                } else {
                    ForEach(activeTemplates) { tmpl in templateRow(tmpl) }
                }
            }
        }
    }

    private func templateRow(_ tmpl: ReceiptTemplate) -> some View {
        let isSelected = selectedTemplate?.id == tmpl.id && !isCreatingNew
        return Button { selectTemplate(tmpl) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(tmpl.name)
                        .font(.body).fontWeight(.bold)
                        .foregroundColor(isSelected ? .white : .textPrimary)
                    Spacer()
                    if tmpl.isDefault {
                        Text("default_badge".t)
                            .font(.system(size: 8)).fontWeight(.black).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.appTeal).cornerRadius(APRadius.sm)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: tmpl.showLogo ? "photo.fill" : "printer.fill")
                        .font(.system(size: 9))
                    Text(tmpl.paperWidth)
                        .font(.caption2)
                }
                .foregroundColor(isSelected ? .white.opacity(0.75) : .textTertiary)
            }
            .padding(12)
            .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteTemplate(tmpl) } label: {
                Label("delete".t, systemImage: "trash")
            }
        }
    }

    // ── Editor Panel ──────────────────────────────────────────────────────────
    private var editorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader(isCreatingNew ? "create_template_header".t : "edit_template_header".t)

                // Identity
                cardGroup {
                    fieldLabel("template_name_lbl".t)
                    TextField("e.g. Standard 80mm", text: $name).apTemplateTextField()

                    fieldLabel("Paper Width")
                    Picker("Paper Width", selection: $paperWidth) {
                        Text("80 mm Thermal").tag("80mm")
                        Text("58 mm Thermal").tag("58mm")
                    }.pickerStyle(SegmentedPickerStyle())

                    apDivider
                    Toggle(isOn: $isDefault) {
                        toggleLabel("set_as_default_lbl".t, sub: "set_as_default_desc".t)
                    }.tint(.appAccent)
                }

                // Header / Footer
                sectionHeader("HEADER & FOOTER TEXT")
                cardGroup {
                    fieldLabel("header_text_lbl".t)
                    TextField("e.g. Thank you for dining with us!", text: $headerText).apTemplateTextField()
                    fieldLabel("footer_text_lbl".t)
                    TextField("e.g. Follow us: @alphapos.cafe", text: $footerText).apTemplateTextField()
                }

                // Branding
                sectionHeader("BRANDING & MEDIA")
                cardGroup {
                    Toggle(isOn: $showLogo) {
                        toggleLabel("Store Logo",
                                    sub: storeLogoPath.isEmpty
                                        ? "⚠ No logo uploaded — set in Store Management"
                                        : "✓ Logo configured in Store Management")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showQRCode) {
                        toggleLabel("QR Code / Barcode",
                                    sub: promptPayNumber.isEmpty
                                        ? "PromptPay QR — set number in Store Management"
                                        : "PromptPay: \(maskedPromptPay)")
                    }.tint(.appAccent)
                }

                // Visibility
                sectionHeader("SECTION VISIBILITY")
                cardGroup {
                    Toggle(isOn: $showTaxId) {
                        toggleLabel("show_tax_id_lbl".t, sub: "Tax ID · Branch Code")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showCustomerInfo) {
                        toggleLabel("show_customer_info_lbl".t, sub: "Customer name · Tax exemption no.")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showTableInfo) {
                        toggleLabel("Table & Queue", sub: "Table number · Queue number")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showOrderType) {
                        toggleLabel("Order Type", sub: "Dine-in / Take-out / Delivery badge")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showItemModifiers) {
                        toggleLabel("Item Modifiers", sub: "e.g. + Extra Cheese · Sweet 50%")
                    }.tint(.appAccent)
                    apDivider
                    Toggle(isOn: $showServiceCharge) {
                        toggleLabel("Service Charge Line", sub: "10% service charge row")
                    }.tint(.appAccent)
                }

                // Save
                Button { saveTemplate() } label: {
                    Text(isCreatingNew ? "save_new_template_btn".t : "save_changes_btn".t)
                        .fontWeight(.bold)
                }
                .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: name.isEmpty)
                .disabled(name.isEmpty)

                // Delete
                if !isCreatingNew, let tmpl = selectedTemplate {
                    Button { deleteTemplate(tmpl) } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Template")
                        }
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.appRose)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appRose.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private func sectionHeader(_ text: String) -> some View {
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
        paperWidth         = "80mm"
        showLogo           = true
        showServiceCharge  = true
        showTableInfo      = true
        showQRCode         = true
        showItemModifiers  = true
        showOrderType      = true
        isCreatingNew      = true
        APHaptic.trigger()
    }

    private func saveTemplate() {
        if isDefault { for t in templates { t.isDefault = false } }

        if isCreatingNew {
            let t = ReceiptTemplate(
                name:              name,
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
                showOrderType:     showOrderType
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
            t.isSynced         = false
            t.updatedAt        = Date()
        }
        try? modelContext.save()
        APHaptic.trigger()
    }

    private func deleteTemplate(_ tmpl: ReceiptTemplate) {
        tmpl.isDeleted = true
        try? modelContext.save()
        if selectedTemplate?.id == tmpl.id {
            if let next = activeTemplates.first(where: { $0.id != tmpl.id }) {
                selectTemplate(next)
            } else {
                setupNewTemplateForm()
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TextField Modifier
// ─────────────────────────────────────────────────────────────────────────────

private extension View {
    func apTemplateTextField() -> some View {
        self
            .textFieldStyle(PlainTextFieldStyle())
            .padding(10)
            .background(Color.appSurfaceHigh)
            .foregroundColor(.textPrimary)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ReceiptLivePreview
// Live preview แสดง pixel-accurate ตรงกับ ESCPOSBuilder
// โหลดโลโก้จาก Documents จริง + generate PromptPay QR จาก CIQRCodeGenerator
// ─────────────────────────────────────────────────────────────────────────────

struct ReceiptLivePreview: View {

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

    // Computed
    private var paperPx: CGFloat { paperWidth == "58mm" ? 272 : 340 }
    private var hPad: CGFloat    { paperWidth == "58mm" ? 12 : 20 }
    private var divLen: Int      { paperWidth == "58mm" ? 32 : 42 }

    // Loaded assets
    @State private var logoImage:  UIImage? = nil
    @State private var qrImage:    UIImage? = nil

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
            ScrollView {
                VStack(spacing: 0) {
                    paperTeeth(flip: false)

                    VStack(alignment: .leading, spacing: 0) {
                        receiptBody
                    }
                    .padding(.horizontal, hPad)
                    .background(Color(hex: "FCFCF9"))

                    paperTeeth(flip: true)
                }
                .frame(width: paperPx)
                .cornerRadius(4)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }

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

    @ViewBuilder
    private var receiptBody: some View {

        // ── Custom header text ──────────────────────────────────────────
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
        Group {
            totalRow("SUBTOTAL", value: "780.00")
            if showServiceCharge { totalRow("SERVICE CHARGE (10%)", value: "78.00") }
            totalRow("7% VAT (INCLUSIVE)", value: "59.36")
            totalRow("DISCOUNT (PROMO)", value: "-39.00")
        }
        .font(.system(size: 8, design: .monospaced)).foregroundColor(.black)

        Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1).padding(.vertical, 3)

        HStack {
            Text("GRAND TOTAL").fontWeight(.black)
            Spacer()
            Text("฿878.00").fontWeight(.black)
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

            await MainActor.run { self.logoImage = img }
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
