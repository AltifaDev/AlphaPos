//
//  PromotionsManagementView.swift
//  AlphaPos
//
//  Created by Antigravity on 2026-06-08.
//

import SwiftUI
import SwiftData
import PhotosUI
import AVKit
import AVFoundation
import CoreTransferable

private enum PromotionListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case scheduled = "Scheduled"
    case inactive = "Inactive"
    case expired = "Expired"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return "promo_filter_all".t
        case .active: return "promo_status_active".t
        case .scheduled: return "promo_status_scheduled".t
        case .inactive: return "promo_status_inactive".t
        case .expired: return "promo_status_expired".t
        }
    }
}

/// Quick-start draft passed into the create form from the empty / landing state.
struct PromotionFormDraft: Identifiable, Equatable {
    let id = UUID()
    var discountType: String
    var title: String
    var discountValue: Double
    var requiredQuantity: Int
    var rewardQuantity: Int
    var audience: String = "public"

    static func preset(_ kind: String) -> PromotionFormDraft {
        switch kind {
        case "staff":
            return PromotionFormDraft(discountType: "fixed_per_item", title: "ส่วนลดพนักงาน ฿10 ต่อรายการ", discountValue: 10, requiredQuantity: 1, rewardQuantity: 1, audience: "staff")
        case "percentage":
            return PromotionFormDraft(discountType: "percentage", title: "10% Off", discountValue: 10, requiredQuantity: 1, rewardQuantity: 1)
        case "fixed":
            return PromotionFormDraft(discountType: "fixed", title: "฿50 Off", discountValue: 50, requiredQuantity: 1, rewardQuantity: 1)
        case "bundle_price":
            return PromotionFormDraft(discountType: "bundle_price", title: "3 for 299", discountValue: 299, requiredQuantity: 3, rewardQuantity: 1)
        case "buy_x_get_y":
            return PromotionFormDraft(discountType: "buy_x_get_y", title: "Buy 1 Get 1", discountValue: 0, requiredQuantity: 1, rewardQuantity: 1)
        case "buy_x_pay_y":
            return PromotionFormDraft(discountType: "buy_x_pay_y", title: "Buy 3 Pay 2", discountValue: 0, requiredQuantity: 3, rewardQuantity: 2)
        default:
            return PromotionFormDraft(discountType: "none", title: "", discountValue: 0, requiredQuantity: 1, rewardQuantity: 1)
        }
    }
}

