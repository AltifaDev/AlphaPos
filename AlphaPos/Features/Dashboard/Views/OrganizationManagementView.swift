// OrganizationManagementView.swift
// AlphaPos — Enterprise Multi-Tenant Organization Management

import SwiftUI
import SwiftData
import PhotosUI

/// Organization / Tenant Management for enterprise multi-tenant POS.
struct OrganizationManagementView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    // Empty defaults — avoid fake placeholder data looking like real merchant info.
    @AppStorage("store_name") private var storeName = ""
    @AppStorage("store_phone") private var storePhone = ""
    @AppStorage("store_website") private var storeWebsite = ""
    @AppStorage("store_address") private var storeAddress = ""
    @AppStorage("store_tax_id") private var storeTaxId = ""
    @AppStorage("store_email") private var storeEmail = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("store_logo_path") private var storeLogoPath = ""
    @AppStorage("api_keys_json") private var apiKeysJson = "[]"

    @Query(sort: \AuditLog.createdAt, order: .reverse) private var auditLogs: [AuditLog]

    @State private var selectedSection: OrgSection = .profile
    @State private var showSubscriptionSettings = false

    @State private var billingPlan = "—"
    @State private var subscriptionStatusText = "ACTIVE"
    @State private var subscriptionDetailText = ""
    @State private var subscriptionFeaturesText = ""
    @State private var subscriptionIsActive = true
    @State private var currentTierId = ""

    @State private var apiKeysCopied: String? = nil

    @State private var isExporting = false
    @State private var isWiping = false
    @State private var isPullingAudit = false
    @State private var exportMessage: String? = nil
    @State private var showingExportShare = false
    @State private var exportShareURL: URL?
    @State private var showingImportInfo = false
    @State private var showingBackupInfo = false
    @State private var showingWipeConfirm = false
    @State private var showingWipePinAlert = false
    @State private var wipePin = ""
    @State private var showingWipePinError = false

    @State private var selectedLogoItems: [PhotosPickerItem] = []
    @State private var logoImage: UIImage? = nil
    @State private var isSavingProfile = false
    @State private var profileSaveMessage: String? = nil
    @State private var isPullingProfile = false

    /// Enterprise teal–slate accent shared with Employee workspace.
    private let orgAccent = Color(hex: "0F766E")
    private let orgAccentDeep = Color(hex: "334155")

    @State private var bannerPhase: CGFloat = 0
    @State private var bannerShine: CGFloat = -0.35

    enum OrgSection: String, CaseIterable, Identifiable {
        case profile
        case subscription
        case billing
        case apiKeys
        case auditLog
        case dataExport

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .profile: return "org_nav_profile"
            case .subscription: return "org_nav_subscription"
            case .billing: return "org_nav_billing"
            case .apiKeys: return "org_nav_api_keys"
            case .auditLog: return "org_nav_audit"
            case .dataExport: return "org_nav_data"
            }
        }

        var subtitleKey: String {
            switch self {
            case .profile: return "org_profile_subtitle"
            case .subscription: return "org_subscription_subtitle"
            case .billing: return "org_billing_subtitle"
            case .apiKeys: return "org_api_keys_subtitle"
            case .auditLog: return "org_audit_log_subtitle"
            case .dataExport: return "org_data_export_subtitle"
            }
        }

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

    private enum ManagePlanLock {
        case none
        case offlinePlan
        case offlineSyncMode
    }

    private var managePlanLock: ManagePlanLock {
        if OfflineSyncModeController.isOfflineSubscriptionPlan {
            return .offlinePlan
        }
        if offlineSyncMode {
            return .offlineSyncMode
        }
        return .none
    }

    private var displayStoreName: String {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "org_untitled".t : trimmed
    }

    private var planBadgeLabel: String {
        OfflineSyncModeController.isOfflineSubscriptionPlan
            ? "org_badge_offline_plan".t
            : "org_badge_online_cloud".t
    }

    private var storedAPIKeys: [[String: String]] {
        (try? JSONDecoder().decode(
            [[String: String]].self,
            from: apiKeysJson.data(using: .utf8) ?? Data()
        )) ?? []
    }

    /// Real subscription-payment events (from local + pulled audit_logs).
    private var billingEvents: [AuditLog] {
        auditLogs.filter { log in
            let type = log.actionType.lowercased()
            return type.contains("subscription_payment")
                || type.contains("payment_capture")
                || type == "billing_payment"
                || type.hasPrefix("paypal_")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sectionNav
                .frame(width: 240)

            Divider().background(Color.appDivider)

            sectionContent
                .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fullScreenCover(isPresented: $showSubscriptionSettings, onDismiss: {
            refreshBillingPlan()
        }) {
            NavigationStack {
                SubscriptionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showSubscriptionSettings = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingExportShare) {
            if let exportShareURL {
                ShareSheet(activityItems: [exportShareURL])
            }
        }
        .onAppear {
            refreshBillingPlan()
            loadStoredLogo()
            startBannerAnimation()
            Task { await refreshProfileFromServer() }
        }
        .onChange(of: selectedLogoItems) { _, newItems in
            handleLogoSelection(newItems)
        }
        .onChange(of: lm.currentLanguage) { _, _ in
            refreshBillingPlan()
        }
        .onChange(of: selectedSection) { _, section in
            if section == .auditLog || section == .billing {
                Task { await refreshAuditFromServer() }
            }
        }
    }

    // MARK: - Section Nav

    private var sectionNav: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                orgAvatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayStoreName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(planBadgeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(orgAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(orgAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, 0)
            .padding(.bottom, 10)

            Divider().background(Color.appDivider)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(OrgSection.allCases) { section in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedSection = section
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(selectedSection == section ? .white : .textSecondary)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selectedSection == section ? orgAccent : Color.appSurfaceHigh)
                                    )
                                Text(section.titleKey.t)
                                    .font(.system(size: 12, weight: selectedSection == section ? .semibold : .medium))
                                    .foregroundColor(selectedSection == section ? .textPrimary : .textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedSection == section ? orgAccent.opacity(0.10) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                    }
                }
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, APSpacing.sm)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(offlineSyncMode ? Color.orange : orgAccent)
                        .frame(width: 6, height: 6)
                    Text(offlineSyncMode ? "org_status_offline_mode".t : "org_status_online_mode".t)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                if !activeMerchantId.isEmpty {
                    Text(String(activeMerchantId.prefix(8)).uppercased())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 12)
        }
        .background(Color.appSurface)
    }

    @ViewBuilder
    private var orgAvatar: some View {
        if let logoImage {
            Image(uiImage: logoImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [orgAccent, orgAccentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.md) {
                enterpriseBanner

                pageHeader(
                    title: selectedSection.titleKey.t,
                    subtitle: selectedSection.subtitleKey.t
                )

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
            .padding(.horizontal, APSpacing.md)
            .padding(.top, 0)
            .padding(.bottom, APSpacing.md)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    /// Animated enterprise banner — signals organization-level importance.
    private var enterpriseBanner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "0F766E"),
                            Color(hex: "115E59"),
                            Color(hex: "334155")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Soft moving orbs
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 140, height: 140)
                .blur(radius: 2)
                .offset(x: 40 + bannerPhase * 28, y: -36 + bannerPhase * 10)

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 100, height: 100)
                .offset(x: 280 - bannerPhase * 36, y: 40)

            // Sweeping shine
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.14),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: 0.45, anchor: .leading)
                .offset(x: bannerShine * 520)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(0.96 + bannerPhase * 0.06)
                        .opacity(0.88 + bannerPhase * 0.12)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("org_banner_eyebrow".t)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("org_banner_title".t)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("org_banner_subtitle".t)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayStoreName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(planBadgeLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(orgAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.92), in: Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: orgAccent.opacity(0.28), radius: 14, x: 0, y: 6)
    }

    private func startBannerAnimation() {
        withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
            bannerPhase = 1
        }
        withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
            bannerShine = 1.15
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [orgAccent, orgAccentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: selectedSection.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack(spacing: APSpacing.md) {
                if let logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                .stroke(Color.appDivider, lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(Color.appSurfaceHigh)
                            .frame(width: 88, height: 88)
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundColor(.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("org_logo_title".t)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("org_logo_desc".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        PhotosPicker(
                            selection: $selectedLogoItems,
                            maxSelectionCount: 1,
                            matching: .images
                        ) {
                            Text("org_logo_choose".t)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(orgAccent)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        if logoImage != nil {
                            Button(action: removeLogo) {
                                Text("org_logo_remove".t)
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.appRose.opacity(0.12))
                                    .foregroundColor(.appRose)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )

            VStack(spacing: 10) {
                formField(label: "org_field_name".t, placeholder: "org_field_name_ph".t, text: $storeName, icon: "building.2")
                formField(label: "org_field_tax_id".t, placeholder: "org_field_tax_id_ph".t, text: $storeTaxId, icon: "doc.text")
                formField(label: "org_field_address".t, placeholder: "org_field_address_ph".t, text: $storeAddress, icon: "mappin")
                formField(label: "org_field_phone".t, placeholder: "org_field_phone_ph".t, text: $storePhone, icon: "phone")
                formField(label: "org_field_email".t, placeholder: "org_field_email_ph".t, text: $storeEmail, icon: "envelope")
                formField(label: "org_field_website".t, placeholder: "org_field_website_ph".t, text: $storeWebsite, icon: "globe")
            }

            HStack(alignment: .center, spacing: 12) {
                if isPullingProfile {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("org_profile_syncing".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else if let profileSaveMessage {
                    Text(profileSaveMessage)
                        .font(.caption)
                        .foregroundColor(profileSaveMessage.hasPrefix("✓") ? .appTeal : .appRose)
                }
                Spacer()
                Button(action: saveProfile) {
                    if isSavingProfile {
                        ProgressView().tint(.white)
                    } else {
                        Label("org_save_profile".t, systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(orgAccent)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .disabled(isSavingProfile)
            }

            if !StoreSetupChecklist.incompleteItems(modelContext: modelContext).isEmpty {
                Button {
                    let mid = MerchantAuthManager.shared.merchantId
                        ?? activeMerchantId
                    StoreSetupChecklist.reopen(for: mid)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(.system(size: 14, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("org_reopen_setup_checklist_title".t)
                                .font(.system(size: 13, weight: .bold))
                            Text("org_reopen_setup_checklist_sub".t)
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                    .foregroundColor(.textPrimary)
                    .padding(APSpacing.md)
                    .background(Color(hex: "2D71F8").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                            .stroke(Color(hex: "2D71F8").opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack(alignment: .top, spacing: APSpacing.md) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(billingPlan)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(subscriptionStatusText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(subscriptionIsActive ? .appTeal : .orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((subscriptionIsActive ? Color.appTeal : Color.orange).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !subscriptionFeaturesText.isEmpty {
                        Text(subscriptionFeaturesText)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }

                    if !subscriptionDetailText.isEmpty {
                        Text(subscriptionDetailText)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer(minLength: 8)

                managePlanButton
            }
            .padding(APSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .stroke(orgAccent.opacity(0.22), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var managePlanButton: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button("org_manage_plan".t) {
                guard managePlanLock == .none else { return }
                showSubscriptionSettings = true
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(managePlanLock == .none ? orgAccent : Color.appSurfaceHigh)
            .foregroundColor(managePlanLock == .none ? .white : .textSecondary)
            .clipShape(Capsule())
            .disabled(managePlanLock != .none)
            .buttonStyle(.plain)

            if managePlanLock == .offlinePlan {
                Text("org_manage_locked_offline_plan".t)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160, alignment: .trailing)
            } else if managePlanLock == .offlineSyncMode {
                Text("org_manage_locked_offline_mode".t)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
        }
    }

    // MARK: - Billing

    private var billingSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [orgAccent, orgAccentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("org_current_plan".t)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    Text(billingPlan)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    if !subscriptionDetailText.isEmpty {
                        Text(subscriptionDetailText)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                managePlanButton
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("org_billing_history".t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(orgAccent)
                        .tracking(0.6)
                    Spacer()
                    if isPullingAudit {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                Text("org_billing_events_note".t)
                    .font(.caption2)
                    .foregroundColor(.textTertiary)

                if billingEvents.isEmpty {
                    honestEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "org_billing_empty_title".t,
                        message: "org_billing_empty_msg".t
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(billingEvents.prefix(30))) { event in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.appTeal)
                                    .frame(width: 28, height: 28)
                                    .background(Color.appTeal.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.details ?? event.actionType)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Text("org_billing_paid".t)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.appTeal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.appTeal.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 12)
                            if event.id != billingEvents.prefix(30).last?.id {
                                Divider().background(Color.appDivider)
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            honestBanner(
                icon: "exclamationmark.triangle.fill",
                text: "org_api_not_connected_banner".t,
                tint: .orange
            )

            HStack {
                Text("org_api_preview_label".t)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("org_api_coming_soon".t)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
            }

            if storedAPIKeys.isEmpty {
                honestEmptyState(
                    icon: "key.slash",
                    title: "org_no_api_keys".t,
                    message: "org_api_keys_empty_msg".t
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(storedAPIKeys.enumerated()), id: \.offset) { _, key in
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .foregroundColor(orgAccent)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .background(orgAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(key["name"] ?? "org_api_key_default_name".t)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("org_api_preview_badge".t)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                Text(maskKey(key["value"] ?? ""))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.textTertiary)
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
                        .padding(12)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Audit Log

    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Text("org_audit_source_note".t)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                Spacer()
                Button {
                    Task { await refreshAuditFromServer() }
                } label: {
                    if isPullingAudit {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Label("org_audit_refresh".t, systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
                .disabled(isPullingAudit || offlineSyncMode)
                .buttonStyle(.plain)
                .foregroundColor(orgAccent)
            }

            if auditLogs.isEmpty {
                honestEmptyState(
                    icon: "list.bullet.clipboard",
                    title: "org_audit_empty_title".t,
                    message: "org_audit_empty_msg".t
                )
            } else {
                Text(LocalizationManager.shared.t("org_audit_showing_fmt", min(auditLogs.count, 50), auditLogs.count))
                    .font(.caption)
                    .foregroundColor(.textTertiary)

                VStack(spacing: 0) {
                    let recentLogs = Array(auditLogs.prefix(50))
                    ForEach(recentLogs) { log in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(orgAccent.opacity(0.12))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Image(systemName: "list.bullet.clipboard.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(orgAccent)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(log.details ?? log.actionType)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    Text(log.actionType)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                    Text("·")
                                        .foregroundColor(.textTertiary)
                                    Text(log.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        if log.id != recentLogs.last?.id {
                            Divider().background(Color.appDivider)
                        }
                    }
                }
                .padding(.horizontal, APSpacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Data Export

    private var dataExportSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            honestBanner(
                icon: "info.circle.fill",
                text: "org_data_honesty_banner".t,
                tint: orgAccent
            )

            exportRow(
                icon: "square.and.arrow.up.fill",
                title: "org_export_full".t,
                subtitle: "org_export_full_desc".t,
                color: orgAccent,
                badge: nil,
                isLoading: isExporting
            ) {
                Task { await exportLocalStoreData() }
            }

            exportRow(
                icon: "doc.text.fill",
                title: "org_export_metadata".t,
                subtitle: "org_export_metadata_desc".t,
                color: .textSecondary,
                badge: "org_badge_limited".t,
                isLoading: false
            ) {
                Task { await exportMetadataStub() }
            }

            exportRow(
                icon: "trash.fill",
                title: "org_wipe_transactions".t,
                subtitle: "org_wipe_transactions_desc".t,
                color: .appRose,
                badge: nil,
                isLoading: isWiping
            ) {
                showingWipeConfirm = true
            }

            exportRow(
                icon: "clock.arrow.circlepath",
                title: "org_backup_history".t,
                subtitle: "org_backup_history_coming_soon".t,
                color: .appTeal,
                badge: "org_api_coming_soon".t,
                isLoading: false
            ) {
                showingBackupInfo = true
            }

            exportRow(
                icon: "arrow.up.doc.fill",
                title: "org_import_data".t,
                subtitle: "org_import_coming_soon".t,
                color: .appAmber,
                badge: "org_api_coming_soon".t,
                isLoading: false
            ) {
                showingImportInfo = true
            }

            if let msg = exportMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
            }
        }
        .alert("org_backup_history".t, isPresented: $showingBackupInfo) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text("org_backup_history_coming_soon".t)
        }
        .alert("org_import_data".t, isPresented: $showingImportInfo) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text("org_import_coming_soon".t)
        }
        .alert("org_wipe_confirm_title".t, isPresented: $showingWipeConfirm) {
            Button("cancel_btn".t, role: .cancel) {}
            Button("org_wipe_confirm_btn".t, role: .destructive) {
                wipePin = ""
                showingWipePinAlert = true
            }
        } message: {
            Text("org_wipe_confirm_msg".t)
        }
        .alert("org_wipe_pin_title".t, isPresented: $showingWipePinAlert) {
            SecureField("org_wipe_pin_placeholder".t, text: $wipePin)
                .keyboardType(.numberPad)
            Button("cancel_btn".t, role: .cancel) { wipePin = "" }
            Button("org_wipe_confirm_btn".t, role: .destructive) {
                verifyPinAndWipe()
            }
        } message: {
            Text("org_wipe_pin_msg".t)
        }
        .alert("org_wipe_pin_error_title".t, isPresented: $showingWipePinError) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text("org_wipe_pin_error_msg".t)
        }
    }

    // MARK: - Shared UI pieces

    private func honestBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint == .appAccent ? orgAccent : tint)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background((tint == .appAccent ? orgAccent : tint).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func honestEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.textTertiary)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func exportRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        badge: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appSurfaceHigh)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(14)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formField(label: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(orgAccent)
                .frame(width: 28, height: 28)
                .background(orgAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                TextField(placeholder, text: text)
                    .font(.system(size: 13))
                    .foregroundColor(.textPrimary)
                    .textFieldStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func refreshProfileFromServer() async {
        await MainActor.run { isPullingProfile = true }
        await SyncEngine.shared.pullMerchantSettings(
            modelContext: modelContext,
            allowOfflinePlanRecovery: true
        )
        await restoreLogoFromServerIfNeeded()
        await SyncEngine.shared.pullAuditLogs(modelContext)
        await MainActor.run {
            isPullingProfile = false
            loadStoredLogo()
            refreshBillingPlan()
        }
    }

    private func refreshAuditFromServer() async {
        guard !offlineSyncMode else { return }
        await MainActor.run { isPullingAudit = true }
        await SyncEngine.shared.syncAuditLogs(modelContext)
        await SyncEngine.shared.pullAuditLogs(modelContext)
        await MainActor.run {
            isPullingAudit = false
            refreshBillingPlan()
        }
    }

    private func verifyPinAndWipe() {
        let pin = wipePin.trimmingCharacters(in: .whitespacesAndNewlines)
        wipePin = ""
        guard KeychainManager.shared.verifyOwnerPin(pin) else {
            showingWipePinError = true
            return
        }
        performTransactionsWipe()
    }

    private func performTransactionsWipe() {
        isWiping = true
        exportMessage = nil
        Task {
            do {
                if !offlineSyncMode, await NetworkManager.shared.isConnected() {
                    _ = try await NetworkManager.shared.wipeRemoteTransactionsAndSessions()
                }
                await MainActor.run {
                    wipeLocalTransactionsAndSessions()
                    modelContext.insert(AuditLog(
                        actionType: "org_wipe_transactions",
                        details: "Wiped sessions/orders/payments from Organization (merchant: \(activeMerchantId))"
                    ))
                    modelContext.saveWithLogging(label: #function)
                    isWiping = false
                    exportMessage = "org_wipe_success".t
                }
                await SyncEngine.shared.syncAuditLogs(modelContext)
            } catch {
                await MainActor.run {
                    isWiping = false
                    exportMessage = "org_wipe_failed".t + ": \(error.localizedDescription)"
                }
            }
        }
    }

    private func wipeLocalTransactionsAndSessions() {
        if let sessions = try? modelContext.fetch(FetchDescriptor<TableSession>()) {
            for session in sessions { modelContext.delete(session) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for order in orders { modelContext.delete(order) }
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<Payment>()) {
            for payment in payments { modelContext.delete(payment) }
        }
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for table in tables {
                table.status = "vacant"
                table.isSynced = false
                table.updatedAt = Date()
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    /// Export real local SwiftData tables (orders, payments, menu, staff, customers, audits).
    private func exportLocalStoreData() async {
        await MainActor.run { isExporting = true }

        let iso = ISO8601DateFormatter()
        do {
            let orders = (try? modelContext.fetch(FetchDescriptor<Order>())) ?? []
            let payments = (try? modelContext.fetch(FetchDescriptor<Payment>())) ?? []
            let menuItems = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []
            let employees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
            let customers = (try? modelContext.fetch(FetchDescriptor<Customer>())) ?? []
            let logs = (try? modelContext.fetch(FetchDescriptor<AuditLog>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            ))) ?? []

            let payload: [String: Any] = [
                "exported_at": iso.string(from: Date()),
                "merchant_id": activeMerchantId,
                "store_name": storeName,
                "subscription_tier": currentTierId,
                "export_scope": "local_swiftdata",
                "counts": [
                    "orders": orders.count,
                    "payments": payments.count,
                    "menu_items": menuItems.count,
                    "employees": employees.count,
                    "customers": customers.count,
                    "audit_logs": logs.count
                ],
                "orders": orders.prefix(2000).map { order -> [String: Any] in
                    [
                        "id": order.id.uuidString,
                        "order_number": order.orderNumber,
                        "status": order.status,
                        "order_type": order.orderType,
                        "subtotal": order.subtotal,
                        "tax": order.tax,
                        "total": order.total,
                        "created_at": iso.string(from: order.createdAt)
                    ]
                },
                "payments": payments.prefix(2000).map { payment -> [String: Any] in
                    var row: [String: Any] = [
                        "id": payment.id.uuidString,
                        "method": payment.paymentMethod,
                        "amount": payment.amount,
                        "status": payment.status,
                        "paid_at": iso.string(from: payment.paidAt)
                    ]
                    if let orderId = payment.order?.id.uuidString { row["order_id"] = orderId }
                    return row
                },
                "menu_items": menuItems.prefix(2000).map { item -> [String: Any] in
                    var row: [String: Any] = [
                        "id": item.id,
                        "name": item.name,
                        "price": item.price,
                        "is_available": item.isAvailable
                    ]
                    if let sku = item.sku { row["sku"] = sku }
                    if let barcode = item.barcode { row["barcode"] = barcode }
                    return row
                },
                "employees": employees.prefix(500).map { emp -> [String: Any] in
                    var row: [String: Any] = [
                        "id": emp.id.uuidString,
                        "first_name": emp.firstName,
                        "last_name": emp.lastName,
                        "employment_type": emp.employmentType
                    ]
                    if let email = emp.email { row["email"] = email }
                    if let phone = emp.phone { row["phone"] = phone }
                    return row
                },
                "customers": customers.prefix(2000).map { customer -> [String: Any] in
                    var row: [String: Any] = [
                        "id": customer.id.uuidString,
                        "name": customer.name,
                        "loyalty_points": customer.loyaltyPoints
                    ]
                    if let email = customer.email { row["email"] = email }
                    if let phone = customer.phone { row["phone"] = phone }
                    return row
                },
                "audit_logs": logs.prefix(500).map { log -> [String: Any] in
                    var row: [String: Any] = [
                        "id": log.id.uuidString,
                        "action_type": log.actionType,
                        "created_at": iso.string(from: log.createdAt)
                    ]
                    if let details = log.details { row["details"] = details }
                    return row
                }
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("alphapos_store_export_\(Int(Date().timeIntervalSince1970)).json")
            try jsonData.write(to: tmpURL)

            await MainActor.run {
                isExporting = false
                exportShareURL = tmpURL
                showingExportShare = true
                exportMessage = LocalizationManager.shared.t(
                    "org_export_full_success_fmt",
                    orders.count,
                    payments.count,
                    menuItems.count
                )
                modelContext.insert(AuditLog(
                    actionType: "org_export_local_data",
                    details: "Exported local store JSON (\(orders.count) orders, \(payments.count) payments)"
                ))
                modelContext.saveWithLogging(label: #function)
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportMessage = "org_export_failed_msg".t + ": \(error.localizedDescription)"
            }
        }
    }

    private func saveProfile() {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = storeEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, email.contains("@"), email.contains(".") else {
            profileSaveMessage = "org_profile_validation_error".t
            return
        }

        storeName = name
        storeEmail = email
        isSavingProfile = true
        profileSaveMessage = nil
        Task {
            let saved = await SyncEngine.shared.syncMerchant()
            await MainActor.run {
                isSavingProfile = false
                profileSaveMessage = saved ? "org_profile_saved_remote".t : "org_profile_saved_local".t
                if saved {
                    modelContext.insert(AuditLog(
                        actionType: "UPDATE_ORGANIZATION_PROFILE",
                        details: "Updated organization profile: \(name)"
                    ))
                    modelContext.saveWithLogging(label: #function)
                    Task { await SyncEngine.shared.syncAuditLogs(modelContext) }
                }
            }
        }
    }

    private func refreshBillingPlan() {
        let tier = MerchantAuthManager.shared.subscriptionTier
            ?? (OfflineSyncModeController.isOfflineSubscriptionPlan
                ? "offline_perpetual"
                : (offlineSyncMode ? "offline_perpetual" : "unknown"))
        currentTierId = tier

        billingPlan = switch tier {
        case "offline_perpetual": "settings_tier_perpetual".t
        case "offline_subscription": "settings_tier_subscription".t
        case "online_subscription": "settings_tier_cloud".t
        default: tier == "unknown" ? "—" : tier
        }

        let status = (MerchantAuthManager.shared.subscriptionStatus ?? "active").lowercased()
        let expiry = MerchantAuthManager.shared.subscriptionExpiry
        let isExpired = expiry.map { Date(timeIntervalSince1970: $0) < Date() } ?? false
        subscriptionIsActive = (status == "active") && !isExpired
        subscriptionStatusText = (isExpired ? "org_status_expired".t : status.uppercased())

        subscriptionFeaturesText = switch tier {
        case "offline_perpetual": "org_plan_features_offline_perpetual".t
        case "offline_subscription": "org_plan_features_offline_sub".t
        case "online_subscription": "org_plan_features_online".t
        default: "org_plan_features".t
        }

        if tier == "offline_perpetual" {
            subscriptionDetailText = "org_plan_perpetual_detail".t
        } else if let expiry {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.locale = Locale(identifier: LocalizationManager.shared.currentLanguage.rawValue)
            subscriptionDetailText = LocalizationManager.shared.t(
                "org_next_billing_fmt",
                df.string(from: Date(timeIntervalSince1970: expiry))
            )
        } else {
            subscriptionDetailText = ""
        }
    }

    // MARK: - Logo Operations

    private func loadStoredLogo() {
        guard !storeLogoPath.isEmpty else { return }
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: storeLogoPath)

        if fileManager.fileExists(atPath: url.path) {
            logoImage = UIImage(contentsOfFile: url.path)
        } else {
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

    private func restoreLogoFromServerIfNeeded() async {
        if !storeLogoPath.isEmpty,
           FileManager.default.fileExists(atPath: storeLogoPath),
           UIImage(contentsOfFile: storeLogoPath) != nil {
            return
        }

        guard let remote = UserDefaults.standard.string(forKey: "store_logo_url"),
              let remoteURL = URL(string: remote),
              remoteURL.scheme == "https" else { return }

        do {
            let (data, response) = try await AppNetworkTransport.data(from: remoteURL, purpose: .remoteMedia)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 10 * 1_024 * 1_024,
                  let image = UIImage(data: data),
                  let png = image.pngData(),
                  let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }

            let localURL = documents.appendingPathComponent("store_logo.png")
            try png.write(to: localURL, options: .atomic)
            await MainActor.run {
                logoImage = image
                storeLogoPath = localURL.path
            }
        } catch {
            #if DEBUG
            print("Failed to restore store logo cache: \(error)")
            #endif
        }
    }

    private func handleLogoSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }

        Task {
            if let selectedData = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: selectedData),
               let data = image.pngData() {

                let fileManager = FileManager.default
                if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = docDir.appendingPathComponent("store_logo.png")
                    do {
                        try data.write(to: fileURL, options: .atomic)
                        await MainActor.run {
                            self.logoImage = image
                            self.storeLogoPath = fileURL.path

                            let newLog = AuditLog(
                                actionType: "UPDATE_STORE_LOGO",
                                details: "Updated store logo for receipts"
                            )
                            modelContext.insert(newLog)
                            modelContext.saveWithLogging(label: #function)
                        }

                        let connected = await NetworkManager.shared.isConnected()
                        if !offlineSyncMode && connected && !activeMerchantId.isEmpty {
                            do {
                                let publicURL = try await NetworkManager.shared.uploadStoreLogo(data, merchantId: activeMerchantId)
                                UserDefaults.standard.set(publicURL, forKey: "store_logo_url")
                                _ = await SyncEngine.shared.syncMerchant()
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
        UserDefaults.standard.removeObject(forKey: "store_logo_url")
        selectedLogoItems = []

        let newLog = AuditLog(
            actionType: "REMOVE_STORE_LOGO",
            details: "Removed store logo"
        )
        modelContext.insert(newLog)
        modelContext.saveWithLogging(label: #function)
        Task { _ = await SyncEngine.shared.syncMerchant() }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 10 else { return key }
        return String(key.prefix(10)) + "••••••••••••"
    }

    /// Metadata-only stub export with share sheet — clearly not a full store dump.
    private func exportMetadataStub() async {
        await MainActor.run { isExporting = true }
        do {
            let exportData: [String: Any] = [
                "exported_at": ISO8601DateFormatter().string(from: Date()),
                "merchant_id": activeMerchantId,
                "store_name": storeName,
                "subscription_tier": currentTierId,
                "export_scope": "metadata_only",
                "note": "This file contains organization metadata only. Full table export is not available in this version."
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("alphapos_org_metadata_\(Int(Date().timeIntervalSince1970)).json")
            try jsonData.write(to: tmpURL)

            await MainActor.run {
                isExporting = false
                exportShareURL = tmpURL
                showingExportShare = true
                exportMessage = "org_export_metadata_success".t
            }
        } catch {
            await MainActor.run {
                isExporting = false
                exportMessage = "org_export_failed_msg".t + ": \(error.localizedDescription)"
            }
        }
    }
}
