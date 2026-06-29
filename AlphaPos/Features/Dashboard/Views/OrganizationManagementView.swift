// OrganizationManagementView.swift
// AlphaPos — Enterprise Multi-Tenant Organization Management
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData

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
    
    @Query(sort: \AuditLog.createdAt, order: .reverse) private var auditLogs: [AuditLog]
    
    @State private var selectedSection: OrgSection = .profile
    
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
                    Text("Enterprise Plan")
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
                        Text("Enterprise")
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
                    Text("Next billing: July 1, 2026 • ฿4,990/month")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button("Manage Plan") {}
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .buttonStyle(.plain)
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
            Text("org_billing_desc".t)
                .font(.subheadline)
                .foregroundColor(.textTertiary)
        }
    }
    
    // MARK: - API Keys
    
    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("org_api_keys".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("org_api_keys_desc".t)
                .font(.subheadline)
                .foregroundColor(.textTertiary)
            
            // Placeholder
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.appAccent)
                Text("pk_live_•••••••••••abc123")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.textSecondary)
                Spacer()
                Button("Regenerate") {}
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
            }
            .padding()
            .background(Color.appSurfaceHigh)
            .cornerRadius(10)
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
            
            VStack(spacing: 12) {
                exportRow(icon: "arrow.down.doc.fill", title: "org_export_all".t, subtitle: "org_export_all_desc".t, color: .blue)
                exportRow(icon: "clock.arrow.circlepath", title: "org_backup_history".t, subtitle: "org_backup_history_desc".t, color: .green)
                exportRow(icon: "arrow.up.doc.fill", title: "org_import_data".t, subtitle: "org_import_data_desc".t, color: .orange)
                exportRow(icon: "trash.fill", title: "org_delete_all".t, subtitle: "org_delete_all_desc".t, color: .red)
            }
        }
    }
    
    private func exportRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
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
}