struct PromotionsManagementView: View {
    @AppStorage("offline_sync_mode") private var offlineMode = false
    private var isOffline: Bool { offlineMode || OfflineSyncModeController.isOfflineSubscriptionPlan }
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Promotion> { $0.isDeleted == false }, sort: \Promotion.updatedAt, order: .reverse) private var promotions: [Promotion]
    @Query(filter: #Predicate<OrderDiscount> { $0.isDeleted == false }) private var orderDiscounts: [OrderDiscount]

    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject private var lm: LocalizationManager

    @State private var formDraft: PromotionFormDraft? = nil
    @State private var promotionToEdit: Promotion? = nil
    // M-2: Coupon Code
    @State private var showingCouponSheet = false

    @State private var deletingPromotionIds = Set<UUID>()
    @State private var promotionPendingDelete: Promotion? = nil
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var selectedFilter: PromotionListFilter = .all

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                campaignOverview

                if promotions.isEmpty {
                    emptyStateView
                } else {
                    filterBar
                    promotionsGridView
                }
            }
        }
        .navigationTitle(L.Promos.title.t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                headerView
            }
        }
        .sheet(item: $formDraft) { draft in
            PromotionFormSheet(promotion: nil, draft: draft)
        }
        .sheet(item: $promotionToEdit) { promotion in
            PromotionFormSheet(promotion: promotion, draft: nil)
        }
        // M-2: Coupon Code sheet
        .sheet(isPresented: $showingCouponSheet) {
            CouponCodeSheet()
        }
        .onAppear {
            Task {
                guard !isOffline else { return }
                // Ensure menu catalog + promotions are on device before setup.
                await SyncEngine.shared.pullMenuItemsFromSupabase(modelContext)
                await SyncEngine.shared.pullPromotionsFromSupabase(modelContext)
                await SyncEngine.shared.syncPromotions(modelContext)
            }
        }
        .alert("promo_update_failed".t, isPresented: $showingErrorAlert) {
            Button("done".t, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert((L.Promos.deletePromoBtn.t + "?"), isPresented: Binding(
            get: { promotionPendingDelete != nil },
            set: { if !$0 { promotionPendingDelete = nil } }
        )) {
            Button("cancel_btn".t, role: .cancel) {
                promotionPendingDelete = nil
            }
            Button("delete_btn".t, role: .destructive) {
                if let promo = promotionPendingDelete {
                    deletePromotion(promo)
                }
                promotionPendingDelete = nil
            }
        } message: {
            Text("promo_delete_confirm_msg".t)
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            // M-2: Coupon Codes button
            Button(action: { showingCouponSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("coupon_codes_btn".t)
                        .font(.headline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.appSurfaceHigh)
                .foregroundColor(.appAccent)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appAccent.opacity(0.4), lineWidth: 1)
                )
            }

            Button(action: { formDraft = PromotionFormDraft.preset("none") }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(L.Promos.addPromotion.t)
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: "0F766E"), Color(hex: "14B8A6")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color(hex: "0F766E").opacity(0.35), radius: 10, x: 0, y: 4)
            }
        }
    }

    private var emptyStateView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                emptyHeroPanel
                standardsComplianceStrip
                quickStartSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var emptyHeroPanel: some View {
        ZStack(alignment: .bottomLeading) {
            // Atmospheric plane — suitable for product screenshots / website demos
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "0F766E"),
                            Color(hex: "115E59"),
                            Color(hex: "134E4A")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    GeometryReader { geo in
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: geo.size.width * 0.55)
                            .offset(x: geo.size.width * 0.55, y: -geo.size.height * 0.25)
                        Circle()
                            .fill(Color(hex: "5EEAD4").opacity(0.12))
                            .frame(width: geo.size.width * 0.4)
                            .offset(x: -geo.size.width * 0.1, y: geo.size.height * 0.55)
                    }
                    .clipped()
                )

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("promo_hub_badge".t)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(hex: "99F6E4"))
                        .tracking(1.2)
                        .textCase(.uppercase)

                    Text(L.Promos.noPromotionsTitle.t)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("promo_hub_hero_subtitle".t)
                        .font(.body)
                        .foregroundColor(Color.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)

                    HStack(spacing: 12) {
                        Button(action: { formDraft = PromotionFormDraft.preset("none") }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text(L.Promos.addPromotion.t)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .foregroundColor(Color(hex: "0F766E"))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(action: { showingCouponSheet = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "ticket")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("coupon_codes_btn".t)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 120, height: 120)
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(Color(hex: "5EEAD4"))
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "0F766E").opacity(0.25), radius: 20, x: 0, y: 10)
    }

    private var standardsComplianceStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("promo_standards_title".t)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                standardPill(
                    icon: "shippingbox.fill",
                    title: "promo_std_stock_title".t,
                    detail: "promo_std_stock_detail".t,
                    tint: Color(hex: "0F766E")
                )
                standardPill(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "promo_std_sales_title".t,
                    detail: "promo_std_sales_detail".t,
                    tint: Color(hex: "0369A1")
                )
                standardPill(
                    icon: "bolt.fill",
                    title: "promo_std_pos_title".t,
                    detail: "promo_std_pos_detail".t,
                    tint: Color(hex: "B45309")
                )
            }
        }
    }

    private func standardPill(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("promo_quick_start_title".t)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("promo_quick_start_hint".t)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                quickStartCard(
                    title: "ส่วนลดพนักงาน",
                    subtitle: "ลด ฿10 ต่อสินค้า 1 ชิ้น · เฉพาะ POS",
                    icon: "person.badge.shield.checkmark",
                    tint: Color(hex: "0F766E"),
                    kind: "staff"
                )
                if !isOffline {
                quickStartCard(
                    title: "promo_tpl_banner".t,
                    subtitle: "promo_tpl_banner_sub".t,
                    icon: "photo.on.rectangle.angled",
                    tint: Color(hex: "64748B"),
                    kind: "none"
                )
                }
                quickStartCard(
                    title: "promo_tpl_percent".t,
                    subtitle: "promo_tpl_percent_sub".t,
                    icon: "percent",
                    tint: Color(hex: "0F766E"),
                    kind: "percentage"
                )
                quickStartCard(
                    title: "promo_tpl_fixed".t,
                    subtitle: "promo_tpl_fixed_sub".t,
                    icon: "banknote",
                    tint: Color(hex: "0369A1"),
                    kind: "fixed"
                )
                quickStartCard(
                    title: "promo_tpl_bundle".t,
                    subtitle: "promo_tpl_bundle_sub".t,
                    icon: "cube.box.fill",
                    tint: Color(hex: "7C3AED"),
                    kind: "bundle_price"
                )
                quickStartCard(
                    title: "promo_tpl_bogo".t,
                    subtitle: "promo_tpl_bogo_sub".t,
                    icon: "gift.fill",
                    tint: Color(hex: "BE185D"),
                    kind: "buy_x_get_y"
                )
                quickStartCard(
                    title: "promo_tpl_payy".t,
                    subtitle: "promo_tpl_payy_sub".t,
                    icon: "tag.fill",
                    tint: Color(hex: "B45309"),
                    kind: "buy_x_pay_y"
                )
            }
        }
    }

    private func quickStartCard(title: String, subtitle: String, icon: String, tint: Color, kind: String) -> some View {
        Button(action: { formDraft = PromotionFormDraft.preset(kind) }) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Text("promo_quick_start_cta".t)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(tint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var promotionsGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if filteredPromotions.isEmpty {
                filteredEmptyState
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 24) {
                    ForEach(filteredPromotions) { promo in
                        promotionCard(for: promo)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundColor(.textTertiary)
            Text(LocalizationManager.shared.t("promo_filter_empty_title", selectedFilter.localizedTitle))
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text(L.Promos.noPromotionsSubtitle.t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var filteredPromotions: [Promotion] {
        promotions.filter { promo in
            switch selectedFilter {
            case .all:
                return true
            case .active:
                return promotionStatusText(promo) == "Active"
            case .scheduled:
                return promotionStatusText(promo) == "Scheduled"
            case .inactive:
                return promotionStatusText(promo) == "Inactive"
            case .expired:
                return promotionStatusText(promo) == "Expired"
            }
        }
    }

    private var campaignOverview: some View {
        let activeCount = promotions.filter { promotionStatusText($0) == "Active" }.count
        let scheduledCount = promotions.filter { promotionStatusText($0) == "Scheduled" }.count
        let expiredCount = promotions.filter { promotionStatusText($0) == "Expired" }.count
        let totalUses = orderDiscounts.count
        let totalDiscount = orderDiscounts.reduce(0.0) { $0 + $1.discountAmount }

        return HStack(spacing: 12) {
            overviewTile("promo_status_active".t, value: "\(activeCount)", icon: "bolt.fill", color: Color(hex: "0F766E"))
            overviewTile("promo_status_scheduled".t, value: "\(scheduledCount)", icon: "calendar.badge.clock", color: Color(hex: "B45309"))
            overviewTile("promo_kpi_history".t, value: "\(expiredCount)", icon: "clock.arrow.circlepath", color: .textSecondary)
            overviewTile("promo_kpi_used".t, value: "\(totalUses)", icon: "receipt", color: .appAccent)
            overviewTile("promo_kpi_discount".t, value: "฿\(totalDiscount.formatted(.number.precision(.fractionLength(0...0))))", icon: "chart.bar.fill", color: .appRose)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func overviewTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Promotion status", selection: $selectedFilter) {
                ForEach(PromotionListFilter.allCases) { filter in
                    Text(filter.localizedTitle).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Text(LocalizationManager.shared.t("promo_campaigns_count", filteredPromotions.count))
                .font(.caption)
                .foregroundColor(.textSecondary)
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func promotionCard(for promo: Promotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if !isOffline && promo.isPublicPromotion {
                    promotionMediaPreview(promo)
                }

                // Status Badge Overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(promotionStatusLocalized(promo))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(promotionStatusColor(promo))
                            .cornerRadius(8)
                            .shadow(radius: 4)
                    }
                    Spacer()
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(promo.audienceLabel).font(.caption).foregroundStyle(.secondary)
                if promo.pendingWebRemoval {
                    Text("รอลบโปรโมชั่นเดิมออกจากเว็บเมื่อเชื่อมต่อออนไลน์")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(promo.title)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text(promotionDiscountText(promo))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Label(promo.mediaType == "video" ? "Video" : "Image", systemImage: promo.mediaType == "video" ? "play.rectangle.fill" : "photo")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(6)
                }

                if let desc = promo.promoDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                } else {
                    Text(L.Promos.noDescription.t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    miniMetric("Orders", value: "\(promotionUsageCount(promo))")
                    miniMetric("Discount", value: "฿\(promotionTotalDiscount(promo).formatted(.number.precision(.fractionLength(0...0))))")
                    miniMetric("Avg", value: "฿\(promotionAverageDiscount(promo).formatted(.number.precision(.fractionLength(0...0))))")
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(promotionScheduleText(promo))
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Divider()
                    .background(Color.appDivider)
                    .padding(.vertical, 4)

                HStack {
                    // Sync Status Indicator
                    HStack(spacing: 4) {
                        Image(systemName: deletingPromotionIds.contains(promo.id) ? "hourglass" : (promo.isSynced ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"))
                            .font(.system(size: 10))
                            .foregroundColor(deletingPromotionIds.contains(promo.id) ? .orange : (promo.isSynced ? .appTeal : .orange))
                        Text(isOffline || !promo.isPublicPromotion ? "บันทึกในเครื่อง" : (deletingPromotionIds.contains(promo.id) ? "Deleting" : (promo.isSynced ? "Synced" : "Unsynced")))
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    // Action Buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            guard sessionManager.can(.promotionsManage) else { return }
                            withAnimation {
                                promo.isActive.toggle()
                                promo.isSynced = false
                                promo.updatedAt = Date()
                                modelContext.saveWithLogging(label: #function)

                                // Trigger sync in the background
                                Task {
                                    guard !isOffline else { return }
                                    await SyncEngine.shared.syncPromotions(modelContext)
                                }
                            }
                        }) {
                            Image(systemName: promo.isActive ? "eye.slash" : "eye")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }

                        Button(action: { promotionToEdit = promo }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16))
                                .foregroundColor(.textSecondary)
                        }

                        Button(action: {
                            promotionPendingDelete = promo
                        }) {
                            if deletingPromotionIds.contains(promo.id) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 16))
                                    .foregroundColor(.appRose)
                            }
                        }
                        .disabled(deletingPromotionIds.contains(promo.id))
                    }
                }
            }
            .padding(16)
            .background(Color.appSurface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private func miniMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func promotionMediaPreview(_ promo: Promotion) -> some View {
        if promo.mediaType == "video",
           let url = PromotionMediaCodec.playableURL(from: promo.imageData, fileExtension: "mp4") {
            LoopingVideoPlayer(url: url)
                .frame(height: 180)
                .clipped()
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Label("loops_label".t, systemImage: "repeat")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.45))
                                .cornerRadius(6)
                            Spacer()
                        }
                        .padding(10)
                    }
                )
        } else if let remote = PromotionMediaCodec.remoteURL(from: promo.imageData) {
            RemoteImageView(
                imageUrl: remote.absoluteString,
                imageData: nil,
                fallbackColor: .appSurfaceHigh,
                fallbackIcon: "photo"
            )
            .frame(height: 180)
            .clipped()
        } else if let data = PromotionMediaCodec.decodedData(from: promo.imageData),
                  let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()
        } else {
            LinearGradient(colors: [Color.appSurfaceHigh, Color.appSurface], startPoint: .top, endPoint: .bottom)
                .frame(height: 180)

            Image(systemName: promo.mediaType == "video" ? "video" : "photo")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)
        }
    }

    private func promotionStatusText(_ promo: Promotion) -> String {
        if !promo.isActive { return "Inactive" }
        let now = Date()
        if let startsAt = promo.startsAt, now < startsAt { return "Scheduled" }
        if let endsAt = promo.endsAt, now > endsAt { return "Expired" }
        return "Active"
    }

    private func promotionStatusLocalized(_ promo: Promotion) -> String {
        switch promotionStatusText(promo) {
        case "Active": return "promo_status_active".t
        case "Scheduled": return "promo_status_scheduled".t
        case "Expired": return "promo_status_expired".t
        default: return "promo_status_inactive".t
        }
    }

    private func promotionStatusColor(_ promo: Promotion) -> Color {
        switch promotionStatusText(promo) {
        case "Active": return Color(hex: "0F766E")
        case "Scheduled": return Color(hex: "B45309")
        case "Expired": return .gray
        default: return .gray
        }
    }

    private func promotionDiscountText(_ promo: Promotion) -> String {
        switch promo.discountType {
        case "percentage":
            return "Discount \(promo.discountValue.formatted(.number.precision(.fractionLength(0...2))))%"
        case "fixed":
            return "Discount ฿\(promo.discountValue.formatted(.number.precision(.fractionLength(0...2))))"
        case "fixed_per_item":
            return "Discount ฿\(promo.discountValue.formatted(.number.precision(.fractionLength(0...2)))) per item"
        case "bundle_price":
            return "Buy \(promo.requiredQuantity) for ฿\(promo.discountValue.formatted(.number.precision(.fractionLength(0...2))))"
        case "buy_x_get_y":
            return "Buy \(promo.requiredQuantity), get \(promo.rewardQuantity) free"
        case "buy_x_pay_y":
            return "Buy \(promo.requiredQuantity), pay \(promo.rewardQuantity)"
        default:
            return "Banner only"
        }
    }

    private func promotionUsageCount(_ promo: Promotion) -> Int {
        orderDiscounts.filter { $0.promotion?.id == promo.id }.count
    }

    private func promotionTotalDiscount(_ promo: Promotion) -> Double {
        orderDiscounts
            .filter { $0.promotion?.id == promo.id }
            .reduce(0.0) { $0 + $1.discountAmount }
    }

    private func promotionAverageDiscount(_ promo: Promotion) -> Double {
        let usageCount = promotionUsageCount(promo)
        guard usageCount > 0 else { return 0 }
        return promotionTotalDiscount(promo) / Double(usageCount)
    }

    private func promotionPerformanceText(_ promo: Promotion) -> String {
        let usageCount = promotionUsageCount(promo)
        let totalDiscount = promotionTotalDiscount(promo)
        guard usageCount > 0 else { return "No sales impact yet" }
        return "\(usageCount) orders • ฿\(totalDiscount.formatted(.number.precision(.fractionLength(0...2)))) discount"
    }

    private func promotionScheduleText(_ promo: Promotion) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = promo.startsAt.map { formatter.string(from: $0) } ?? "Now"
        let end = promo.endsAt.map { formatter.string(from: $0) } ?? "No end"
        let minimum = promo.minimumSpend > 0 ? "Minimum ฿\(promo.minimumSpend.formatted(.number.precision(.fractionLength(0...2)))) • " : ""
        return "\(minimum)\(start) - \(end)"
    }

    private func deletePromotion(_ promo: Promotion) {
        guard sessionManager.can(.promotionsManage) else { return }
        guard !deletingPromotionIds.contains(promo.id) else { return }
        if isOffline || !promo.isPublicPromotion {
            promo.isDeleted = true
            promo.isSynced = false
            promo.updatedAt = Date()
            modelContext.saveWithLogging(label: #function)
            if !isOffline {
                Task { await SyncEngine.shared.syncPromotions(modelContext) }
            }
            return
        }
        deletingPromotionIds.insert(promo.id)
        let id = promo.id
        Task {
            do {
                let deleted = try await NetworkManager.shared.deletePromotionOnServer(id: id)
                await MainActor.run {
                    deletingPromotionIds.remove(id)
                    if deleted {
                        withAnimation {
                            modelContext.delete(promo)
                        }
                        modelContext.saveWithLogging(label: #function)
                    } else {
                        errorMessage = "Could not delete this promotion on the database. Please check connection and permissions."
                        showingErrorAlert = true
                    }
                }
                if deleted {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                }
            } catch {
                await MainActor.run {
                    deletingPromotionIds.remove(id)
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
}

struct PromotionFormSheet: View {
    @AppStorage("offline_sync_mode") private var offlineMode = false
    @State private var audience = "public"
    private var isOffline: Bool { offlineMode || OfflineSyncModeController.isOfflineSubscriptionPlan }
    private var showsWebMedia: Bool { !isOffline && audience == "public" }
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MenuItem> { $0.isDeleted == false }, sort: \MenuItem.name) private var menuItems: [MenuItem]

    let promotion: Promotion?
    var draft: PromotionFormDraft? = nil

    @State private var title: String = ""
    @State private var promoDescription: String = ""
    @State private var mediaDataBase64: String? = nil
    @State private var mediaType: String = "image"
    @State private var isActive: Bool = true
    @State private var discountType: String = "none"
    @State private var discountValue: Double = 0.0
    @State private var minimumSpend: Double = 0.0
    @State private var appliesToMenuItemId: String = ""
    @State private var requiredQuantity: Int = 3
    @State private var rewardQuantity: Int = 1
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var startsAt = Date()
    @State private var endsAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    @State private var selectedMediaItem: PhotosPickerItem? = nil
    @State private var isProcessingMedia = false
    @State private var mediaErrorMessage: String? = nil
    @State private var limitToSpecificProduct = false
    @State private var showingProductPicker = false
    @State private var productSearch = ""
    @State private var syncFeedback: String? = nil
    @State private var isSaving = false

    var isNew: Bool { promotion == nil }

    private var availableMenuItems: [MenuItem] {
        menuItems.filter { $0.isAvailable || $0.id == appliesToMenuItemId }
    }

    private var filteredMenuItems: [MenuItem] {
        let q = productSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return availableMenuItems }
        return availableMenuItems.filter {
            $0.name.lowercased().contains(q)
                || ($0.sku?.lowercased().contains(q) ?? false)
                || ($0.barcode?.lowercased().contains(q) ?? false)
        }
    }

    private var selectedProduct: MenuItem? {
        availableMenuItems.first { $0.id == appliesToMenuItemId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L.Promos.detailsSection.t)) {
                    TextField(L.Promos.titleLabel.t, text: $title)
                        .foregroundColor(.textPrimary)

                    TextField(L.Promos.descriptionLabel.t, text: $promoDescription, axis: .vertical)
                        .lineLimit(3...5)
                        .foregroundColor(.textPrimary)

                    Toggle(L.Promos.statusActive.t, isOn: $isActive)
                        .tint(Color(hex: "10B981"))
                }

                Section("ช่องทางใช้งาน") {
                    Picker("ใช้โปรโมชั่นสำหรับ", selection: $audience) {
                        if !isOffline { Text("ลูกค้า · เผยแพร่บนเว็บ").tag("public") }
                        Text("ลูกค้า · เฉพาะ POS").tag("pos")
                        Text("พนักงาน · เฉพาะ POS").tag("staff")
                    }
                    Text(audience == "staff"
                         ? "กำหนดส่วนลดเป็นจำนวนเงิน เปอร์เซ็นต์ หรือต่อสินค้าแต่ละชิ้น แล้วเลือกใช้ที่ POS สำหรับบิลพนักงาน ระบบไม่เลือกให้อัตโนมัติและไม่ส่งข้อมูลส่วนลดนี้ไปเว็บ"
                         : (showsWebMedia ? "เผยแพร่โปรโมชั่นและแบนเนอร์ไปยังเว็บไซต์สั่งอาหาร" : "คำนวณส่วนลดในเครื่อง ไม่ต้องมีแบนเนอร์และไม่ส่งโปรโมชั่นนี้ไปเว็บ"))
                        .font(.caption).foregroundStyle(.secondary)
                    if promotion?.isPublicPromotion == true && (audience != "public" || isOffline) {
                        Text("หากเคยเผยแพร่แล้ว แบนเนอร์เดิมจะถูกนำออกเมื่อเชื่อมต่อและซิงก์สำเร็จ")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section(header: Text("promo_type_label".t)) {
                    if audience != "staff" { promotionPresetButtons }

                    Picker("promo_type_label".t, selection: $discountType) {
                        if audience != "staff" && showsWebMedia { Text(L.Promos.typeNone.t).tag("none") }
                        Text(L.Promos.typePercentage.t).tag("percentage")
                        Text(L.Promos.typeFixed.t).tag("fixed")
                        if audience == "staff" { Text("ส่วนลดคงที่ต่อสินค้า 1 ชิ้น").tag("fixed_per_item") }
                        if audience != "staff" {
                        Text(L.Promos.typeBundle.t).tag("bundle_price")
                        Text("promo_type_buy_x_get_y".t).tag("buy_x_get_y")
                        Text("promo_type_buy_x_pay_y".t).tag("buy_x_pay_y")
                        }
                    }

                    if discountType != "none" {
                        if discountType == "percentage" || discountType == "fixed" {
                            Picker("ขอบเขตส่วนลด", selection: $limitToSpecificProduct) {
                                Text("ทั้งออเดอร์ (Cart)").tag(false)
                                Text("สินค้าเฉพาะรายการ (Item)").tag(true)
                            }
                            .pickerStyle(.segmented)

                            Text(limitToSpecificProduct
                                 ? "มาตรฐานสากล: หักจากราคาสินค้าที่เลือกเท่านั้น"
                                 : "มาตรฐานสากล: หักจากยอดออเดอร์ทั้งใบ (มีขั้นต่ำได้)")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                        }

                        if requiresProductRule || limitToSpecificProduct {
                            productPickerButton

                            if requiresProductRule {
                                Stepper(requiredQuantityLabel, value: $requiredQuantity, in: 1...99)

                                if discountType == "buy_x_get_y" || discountType == "buy_x_pay_y" {
                                    Stepper(rewardQuantityLabel, value: $rewardQuantity, in: 1...99)
                                }
                            }
                        }

                        if showsDiscountValue {
                            HStack {
                                Text(discountValueLabel)
                                Spacer()
                                TextField("0", value: $discountValue, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            }
                            if let product = selectedProduct, discountType == "percentage" || discountType == "fixed" {
                                Text(itemDiscountPreview(for: product))
                                    .font(.caption)
                                    .foregroundColor(.appTeal)
                            }
                        }

                        if (discountType == "percentage" || discountType == "fixed") && !limitToSpecificProduct {
                            HStack {
                                Text("minimum_spend_lbl".t)
                                Spacer()
                                TextField("0", value: $minimumSpend, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            }
                        }

                        if discountType == "fixed_per_item" {
                            HStack {
                                Text("ราคาสินค้าขั้นต่ำต่อหน่วย (ต้องมากกว่า)")
                                Spacer()
                                TextField("50", value: $minimumSpend, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            }
                            Text("ระบบคูณส่วนลดตามจำนวนชิ้น และใช้เฉพาะสินค้าที่ราคาต่อหน่วยสูงกว่าเกณฑ์นี้")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }

                Section(header: Text("schedule_section".t)) {
                    Toggle("start_scheduled_toggle".t, isOn: $hasStartDate)
                        .tint(Color(hex: "10B981"))
                    if hasStartDate {
                        DatePicker("starts_field".t, selection: $startsAt)
                    }

                    Toggle("end_auto_toggle".t, isOn: $hasEndDate)
                        .tint(Color(hex: "10B981"))
                    if hasEndDate {
                        DatePicker("ends_field".t, selection: $endsAt)
                    }
                }

                if showsWebMedia {
                Section(header: Text("banner_media_section".t)) {
                    VStack(spacing: 12) {
                        mediaGuidancePanel

                        if let mediaErrorMessage {
                            Text(mediaErrorMessage)
                                .font(.caption)
                                .foregroundColor(.appRose)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isProcessingMedia {
                            ProgressView("processing_media_lbl".t)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if mediaType == "video",
                                  let url = PromotionMediaCodec.playableURL(from: mediaDataBase64, fileExtension: "mp4") {
                            LoopingVideoPlayer(url: url)
                                .frame(width: 432, height: 180)
                                .cornerRadius(8)
                                .padding(.vertical, 4)
                                .overlay(alignment: .bottomLeading) {
                                    Label("auto_loop_preview_label".t, systemImage: "repeat")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.45))
                                        .cornerRadius(6)
                                        .padding(10)
                                }
                        } else if let remote = PromotionMediaCodec.remoteURL(from: mediaDataBase64) {
                            RemoteImageView(
                                imageUrl: remote.absoluteString,
                                imageData: nil,
                                fallbackColor: .appSurfaceHigh,
                                fallbackIcon: "photo"
                            )
                            .frame(width: 432, height: 180)
                            .clipped()
                            .cornerRadius(8)
                            .padding(.vertical, 4)
                        } else if let data = PromotionMediaCodec.decodedData(from: mediaDataBase64),
                                  let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 432, height: 180)
                                .clipped()
                                .cornerRadius(8)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 40))
                                    .foregroundColor(.textTertiary)
                                Text("no_image_selected_lbl".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(8)
                        }

                        PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                Text(mediaDataBase64 == nil ? "select_media_btn".t : "change_media_btn".t)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                }
            }
            .navigationTitle(isNew ? L.Promos.addPromotion.t : L.Promos.editPromotion.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("save_btn".t) {
                            savePromotion()
                        }
                        .disabled(isSaveDisabled)
                        .foregroundColor(isSaveDisabled ? .textTertiary : Color(hex: "10B981"))
                    }
                }
            }
            .sheet(isPresented: $showingProductPicker) {
                productPickerSheet
            }
            .alert("ผลซิงก์โปรโมชั่น", isPresented: Binding(
                get: { syncFeedback != nil },
                set: { if !$0 { syncFeedback = nil } }
            )) {
                Button("done".t, role: .cancel) { syncFeedback = nil }
            } message: {
                Text(syncFeedback ?? "")
            }
            .onChange(of: selectedMediaItem) { _, newItem in
                Task {
                    guard let item = newItem else { return }
                    await MainActor.run {
                        isProcessingMedia = true
                        mediaErrorMessage = nil
                    }

                    do {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            let resized = cropBannerImage(image)
                            guard let jpeg = resized.jpegData(compressionQuality: 0.72) else {
                                throw PromoMediaError.unreadableImage
                            }
                            await MainActor.run {
                                self.mediaDataBase64 = jpeg.base64EncodedString()
                                self.mediaType = "image"
                                self.isProcessingMedia = false
                            }
                            return
                        }

                        // Compress to browser-safe H.264 MP4 (raw Photos Hevc/Mov often blacks out on web).
                        let compressed = try await PromotionMediaCodec.compressBannerVideo(from: item)
                        await MainActor.run {
                            self.mediaDataBase64 = compressed.base64EncodedString()
                            self.mediaType = "video"
                            self.isProcessingMedia = false
                        }
                    } catch let error as PromoMediaError {
                        await MainActor.run {
                            self.selectedMediaItem = nil
                            self.mediaErrorMessage = error.localizedDescription
                            self.isProcessingMedia = false
                        }
                    } catch {
                        await MainActor.run {
                            self.selectedMediaItem = nil
                            self.mediaErrorMessage = "ไม่สามารถประมวลผลไฟล์สื่อนี้ได้ กรุณาลองไฟล์อื่น"
                            self.isProcessingMedia = false
                        }
                    }
                }
            }
            .onAppear {
                if let promo = promotion {
                    audience = isOffline && promo.isPublicPromotion ? "pos" : promo.audience
                    title = promo.title
                    promoDescription = promo.promoDescription ?? ""
                    mediaDataBase64 = promo.imageData
                    mediaType = promo.mediaType
                    isActive = promo.isActive
                    discountType = promo.discountType
                    discountValue = promo.discountValue
                    minimumSpend = promo.minimumSpend
                    appliesToMenuItemId = promo.appliesToMenuItemId ?? ""
                    limitToSpecificProduct = !(promo.appliesToMenuItemId ?? "").isEmpty
                        && (promo.discountType == "percentage" || promo.discountType == "fixed")
                    requiredQuantity = max(1, promo.requiredQuantity)
                    rewardQuantity = max(1, promo.rewardQuantity)
                    if let start = promo.startsAt {
                        hasStartDate = true
                        startsAt = start
                    }
                    if let end = promo.endsAt {
                        hasEndDate = true
                        endsAt = end
                    }
                } else if let draft {
                    audience = draft.audience
                    title = draft.title
                    discountType = draft.discountType
                    discountValue = draft.discountValue
                    requiredQuantity = max(1, draft.requiredQuantity)
                    rewardQuantity = max(1, draft.rewardQuantity)
                    limitToSpecificProduct = draft.discountType == "bundle_price"
                        || draft.discountType == "buy_x_get_y"
                        || draft.discountType == "buy_x_pay_y"
                    if draft.discountType == "fixed_per_item" { minimumSpend = 50 }
                }
                if isOffline && audience == "public" { audience = "pos" }
                if !showsWebMedia && discountType == "none" { discountType = "percentage"; discountValue = 10 }
                // Refresh menu so product picker is not empty after catalog sync lag.
                Task {
                    guard !isOffline else { return }
                    await SyncEngine.shared.pullMenuItemsFromSupabase(modelContext)
                }
            }
            .onChange(of: isOffline) { _, value in
                if value && audience == "public" { audience = "pos" }
            }
            .onChange(of: audience) { _, value in
                if (value == "staff" && !["percentage", "fixed", "fixed_per_item"].contains(discountType)) || (value != "public" && discountType == "none") {
                    discountType = "percentage"
                    discountValue = 10
                }
            }
            .onChange(of: discountType) { _, newType in
                if newType == "bundle_price" || newType == "buy_x_get_y" || newType == "buy_x_pay_y" {
                    limitToSpecificProduct = true
                }
            }
        }
    }

    private var productPickerButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingProductPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("product_name_header".t)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        if let product = selectedProduct {
                            Text(product.name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text("ราคาปกติ ฿\(product.price.formatted(.number.precision(.fractionLength(0...2))))")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(availableMenuItems.isEmpty
                                  ? "ยังไม่มีเมนูในแคตตาล็อก — ไปเพิ่มที่ Inventory/Menu"
                                  : L.Promos.selectProduct.t)
                                .font(.body)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if availableMenuItems.isEmpty {
                Text("ต้องมี Menu Item ก่อน จึงจะตั้งโปรโมชั่นระดับสินค้าได้")
                    .font(.caption2)
                    .foregroundColor(.appRose)
            }
        }
    }

    private var productPickerSheet: some View {
        NavigationStack {
            Group {
                if availableMenuItems.isEmpty {
                    ContentUnavailableView(
                        "ไม่มีสินค้าในเมนู",
                        systemImage: "fork.knife.circle",
                        description: Text("สร้างหรือซิงก์เมนูจาก Inventory ก่อน ระบบต้องดึง Menu Item เพื่อใช้เป็นรายการโปรโมชั่น")
                    )
                } else {
                    List {
                        ForEach(filteredMenuItems, id: \.id) { item in
                            Button {
                                appliesToMenuItemId = item.id
                                showingProductPicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundColor(.textPrimary)
                                        if let sku = item.sku, !sku.isEmpty {
                                            Text("SKU \(sku)")
                                                .font(.caption2)
                                                .foregroundColor(.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Text("฿\(item.price.formatted(.number.precision(.fractionLength(0...2))))")
                                        .foregroundColor(.textSecondary)
                                    if item.id == appliesToMenuItemId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.appTeal)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $productSearch, prompt: "ค้นหาชื่อ / SKU / บาร์โค้ด")
                }
            }
            .navigationTitle("เลือกสินค้าโปรโมชั่น")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { showingProductPicker = false }
                }
            }
        }
    }

    private func itemDiscountPreview(for product: MenuItem) -> String {
        if discountType == "percentage" {
            let off = product.price * min(discountValue, 100) / 100
            let final = max(0, product.price - off)
            return "ตัวอย่าง: ฿\(product.price.formatted(.number.precision(.fractionLength(0...2)))) → ฿\(final.formatted(.number.precision(.fractionLength(0...2)))) (ลด ฿\(off.formatted(.number.precision(.fractionLength(0...2)))))"
        }
        let final = max(0, product.price - discountValue)
        return "ตัวอย่าง: ฿\(product.price.formatted(.number.precision(.fractionLength(0...2)))) → ฿\(final.formatted(.number.precision(.fractionLength(0...2))))"
    }

    private var invalidSchedule: Bool {
        hasStartDate && hasEndDate && startsAt >= endsAt
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        isProcessingMedia || invalidSchedule || invalidPromotionRule
    }

    private var invalidPromotionRule: Bool {
        if audience == "staff" && !["percentage", "fixed", "fixed_per_item"].contains(discountType) { return true }
        if !showsWebMedia && discountType == "none" { return true }
        let needsProduct = requiresProductRule || ((discountType == "percentage" || discountType == "fixed") && limitToSpecificProduct)
        if needsProduct && appliesToMenuItemId.isEmpty { return true }
        if ["percentage", "fixed", "fixed_per_item"].contains(discountType) && discountValue <= 0 { return true }
        if discountType == "bundle_price" && discountValue <= 0 { return true }
        if discountType == "buy_x_get_y" && rewardQuantity < 1 { return true }
        if discountType == "buy_x_pay_y" && (rewardQuantity < 1 || rewardQuantity >= requiredQuantity) { return true }
        return false
    }

    private var requiresProductRule: Bool {
        discountType == "bundle_price" || discountType == "buy_x_get_y" || discountType == "buy_x_pay_y"
    }

    private var showsDiscountValue: Bool {
        discountType == "percentage" || discountType == "fixed" || discountType == "fixed_per_item" || discountType == "bundle_price"
    }

    private var requiredQuantityLabel: String {
        switch discountType {
        case "buy_x_pay_y": return "Buy Quantity: \(requiredQuantity)"
        default: return LocalizationManager.shared.t("required_quantity_template", requiredQuantity)
        }
    }

    private var rewardQuantityLabel: String {
        switch discountType {
        case "buy_x_get_y": return "Free Quantity: \(rewardQuantity)"
        case "buy_x_pay_y": return "Pay Quantity: \(rewardQuantity)"
        default: return "Reward Quantity: \(rewardQuantity)"
        }
    }

    private var discountValueLabel: String {
        switch discountType {
        case "percentage": return "discount_val_pct_lbl".t
        case "fixed_per_item": return "ส่วนลดต่อสินค้า 1 ชิ้น"
        case "bundle_price": return "bundle_price_lbl".t
        default: return "discount_val_amt_lbl".t
        }
    }

    private func savePromotion() {
        guard sessionManager.can(.promotionsManage), !isSaveDisabled, !isSaving else { return }
        let needsProduct = requiresProductRule || ((discountType == "percentage" || discountType == "fixed") && limitToSpecificProduct)
        let linkedItemId: String? = needsProduct ? appliesToMenuItemId : nil
        let minSpend = discountType == "fixed_per_item"
            ? max(0, minimumSpend)
            : ((discountType == "percentage" || discountType == "fixed") && !limitToSpecificProduct
                ? max(0, minimumSpend)
                : 0)

        let savedPromotion: Promotion
        if let promo = promotion {
            promo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            promo.promoDescription = promoDescription
            promo.imageData = mediaDataBase64
            promo.mediaType = mediaType
            promo.isActive = isActive
            promo.discountType = discountType
            promo.discountValue = normalizedDiscountValue
            promo.minimumSpend = minSpend
            promo.appliesToMenuItemId = linkedItemId
            promo.requiredQuantity = requiresProductRule ? max(1, requiredQuantity) : 1
            promo.rewardQuantity = requiresProductRule ? normalizedRewardQuantity : 0
            promo.startsAt = hasStartDate ? startsAt : nil
            promo.endsAt = hasEndDate ? endsAt : nil
            promo.isSynced = false
            promo.updatedAt = Date()
            savedPromotion = promo
        } else {
            let newPromo = Promotion(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                promoDescription: promoDescription,
                imageData: mediaDataBase64,
                mediaType: mediaType,
                isActive: isActive,
                discountType: discountType,
                discountValue: normalizedDiscountValue,
                minimumSpend: minSpend,
                appliesToMenuItemId: linkedItemId,
                requiredQuantity: requiresProductRule ? max(1, requiredQuantity) : 1,
                rewardQuantity: requiresProductRule ? normalizedRewardQuantity : 0,
                startsAt: hasStartDate ? startsAt : nil,
                endsAt: hasEndDate ? endsAt : nil
            )
            modelContext.insert(newPromo)
            savedPromotion = newPromo
        }

        let effectiveAudience = isOffline && audience == "public" ? "pos" : audience
        if promotion != nil && savedPromotion.isPublicPromotion && effectiveAudience != "public" {
            savedPromotion.pendingWebRemoval = true
        }
        savedPromotion.audience = effectiveAudience
        if !savedPromotion.isPublicPromotion {
            savedPromotion.imageData = nil
            savedPromotion.mediaType = "image"
        } else {
            savedPromotion.pendingWebRemoval = false
        }
        do {
            try modelContext.save()
        } catch {
            syncFeedback = "บันทึกโปรโมชั่นไม่สำเร็จ: \(error.localizedDescription)"
            return
        }
        if isOffline || (!savedPromotion.isPublicPromotion && !savedPromotion.pendingWebRemoval) {
            dismiss()
            return
        }
        isSaving = true

        // Push to Supabase immediately so customer web can show the campaign.
        let context = modelContext
        Task {
            await SyncEngine.shared.syncPromotions(context)
            let synced = savedPromotion.isPublicPromotion ? savedPromotion.isSynced : !savedPromotion.pendingWebRemoval
            await MainActor.run {
                isSaving = false
                if synced {
                    dismiss()
                } else {
                    syncFeedback = savedPromotion.pendingWebRemoval
                        ? "บันทึกส่วนลดภายในเครื่องแล้ว แต่ยังนำโปรโมชั่นเดิมออกจากเว็บไม่สำเร็จ ระบบจะลองอีกครั้งเมื่อซิงก์ออนไลน์"
                        : "บันทึกในเครื่องแล้ว แต่ยังเผยแพร่บนเว็บไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วลองอีกครั้ง"
                }
            }
        }
    }

    private var normalizedDiscountValue: Double {
        if discountType == "percentage" {
            return min(100, max(0, discountValue))
        }
        if discountType == "fixed" || discountType == "fixed_per_item" {
            return max(0, discountValue)
        }
        if discountType == "bundle_price" {
            return max(0, discountValue)
        }
        return 0
    }

    private var normalizedRewardQuantity: Int {
        switch discountType {
        case "buy_x_get_y":
            return max(1, rewardQuantity)
        case "buy_x_pay_y":
            return min(max(1, rewardQuantity), max(1, requiredQuantity))
        default:
            return 0
        }
    }

    private var promotionPresetButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("quick_templates_title".t)
                .font(.caption)
                .foregroundColor(.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if showsWebMedia {
                presetButton("Banner", systemImage: "megaphone") {
                    discountType = "none"
                    discountValue = 0
                    minimumSpend = 0
                }
                }
                presetButton("10% Off", systemImage: "percent") {
                    discountType = "percentage"
                    discountValue = 10
                    minimumSpend = 0
                }
                presetButton("฿50 Off", systemImage: "banknote") {
                    discountType = "fixed"
                    discountValue = 50
                    minimumSpend = 0
                }
                presetButton("3 for 299", systemImage: "tag") {
                    discountType = "bundle_price"
                    requiredQuantity = 3
                    rewardQuantity = 0
                    discountValue = 299
                }
                presetButton("Buy 1 Get 1", systemImage: "gift") {
                    discountType = "buy_x_get_y"
                    requiredQuantity = 1
                    rewardQuantity = 1
                    discountValue = 0
                }
                presetButton("Buy 3 Pay 2", systemImage: "cart.badge.plus") {
                    discountType = "buy_x_pay_y"
                    requiredQuantity = 3
                    rewardQuantity = 2
                    discountValue = 0
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var mediaGuidancePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.appAccent)
                Text("media_display_standard".t)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("banner_image_standard_desc".t)
                Text("banner_video_standard_desc".t)
                Text("banner_safe_margin_desc".t)
            }
            .font(.caption)
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func presetButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func cropBannerImage(_ image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 1200, height: 500)
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let targetRatio = targetSize.width / targetSize.height
        let sourceRatio = sourceSize.width / sourceSize.height
        let cropSize: CGSize
        if sourceRatio > targetRatio {
            cropSize = CGSize(width: sourceSize.height * targetRatio, height: sourceSize.height)
        } else {
            cropSize = CGSize(width: sourceSize.width, height: sourceSize.width / targetRatio)
        }

        let cropOrigin = CGPoint(
            x: (sourceSize.width - cropSize.width) / 2,
            y: (sourceSize.height - cropSize.height) / 2
        )
        let drawRect = CGRect(
            x: -cropOrigin.x * targetSize.width / cropSize.width,
            y: -cropOrigin.y * targetSize.height / cropSize.height,
            width: sourceSize.width * targetSize.width / cropSize.width,
            height: sourceSize.height * targetSize.height / cropSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: drawRect)
        }
    }
}

// MARK: - Promotion banner media helpers

private enum PromoMediaError: LocalizedError {
    case unreadableImage
    case unreadableVideo
    case videoTooLong
    case videoTooLarge
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "อ่านไฟล์รูปภาพไม่สำเร็จ กรุณาเลือกรูปอื่น"
        case .unreadableVideo: return "อ่านไฟล์วิดีโอไม่สำเร็จ กรุณาเลือกคลิปอื่น"
        case .videoTooLong: return "วิดีโอบanner ต้องไม่เกิน 30 วินาที"
        case .videoTooLarge: return "วิดีโอหลังบีบอัดต้องไม่เกิน 15 MB"
        case .exportFailed: return "อุปกรณ์ไม่รองรับการแปลงวิดีโอนี้เป็น MP4 H.264"
        }
    }
}

