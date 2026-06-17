import SwiftUI
import SwiftData

struct ReceiptTemplateSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ReceiptTemplate.name) private var templates: [ReceiptTemplate]
    
    @State private var selectedTemplate: ReceiptTemplate? = nil
    
    // Form States
    @State private var name = ""
    @State private var headerText = ""
    @State private var footerText = ""
    @State private var showTaxId = true
    @State private var showCustomerInfo = true
    @State private var isDefault = false
    
    @State private var isCreatingNew = false
    
    // Mock Store Settings for Preview
    @AppStorage("store_name") private var storeName = "AlphaPos Restaurant"
    @AppStorage("store_phone") private var storePhone = "02-123-4567"
    @AppStorage("store_website") private var storeWebsite = "www.alphapos.restaurant"
    @AppStorage("store_address") private var storeAddress = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id") private var storeTaxId = "1234567890123"
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    
    private var activeTemplates: [ReceiptTemplate] {
        templates.filter { !$0.isDeleted }
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            HStack(spacing: 24) {
                // LEFT COLUMN: Template List and Editor Form
                VStack(alignment: .leading, spacing: 20) {
                    // Header Actions
                    HStack {
                        Text("receipt_templates_section".t)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        
                        Button {
                            setupNewTemplateForm()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("add_new_template_btn".t)
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
                    
                    // Main Content Area inside Left Column
                    HStack(spacing: 20) {
                        // Templates Sidebar List
                        ScrollView {
                            VStack(spacing: 12) {
                                if activeTemplates.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.largeTitle)
                                            .foregroundColor(.textTertiary)
                                        Text("no_templates_placeholder".t)
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.vertical, 40)
                                    .frame(maxWidth: .infinity)
                                } else {
                                    ForEach(activeTemplates) { template in
                                        Button {
                                            selectTemplate(template)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(template.name)
                                                        .font(.body)
                                                        .fontWeight(.bold)
                                                        .foregroundColor(selectedTemplate?.id == template.id && !isCreatingNew ? .white : .textPrimary)
                                                    
                                                    Spacer()
                                                    
                                                    if template.isDefault {
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
                                                
                                                if let header = template.headerText, !header.isEmpty {
                                                    Text(header)
                                                        .font(.caption2)
                                                        .foregroundColor(selectedTemplate?.id == template.id && !isCreatingNew ? .white.opacity(0.8) : .textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(14)
                                            .background(selectedTemplate?.id == template.id && !isCreatingNew ? Color.appAccent : Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.md)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: APRadius.md)
                                                    .stroke(selectedTemplate?.id == template.id && !isCreatingNew ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deleteTemplate(template)
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
                                Text(isCreatingNew ? "create_template_header".t : "edit_template_header".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                VStack(spacing: 16) {
                                    // Template Name Field
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("template_name_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        TextField("e.g. Standard Thermal", text: $name)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurface)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    
                                    // Header Text Field
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("header_text_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        TextField("e.g. Welcome to Our Store!", text: $headerText)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurface)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    
                                    // Footer Text Field
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("footer_text_lbl".t)
                                            .font(.caption).bold().foregroundColor(.textSecondary)
                                        TextField("e.g. Thank You, Please Come Again!", text: $footerText)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurface)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    
                                    // Toggles
                                    VStack(spacing: 12) {
                                        Toggle(isOn: $showTaxId) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("show_tax_id_lbl".t).font(.body).foregroundColor(.textPrimary)
                                                Text("show_tax_id_desc".t).font(.caption2).foregroundColor(.textTertiary)
                                            }
                                        }
                                        .tint(Color.appAccent)
                                        
                                        Divider().background(Color.appDivider)
                                        
                                        Toggle(isOn: $showCustomerInfo) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("show_customer_info_lbl".t).font(.body).foregroundColor(.textPrimary)
                                                Text("show_customer_info_desc".t).font(.caption2).foregroundColor(.textTertiary)
                                            }
                                        }
                                        .tint(Color.appAccent)
                                        
                                        Divider().background(Color.appDivider)
                                        
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
                                        saveTemplate()
                                    } label: {
                                        Text(isCreatingNew ? "save_new_template_btn".t : "save_changes_btn".t)
                                            .fontWeight(.bold)
                                    }
                                    .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: name.isEmpty)
                                    .disabled(name.isEmpty)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .apCard()
                .frame(maxWidth: .infinity)
                
                // RIGHT COLUMN: Dynamic Live Preview Panel
                receiptPreviewPanel
                    .frame(width: 320)
            }
            .padding()
        }
        .navigationTitle("receipt_templates_title".t)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            if let first = activeTemplates.first {
                selectTemplate(first)
            } else {
                setupNewTemplateForm()
            }
        }
    }
    
    // MARK: - Helper Actions
    private func selectTemplate(_ template: ReceiptTemplate) {
        selectedTemplate = template
        name = template.name
        headerText = template.headerText ?? ""
        footerText = template.footerText ?? ""
        showTaxId = template.showTaxId
        showCustomerInfo = template.showCustomerInfo
        isDefault = template.isDefault
        isCreatingNew = false
        APHaptic.trigger()
    }
    
    private func setupNewTemplateForm() {
        selectedTemplate = nil
        name = ""
        headerText = ""
        footerText = ""
        showTaxId = true
        showCustomerInfo = true
        isDefault = false
        isCreatingNew = true
        APHaptic.trigger()
    }
    
    private func saveTemplate() {
        if isDefault {
            for t in templates { t.isDefault = false }
        }
        
        if isCreatingNew {
            let newTemplate = ReceiptTemplate(
                name: name,
                headerText: headerText.isEmpty ? nil : headerText,
                footerText: footerText.isEmpty ? nil : footerText,
                showTaxId: showTaxId,
                showCustomerInfo: showCustomerInfo,
                isDefault: isDefault
            )
            modelContext.insert(newTemplate)
            selectedTemplate = newTemplate
            isCreatingNew = false
        } else if let template = selectedTemplate {
            template.name = name
            template.headerText = headerText.isEmpty ? nil : headerText
            template.footerText = footerText.isEmpty ? nil : footerText
            template.showTaxId = showTaxId
            template.showCustomerInfo = showCustomerInfo
            template.isDefault = isDefault
        }
        
        try? modelContext.save()
        APHaptic.trigger()
    }
    
    private func deleteTemplate(_ template: ReceiptTemplate) {
        template.isDeleted = true
        try? modelContext.save()
        if selectedTemplate?.id == template.id {
            if let next = activeTemplates.first(where: { !$0.isDeleted }) {
                selectTemplate(next)
            } else {
                setupNewTemplateForm()
            }
        }
    }
    
    // MARK: - Receipt Live Preview Panel
    private var receiptPreviewPanel: some View {
        VStack(spacing: 12) {
            Text("live_receipt_preview".t)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .tracking(1.0)
            
            // Thermal Receipt Paper Card
            VStack(spacing: 8) {
                // Receipt Header
                Image(systemName: "storefront.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                
                Text(storeName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(storeAddress)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                
                Text("TEL: \(storePhone)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text("TAX INVOICE (ABB.)")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .padding(.vertical, 4)
                
                if showTaxId {
                    HStack {
                        Text("TAX ID: \(storeTaxId)")
                        Spacer()
                        Text("BRANCH: \(storeBranchCode)")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                }
                
                if showCustomerInfo {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CUSTOMER: John Doe (VIP)")
                            Text("TAX EXEMPTION NO: EX-99221")
                        }
                        Spacer()
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                }
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Mock Order Items
                VStack(spacing: 4) {
                    HStack {
                        Text("1 x Classic Pad Thai")
                        Spacer()
                        Text("120.00")
                    }
                    HStack {
                        Text("1 x Traditional Thai Iced Tea")
                        Spacer()
                        Text("85.00")
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Totals
                VStack(spacing: 3) {
                    HStack {
                        Text("SUBTOTAL")
                        Spacer()
                        Text("191.59")
                    }
                    HStack {
                        Text("VAT (7% - INCL)")
                        Spacer()
                        Text("13.41")
                    }
                    HStack {
                        Text("TOTAL")
                            .fontWeight(.bold)
                        Spacer()
                        Text("฿205.00")
                            .fontWeight(.bold)
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                
                Text("----------------------------------------")
                    .foregroundColor(.gray)
                    .font(.system(.caption, design: .monospaced))
                
                // Custom Headers and Footers
                if !headerText.isEmpty {
                    Text(headerText)
                        .font(.system(size: 8, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                }
                
                if !footerText.isEmpty {
                    Text(footerText)
                        .font(.system(size: 8, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                }
                
                // Barcode simulation
                VStack(spacing: 2) {
                    HStack(spacing: 1.5) {
                        ForEach(0..<20, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: CGFloat([1, 2, 3].randomElement() ?? 1), height: 26)
                        }
                    }
                    Text("AP-TPL-PREVIEW")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.black)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color.white)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            .frame(width: 290)
            
            Spacer()
        }
        .padding()
        .apCard()
    }
}
