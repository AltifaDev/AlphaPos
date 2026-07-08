// OrganizationManagementView.swift
// AlphaPos — Enterprise Multi-Tenant Organization Management
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData
import PhotosUI

/// Organization / Tenant Management for enterprise multi-tenant POS.
struct OrganizationManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    // Store settings stored in UserDefaults/AppStorage
    @AppStorage("store_name") private var storeName = "AlphaPos Restaurant"
    @AppStorage("store_phone") private var storePhone = "02-123-4567"
    @AppStorage("store_website") private var storeWebsite = "www.alphapos.restaurant"
    @AppStorage("store_address") private var storeAddress = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id") private var storeTaxId = "1234567890123"
    @AppStorage("store_email") private var storeEmail = "admin@myrestaurant.com"
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"

    @Query(sort: \AuditLog.createdAt, order: .reverse) private var auditLogs: [AuditLog]

    @State private var selectedSection: OrgSection = .profile
    @State private var showSubscriptionSettings = false

    // M-10: Billing states
    @State private var showingBillingHistory = false
    @State private var billingPlan = "Starter"

    // M-11: API Keys states
    @State private var showingNewKeyAlert = false
    @State private var newKeyName = ""
    @State private var generatedKey: String? = nil
    @AppStorage("api_keys_json") private var apiKeysJson = "[]"
    @State private var apiKeysCopied: String? = nil

    // M-12: Data Export states
    @State private var isExporting = false
    @State private var exportMessage: String? = nil
    @State private var showingImportConfirm = false
    @State private var showingDeleteAllConfirm = false

    @AppStorage("store_logo_path") private var storeLogoPath = ""
    @State private var selectedLogoItems: [PhotosPickerItem] = []
    @State private var logoImage: UIImage? = nil

    enum OrgSection: String, CaseIterable, Identifiable {
        case profile = "Profile"
        case subscription = "Subscription"
        case billing = "Billing"
        case apiKeys = "API Keys"
        case auditLog = "Audit Log"
        case dataExport = "Data & Backup"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .profile: return "building.2.fill"
            case .subscription: return "creditcard.fill"
            case .billing: return "doc.text.fill"
            case .apiKeys: return "key.fill"
            case .auditLog: return "list.bullet.clipboard.fill"
            case .dataExport: return "externaldrive.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left nav
            sectionNav
                .frame(width: 220)

            Divider().background(Color.appDivider)

            // Content
            sectionContent
                .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showSubscriptionSettings) {
            NavigationStack { SubscriptionSettingsView() }
        }
        .onAppear {
            loadStoredLogo()
        }
        .onChange(of: selectedLogoItems) { _, newItems in
            handleLogoSelection(newItems)
        }
    }

    // MARK: - Section Nav

    private var sectionNav: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Org header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appAccent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.appAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(storeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(offlineSyncMode ? "Offline Plan" : "Enterprise Plan")
                        .font(.system(size: 10))
                        .foregroundColor(.appAccent)
                }
            }
            .padding()

            Divider().background(Color.appDivider).padding(.horizontal)

            // Sections
            ForEach(OrgSection.allCases) { section in
                Button {
                    withAnimation { selectedSection = section }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 14))
                            .foregroundColor(selectedSection == section ? .appAccent : .textSecondary)
                            .frame(width: 24)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                            .foregroundColor(selectedSection == section ? .textPrimary : .textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(selectedSection == section ? Color.appAccent.opacity(0.08) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(Color.appSurface)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedSection {
                case .profile:
                    profileSection
                case .subscription:
                    subscriptionSection
                case .billing:
                    billingSection
                case .apiKeys:
                    apiKeysSection
                case .auditLog:
                    auditLogSection
                case .dataExport:
                    dataExportSection
                }
            }
            .padding(24)
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_profile".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)

            // Logo Picker Card
            HStack(spacing: 16) {
                if let logoImage = logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appDivider, lineWidth: 1))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appSurfaceHigh)
                            .frame(width: 80, height: 80)
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundColor(.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("โลโก้ร้านค้า (Store Logo)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("โลโก้ร้านค้าจะแสดงบนหน้าจอ POS และพิมพ์บนใบเสร็จรับเงินใบส่งของ")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 10) {
                        PhotosPicker(
                            selection: $selectedLogoItems,
                            maxSelectionCount: 1,
                            matching: .images
                        ) {
                            Text("เลือกรูปภาพ")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(APGradient.accent)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        if logoImage != nil {
                            Button(action: removeLogo) {
                                Text("ลบโลโก้")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.appRose.opacity(0.12))
                                    .foregroundColor(.appRose)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.appSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appDivider, lineWidth: 1))

            formField(label: "Organization Name", text: $storeName, icon: "building.2")
            formField(label: "Tax ID", text: $storeTaxId, icon: "doc.text")
            formField(label: "Address", text: $storeAddress, icon: "mappin")
            formField(label: "Phone", text: $storePhone, icon: "phone")
            formField(label: "Email", text: $storeEmail, icon: "envelope")
            formField(label: "Website", text: $storeWebsite, icon: "globe")
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_subscription".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)

            // Current plan card
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(offlineSyncMode ? "Offline Perpetual" : "Enterprise")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.appAccent)
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                    Text("org_plan_features".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Text(offlineSyncMode ? "ถาวร • ไม่มีการเก็บค่าบริการคลาวด์" : "Next billing: July 1, 2026 • ฿4,990/month")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()

                if offlineSyncMode {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Manage Plan") { }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textSecondary)
                            .cornerRadius(8)
                            .disabled(true)

                        Text("ไม่สามารถจัดการแพ็กเกจขณะออฟไลน์")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                } else {
                    Button("Manage Plan") { showSubscriptionSettings = true }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.appAccent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.appSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.appAccent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Billing

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_billing".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)

            // M-10: Current Plan Card
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appAmber)
                    .padding(12)
                    .background(Color.appAmber.opacity(0.12))
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("org_current_plan".t)
                        .font(.caption).foregroundColor(.textTertiary)
                    Text(billingPlan)
                        .font(.headline.bold()).foregroundColor(.textPrimary)
                    Text("org_billing_next_cycle".t)
                        .font(.caption2).foregroundColor(.textSecondary)
                }
                Spacer()
                Button("org_upgrade_btn".t) {}
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(APGradient.accent)
                    .cornerRadius(8)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))

            // Billing History
            VStack(alignment: .leading, spacing: 10) {
                Text("org_billing_history".t)
                    .font(.caption.bold()).foregroundColor(.appAccent).tracking(0.8)
                ForEach(0..<3) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Calendar.current.date(byAdding: .month, value: -i, to: Date())!
                                    .formatted(.dateTime.month(.wide).year()))
                                .font(.subheadline.bold()).foregroundColor(.textPrimary)
                            Text(billingPlan + " Plan")
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Text(i == 0 ? "org_billing_upcoming".t : "org_billing_paid".t)
                            .font(.caption2.bold())
                            .foregroundColor(i == 0 ? .appAmber : .appTeal)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((i == 0 ? Color.appAmber : Color.appTeal).opacity(0.12))
                            .cornerRadius(6)
                        Text(i == 0 ? "org_billing_amount_pending".t : "฿990")
                            .font(.subheadline.bold()).foregroundColor(.textPrimary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(10)
                    .background(Color.appSurface)
                    .cornerRadius(10)
                }
            }

            if offlineSyncMode {
                Label("org_offline_billing_warning".t, systemImage: "wifi.slash")
                    .font(.caption2).foregroundColor(.orange)
                    .padding(10).background(Color.orange.opacity(0.08)).cornerRadius(8)
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("org_api_keys".t)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                // M-11: Generate new API key
                Button(action: {
                    guard !offlineSyncMode else { return }
                    newKeyName = ""
                    generatedKey = nil
                    showingNewKeyAlert = true
                }) {
                    Label("org_api_new_key_btn".t, systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background {
                            if offlineSyncMode {
                                Color.appSurfaceHigh
                            } else {
                                APGradient.accent
                            }
                        }
                        .cornerRadius(8)
                }

                .disabled(offlineSyncMode)
            }
            Text("org_api_keys_desc".t)
                .font(.subheadline).foregroundColor(.textTertiary)

            // Parse stored API keys
            let storedKeys: [[String: String]] = (try? JSONDecoder().decode([[String: String]].self,
                from: apiKeysJson.data(using: .utf8) ?? Data())) ?? []

            if offlineSyncMode {
                Label("org_offline_api_warning".t, systemImage: "lock.wifi.slash")
                    .font(.caption2).foregroundColor(.orange)
                    .padding(10).background(Color.orange.opacity(0.08)).cornerRadius(8)
            }

            if storedKeys.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "key.slash").foregroundColor(.textTertiary)
                    Text("org_no_api_keys".t).font(.subheadline).foregroundColor(.textSecondary)
                }
                .padding(14).background(Color.appSurfaceHigh).cornerRadius(10)
            } else {
                VStack(spacing: 8) {
                    ForEach(storedKeys.indices, id: \.self) { i in
                        let key = storedKeys[i]
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.appAccent).font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(Color.appAccent.opacity(0.1)).cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key["name"] ?? "org_api_key_default_name".t)
                                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                Text(maskKey(key["value"] ?? ""))
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = key["value"]
                                apiKeysCopied = key["value"]
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeysCopied = nil }
                            } label: {
                                Image(systemName: apiKeysCopied == key["value"] ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(apiKeysCopied == key["value"] ? .appTeal : .textSecondary)
                                    .font(.system(size: 15))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10).background(Color.appSurface).cornerRadius(10)
                    }
                }
            }

            // New Key alert sheet
            if showingNewKeyAlert {
                VStack(alignment: .leading, spacing: 10) {
                    Text("org_api_key_name_lbl".t).font(.caption.bold()).foregroundColor(.textSecondary)
                    TextField("org_api_key_name_placeholder".t, text: $newKeyName)
                        .textFieldStyle(.roundedBorder)
                    if let generated = generatedKey {
                        Text(generated)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.appTeal)
                            .padding(8).background(Color.appTeal.opacity(0.08)).cornerRadius(8)
                        Text("org_api_key_copy_hint".t).font(.caption2).foregroundColor(.textTertiary)
                    }
                    HStack {
                        Button("cancel_btn".t) { showingNewKeyAlert = false }
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Button("org_api_generate_btn".t) { generateAPIKey() }
                            .disabled(newKeyName.isEmpty)
                            .foregroundColor(newKeyName.isEmpty ? .textTertiary : .appAccent)
                            .fontWeight(.bold)
                    }
                }
                .padding(14).background(Color.appSurfaceHigh).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
            }
        }
    }

    // MARK: - Audit Log

    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_audit_log".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("org_audit_log_desc".t)
                .font(.subheadline)
                .foregroundColor(.textTertiary)

            if auditLogs.isEmpty {
                Text("No audit logs found")
                    .font(.subheadline)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(auditLogs.prefix(5)) { log in
                    HStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "list.bullet.clipboard.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.appAccent)
                            )
                        VStack(alignment: .leading) {
                            Text(log.details ?? log.actionType)
                                .font(.system(size: 13))
                                .foregroundColor(.textPrimary)
                            Text("\(log.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Data Export

    private var dataExportSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_data_export".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)

            if offlineSyncMode {
                Label("org_offline_export_warning".t, systemImage: "wifi.slash")
                    .font(.caption2).foregroundColor(.orange)
                    .padding(10).background(Color.orange.opacity(0.08)).cornerRadius(8)
            }

            // M-12: Export All Data (CSV/JSON)
            exportRow(
                icon: "arrow.down.doc.fill", title: "org_export_all".t,
                subtitle: "org_export_all_desc".t, color: .blue,
                isLoading: isExporting
            ) {
                Task { await exportAllData() }
            }

            // Backup History (informational)
            exportRow(
                icon: "clock.arrow.circlepath", title: "org_backup_history".t,
                subtitle: "org_backup_history_desc".t, color: .appTeal,
                isLoading: false
            ) {
                exportMessage = "org_backup_auto_msg".t
            }

            // Import Data
            exportRow(
                icon: "arrow.up.doc.fill", title: "org_import_data".t,
                subtitle: "org_import_data_desc".t, color: .appAmber,
                isLoading: false
            ) {
                showingImportConfirm = true
            }

            // Delete All
            exportRow(
                icon: "trash.fill", title: "org_delete_all".t,
                subtitle: "org_delete_all_desc".t, color: .appRose,
                isLoading: false
            ) {
                showingDeleteAllConfirm = true
            }
            if let msg = exportMessage {
                Text(msg).font(.caption).foregroundColor(.appTeal)
                    .padding(10).background(Color.appTeal.opacity(0.08)).cornerRadius(8)
            }
        }
        .alert("org_import_confirm_title".t, isPresented: $showingImportConfirm) {
            Button("cancel_btn".t, role: .cancel) {}
            Button("org_import_confirm_btn".t) { exportMessage = "org_import_coming_soon".t }
        } message: { Text("org_import_confirm_msg".t) }
        .alert("org_delete_all_title".t, isPresented: $showingDeleteAllConfirm) {
            Button("cancel_btn".t, role: .cancel) {}
            Button("org_delete_all_confirm_btn".t, role: .destructive) {
                exportMessage = "org_delete_all_coming_soon".t
            }
        } message: { Text("org_delete_all_msg".t) }
    }

    // M-12: Updated exportRow with action closure and loading state
    private func exportRow(icon: String, title: String, subtitle: String, color: Color,
                           isLoading: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            if isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formField(label: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.appAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                TextField(label, text: text)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
                    .textFieldStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(10)
    }

    // MARK: - Logo Operations

    private func loadStoredLogo() {
        guard !storeLogoPath.isEmpty else { return }
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: storeLogoPath)

        if fileManager.fileExists(atPath: url.path) {
            logoImage = UIImage(contentsOfFile: url.path)
        } else {
            // Re-resolve in Documents directory if sandbox UUID has rotated
            let filename = url.lastPathComponent
            if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let resolvedUrl = docDir.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: resolvedUrl.path) {
                    logoImage = UIImage(contentsOfFile: resolvedUrl.path)
                    storeLogoPath = resolvedUrl.path
                }
            }
        }
    }

    private func handleLogoSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {

                let fileManager = FileManager.default
                if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = docDir.appendingPathComponent("store_logo.png")
                    do {
                        try data.write(to: fileURL)
                        await MainActor.run {
                            self.logoImage = image
                            self.storeLogoPath = fileURL.path

                            // Register audit log
                            let newLog = AuditLog(
                                actionType: "UPDATE_STORE_LOGO",
                                details: "Updated store logo for receipts"
                            )
                            modelContext.insert(newLog)
                        }

                        // Upload store logo to Supabase storage if online
                        let connected = await NetworkManager.shared.isConnected()
                        if !offlineSyncMode && connected {
                            do {
                                let publicURL = try await NetworkManager.shared.uploadStoreLogo(data, merchantId: activeMerchantId)
                                UserDefaults.standard.set(publicURL, forKey: "store_logo_url")
                            } catch {
                                print("Failed to upload logo to Supabase Storage: \(error)")
                            }
                        }
                    } catch {
                        print("Failed to save store logo: \(error)")
                    }
                }
            }
        }
    }

    private func removeLogo() {
        let fileManager = FileManager.default
        if !storeLogoPath.isEmpty {
            let url = URL(fileURLWithPath: storeLogoPath)
            try? fileManager.removeItem(at: url)
        }

        logoImage = nil
        storeLogoPath = ""
        selectedLogoItems = []

        // Register audit log
        let newLog = AuditLog(
            actionType: "REMOVE_STORE_LOGO",
            details: "Removed store logo"
        )
        modelContext.insert(newLog)
    }
}