private enum PromotionMediaCodec {
    static func remoteURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    static func decodedData(from value: String?) -> Data? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return nil }
        var base64 = raw
        if raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") {
            base64 = String(raw[raw.index(after: comma)...])
        }
        return Data(base64Encoded: base64)
    }

    static func playableURL(from value: String?, fileExtension: String) -> URL? {
        if let remote = remoteURL(from: value) { return remote }
        guard let data = decodedData(from: value) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alphapos-promo-\(value.hashValue)")
            .appendingPathExtension(fileExtension)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    static func compressBannerVideo(from item: PhotosPickerItem) async throws -> Data {
        guard let movie = try await item.loadTransferable(type: PromotionMovie.self) else {
            throw PromoMediaError.unreadableVideo
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }

        let asset = AVURLAsset(url: movie.url)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds <= 30.05 else {
            throw PromoMediaError.videoTooLong
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("promo-banner-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw PromoMediaError.exportFailed
        }
        try await exporter.export(to: outputURL, as: .mp4)
        let compressed = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        guard compressed.count <= 15 * 1_024 * 1_024 else {
            throw PromoMediaError.videoTooLarge
        }
        return compressed
    }
}

private struct PromotionMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("promo-selected-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return PromotionMovie(url: copyURL)
        }
    }
}

// MARK: - M-2: Coupon Code Sheet

struct CouponCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(
        filter: #Predicate<Promotion> { $0.isDeleted == false && $0.couponCode != nil },
        sort: \Promotion.updatedAt, order: .reverse
    ) private var couponPromotions: [Promotion]

    @State private var showingNewCouponForm = false
    @State private var copiedCode: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                if couponPromotions.isEmpty && !showingNewCouponForm {
                    emptyState
                } else if showingNewCouponForm {
                    NewCouponForm(onSave: { showingNewCouponForm = false })
                        .transition(.move(edge: .trailing))
                } else {
                    couponList
                }
            }
            .navigationTitle("coupon_codes_btn".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel_btn".t) { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { withAnimation { showingNewCouponForm = true } }) {
                        Image(systemName: "plus").fontWeight(.bold)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "ticket").font(.system(size: 50)).foregroundColor(.textTertiary)
            Text("coupon_codes_btn".t).font(.title3.bold()).foregroundColor(.textSecondary)
            Button(action: { showingNewCouponForm = true }) {
                Label("coupon_new_btn".t, systemImage: "plus")
                    .font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                    .background(APGradient.accent).foregroundColor(.white).cornerRadius(12)
            }
        }
    }

    private var couponList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(couponPromotions) { promo in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(promo.couponCode ?? "")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(.appAccent)
                            Text(promo.title).font(.caption).foregroundColor(.textSecondary)
                            HStack(spacing: 8) {
                                if let max = promo.couponMaxRedemptions {
                                    Text("\(promo.currentRedemptions)/\(max) " + "coupon_uses_lbl".t)
                                        .font(.caption2).foregroundColor(.textTertiary)
                                } else {
                                    Text("\(promo.currentRedemptions) " + "coupon_uses_lbl".t)
                                        .font(.caption2).foregroundColor(.textTertiary)
                                }
                                if let exp = promo.couponExpiresAt {
                                    Text("coupon_expires_lbl".t + ": \(exp.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption2).foregroundColor(.appAmber)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = promo.couponCode
                            copiedCode = promo.couponCode
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCode = nil }
                        } label: {
                            Image(systemName: copiedCode == promo.couponCode ? "checkmark.circle.fill" : "doc.on.doc")
                                .foregroundColor(copiedCode == promo.couponCode ? .appTeal : .appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.appSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                }
            }
            .padding()
        }
    }
}