// MARK: - M-11/12 Helper Extensions (private)

extension OrganizationManagementView {

    // M-11: Generate a random API key and persist to AppStorage
    func generateAPIKey() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let prefix = "ap_" + activeMerchantId.prefix(8)
        let random = String((0..<32).map { _ in chars.randomElement()! })
        let newKey = "\(prefix)_\(random)"

        var storedKeys: [[String: String]] = (try? JSONDecoder().decode(
            [[String: String]].self,
            from: apiKeysJson.data(using: .utf8) ?? Data()
        )) ?? []
        storedKeys.append(["name": newKeyName, "value": newKey,
                            "createdAt": ISO8601DateFormatter().string(from: Date())])
        if let encoded = try? JSONEncoder().encode(storedKeys),
           let str = String(data: encoded, encoding: .utf8) {
            apiKeysJson = str
        }
        generatedKey = newKey
        UIPasteboard.general.string = newKey
        APHaptic.trigger()
    }

    // M-11: Mask key for display — show first 10 chars + ***
    func maskKey(_ key: String) -> String {
        guard key.count > 10 else { return key }
        return String(key.prefix(10)) + "••••••••••••"
    }

    // M-12: Export all SwiftData to JSON in temp directory and share
    func exportAllData() async {
        await MainActor.run { isExporting = true }
        do {
            let exportData: [String: Any] = [
                "exported_at": ISO8601DateFormatter().string(from: Date()),
                "merchant_id": activeMerchantId,
                "store_name":  storeName,
                "note": "Full data export — use Supabase dashboard for complete table-level export"
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("alphapos_export_\(Date().timeIntervalSince1970).json")
            try jsonData.write(to: tmpURL)

            await MainActor.run {
                isExporting = false
                exportMessage = "org_export_success_msg".t + " → " + tmpURL.lastPathComponent
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportMessage = "org_export_failed_msg".t + ": \(error.localizedDescription)"
            }
        }
    }
}