// MARK: - New Coupon Form

private struct NewCouponForm: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Promotion.title) private var promotions: [Promotion]

    let onSave: () -> Void

    @State private var selectedPromoId: UUID? = nil
    @State private var couponCode = ""
    @State private var maxRedemptions = ""
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(86400 * 30)

    private func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    var body: some View {
        Form {
            Section("coupon_code_lbl".t) {
                HStack {
                    TextField("ALPHA2025", text: $couponCode)
                        .textCase(.uppercase)
                        .font(.system(.body, design: .monospaced))
                    Button("coupon_generate_btn".t) { couponCode = generateCode() }
                        .font(.caption.bold()).foregroundColor(.appAccent)
                }
            }
            Section("coupon_promo_link_lbl".t) {
                Picker("", selection: $selectedPromoId) {
                    Text("coupon_no_promo".t).tag(UUID?.none)
                    ForEach(promotions.filter { $0.isDeleted == false && $0.couponCode == nil }) { promo in
                        Text(promo.title).tag(Optional(promo.id))
                    }
                }
            }
            Section("coupon_max_use_lbl".t) {
                TextField("∞", text: $maxRedemptions).keyboardType(.numberPad)
            }
            Section {
                Toggle("coupon_has_expiry_lbl".t, isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("coupon_expires_lbl".t, selection: $expiresAt, displayedComponents: .date)
                }
            }
            Section {
                Button(action: saveCoupon) {
                    Text("coupon_save_btn".t).frame(maxWidth: .infinity)
                        .foregroundColor(canSaveCoupon ? .white : .textTertiary)
                }
                .listRowBackground(canSaveCoupon ? AnyView(APGradient.accent.opacity(1)) : AnyView(Color.appSurfaceHigh))
                .disabled(!canSaveCoupon)
            } footer: {
                Text("coupon_link_required_hint".t)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private var canSaveCoupon: Bool {
        !couponCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedPromoId != nil
    }

    private func saveCoupon() {
        guard sessionManager.can(.promotionsManage) else { return }
        let code = couponCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let promoId = selectedPromoId,
              let promo = promotions.first(where: { $0.id == promoId }),
              !code.isEmpty else { return }

        promo.couponCode = code
        promo.couponMaxRedemptions = Int(maxRedemptions)
        promo.couponExpiresAt = hasExpiry ? expiresAt : nil
        promo.isSynced = false
        promo.updatedAt = Date()
        modelContext.saveWithLogging(label: "CouponCodeSheet.saveCoupon")
        Task { await SyncEngine.shared.syncPromotions(modelContext) }
        onSave()
    }
}
