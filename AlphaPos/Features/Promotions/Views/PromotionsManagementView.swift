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

private enum PromotionListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case scheduled = "Scheduled"
    case inactive = "Inactive"
    case expired = "Expired"

    var id: String { rawValue }
}

struct PromotionsManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Promotion> { $0.isDeleted == false }, sort: \Promotion.updatedAt, order: .reverse) private var promotions: [Promotion]
    @Query(filter: #Predicate<OrderDiscount> { $0.isDeleted == false }) private var orderDiscounts: [OrderDiscount]

    @Binding var columnVisibility: NavigationSplitViewVisibility
    @EnvironmentObject private var lm: LocalizationManager

    @State private var showingAddSheet = false
    @State private var promotionToEdit: Promotion? = nil
    @State private var deletingPromotionIds = Set<UUID>()
    @State private var promotionPendingDelete: Promotion? = nil
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var selectedFilter: PromotionListFilter = .all

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView

                    if promotions.isEmpty {
                        emptyStateView
                    } else {
                        campaignOverview
                        filterBar
                        promotionsGridView
                    }
                }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddSheet) {
            PromotionFormSheet(promotion: nil)
        }
        .sheet(item: $promotionToEdit) { promotion in
            PromotionFormSheet(promotion: promotion)
        }
        .onAppear {
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
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
        HStack(spacing: 16) {
            if columnVisibility == .detailOnly {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = .all
                    }
                    APHaptic.trigger()
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.appAccent)
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.Promos.title.t)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(L.Promos.subtitle.t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            Spacer()

            Button(action: { showingAddSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(L.Promos.addPromotion.t)
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color(hex: "10B981").opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 80, height: 80)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "10B981"))
            }

            VStack(spacing: 8) {
                Text(L.Promos.noPromotionsTitle.t)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(L.Promos.noPromotionsSubtitle.t)
                    .font(.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundColor(.textTertiary)
            Text("No \(selectedFilter.rawValue.lowercased()) campaigns")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("no_promotions_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .background(Color.appSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
            overviewTile("Active", value: "\(activeCount)", icon: "bolt.fill", color: .appTeal)
            overviewTile("Scheduled", value: "\(scheduledCount)", icon: "calendar.badge.clock", color: .orange)
            overviewTile("History", value: "\(expiredCount)", icon: "clock.arrow.circlepath", color: .textSecondary)
            overviewTile("Used", value: "\(totalUses)", icon: "receipt", color: .appAccent)
            overviewTile("Discount", value: "฿\(totalDiscount.formatted(.number.precision(.fractionLength(0...0))))", icon: "chart.bar.fill", color: .appRose)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func overviewTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .cornerRadius(8)

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
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.appSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Promotion status", selection: $selectedFilter) {
                ForEach(PromotionListFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Text("\(filteredPromotions.count) campaigns")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func promotionCard(for promo: Promotion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                promotionMediaPreview(promo)

                // Status Badge Overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(promotionStatusText(promo))
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
                        Text(deletingPromotionIds.contains(promo.id) ? "Deleting" : (promo.isSynced ? "Synced" : "Unsynced"))
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    // Action Buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation {
                                promo.isActive.toggle()
                                promo.isSynced = false
                                promo.updatedAt = Date()
                                try? modelContext.save()

                                // Trigger sync in the background
                                Task {
                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
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
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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
           let base64 = promo.imageData,
           let url = temporaryMediaURL(base64: base64, extension: "mp4") {
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
        } else if let base64 = promo.imageData,
                  let data = Data(base64Encoded: base64),
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

    private func temporaryMediaURL(base64: String, extension fileExtension: String) -> URL? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alphapos-promo-\(base64.hashValue)")
            .appendingPathExtension(fileExtension)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    private func promotionStatusText(_ promo: Promotion) -> String {
        if !promo.isActive { return "Inactive" }
        let now = Date()
        if let startsAt = promo.startsAt, now < startsAt { return "Scheduled" }
        if let endsAt = promo.endsAt, now > endsAt { return "Expired" }
        return "Active"
    }

    private func promotionStatusColor(_ promo: Promotion) -> Color {
        switch promotionStatusText(promo) {
        case "Active": return .appTeal
        case "Scheduled": return .orange
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
        guard !deletingPromotionIds.contains(promo.id) else { return }
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
                        try? modelContext.save()
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

private struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        context.coordinator.configure(url: url, in: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.configure(url: url, in: uiView)
    }

    final class Coordinator {
        private var currentURL: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL, in view: PlayerContainerView) {
            guard currentURL != url else { return }
            currentURL = url

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player

            view.playerLayer.player = player
            player.play()
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}

struct PromotionFormSheet: View {
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MenuItem> { $0.isDeleted == false }, sort: \MenuItem.name) private var menuItems: [MenuItem]

    let promotion: Promotion?

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

    var isNew: Bool { promotion == nil }

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

                Section(header: Text("promo_type_label".t)) {
                    promotionPresetButtons

                    Picker("promo_type_label".t, selection: $discountType) {
                        Text(L.Promos.typeNone.t).tag("none")
                        Text(L.Promos.typePercentage.t).tag("percentage")
                        Text(L.Promos.typeFixed.t).tag("fixed")
                        Text(L.Promos.typeBundle.t).tag("bundle_price")
                        Text("promo_type_buy_x_get_y".t).tag("buy_x_get_y")
                        Text("promo_type_buy_x_pay_y".t).tag("buy_x_pay_y")
                    }

                    if discountType != "none" {
                        if requiresProductRule {
                            Picker("product_name_header".t, selection: $appliesToMenuItemId) {
                                Text(L.Promos.selectProduct.t).tag("")
                                ForEach(menuItems) { item in
                                    Text(item.name).tag(item.id)
                                }
                            }

                            Stepper(requiredQuantityLabel, value: $requiredQuantity, in: 1...99)

                            if discountType == "buy_x_get_y" || discountType == "buy_x_pay_y" {
                                Stepper(rewardQuantityLabel, value: $rewardQuantity, in: 1...99)
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
                        }

                        if !requiresProductRule {
                            HStack {
                                Text("minimum_spend_lbl".t)
                                Spacer()
                                TextField("0", value: $minimumSpend, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                            }
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

                Section(header: Text("banner_media_section".t)) {
                    VStack(spacing: 12) {
                        mediaGuidancePanel

                        if isProcessingMedia {
                            ProgressView("processing_media_lbl".t)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if mediaType == "video",
                                  let base64 = mediaDataBase64,
                                  let url = temporaryMediaURL(base64: base64, extension: "mp4") {
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
                        } else if let base64 = mediaDataBase64,
                                  let data = Data(base64Encoded: base64),
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
            .navigationTitle(isNew ? L.Promos.addPromotion.t : L.Promos.editPromotion.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        savePromotion()
                    }
                    .disabled(isSaveDisabled)
                    .foregroundColor(isSaveDisabled ? .textTertiary : Color(hex: "10B981"))
                }
            }
            .onChange(of: selectedMediaItem) { _, newItem in
                Task {
                    guard let item = newItem else { return }
                    await MainActor.run { isProcessingMedia = true }

                    if let data = try? await item.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: data) {
                        // Downscale to max 800 width while maintaining aspect ratio
                            let resized = resizeImage(image: image, targetSize: CGSize(width: 800, height: 400))
                            if let jpeg = resized.jpegData(compressionQuality: 0.7) {
                                let base64 = jpeg.base64EncodedString()
                                await MainActor.run {
                                    self.mediaDataBase64 = base64
                                    self.mediaType = "image"
                                    self.isProcessingMedia = false
                                }
                                return
                            }
                        } else {
                            await MainActor.run {
                                self.mediaDataBase64 = data.base64EncodedString()
                                self.mediaType = "video"
                                self.isProcessingMedia = false
                            }
                            return
                        }
                    }
                    await MainActor.run { isProcessingMedia = false }
                }
            }
            .onAppear {
                if let promo = promotion {
                    title = promo.title
                    promoDescription = promo.promoDescription ?? ""
                    mediaDataBase64 = promo.imageData
                    mediaType = promo.mediaType
                    isActive = promo.isActive
                    discountType = promo.discountType
                    discountValue = promo.discountValue
                    minimumSpend = promo.minimumSpend
                    appliesToMenuItemId = promo.appliesToMenuItemId ?? ""
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
                }
            }
        }
    }

    private var invalidSchedule: Bool {
        hasStartDate && hasEndDate && startsAt >= endsAt
    }

    private var isSaveDisabled: Bool {
        title.isEmpty || isProcessingMedia || invalidSchedule || invalidPromotionRule
    }

    private var invalidPromotionRule: Bool {
        if requiresProductRule && appliesToMenuItemId.isEmpty { return true }
        if discountType == "bundle_price" && discountValue <= 0 { return true }
        if discountType == "buy_x_get_y" && rewardQuantity < 1 { return true }
        if discountType == "buy_x_pay_y" && (rewardQuantity < 1 || rewardQuantity >= requiredQuantity) { return true }
        return false
    }

    private var requiresProductRule: Bool {
        discountType == "bundle_price" || discountType == "buy_x_get_y" || discountType == "buy_x_pay_y"
    }

    private var showsDiscountValue: Bool {
        discountType == "percentage" || discountType == "fixed" || discountType == "bundle_price"
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
        case "bundle_price": return "bundle_price_lbl".t
        default: return "discount_val_amt_lbl".t
        }
    }

    private func savePromotion() {
        if let promo = promotion {
            // Edit existing
            promo.title = title
            promo.promoDescription = promoDescription
            promo.imageData = mediaDataBase64
            promo.mediaType = mediaType
            promo.isActive = isActive
            promo.discountType = discountType
            promo.discountValue = normalizedDiscountValue
            promo.minimumSpend = requiresProductRule ? 0 : max(0, minimumSpend)
            promo.appliesToMenuItemId = requiresProductRule ? appliesToMenuItemId : nil
            promo.requiredQuantity = requiresProductRule ? max(1, requiredQuantity) : 1
            promo.rewardQuantity = requiresProductRule ? normalizedRewardQuantity : 0
            promo.startsAt = hasStartDate ? startsAt : nil
            promo.endsAt = hasEndDate ? endsAt : nil
            promo.isSynced = false
            promo.updatedAt = Date()
        } else {
            // Create new
            let newPromo = Promotion(
                title: title,
                promoDescription: promoDescription,
                imageData: mediaDataBase64,
                mediaType: mediaType,
                isActive: isActive,
                discountType: discountType,
                discountValue: normalizedDiscountValue,
                minimumSpend: requiresProductRule ? 0 : max(0, minimumSpend),
                appliesToMenuItemId: requiresProductRule ? appliesToMenuItemId : nil,
                requiredQuantity: requiresProductRule ? max(1, requiredQuantity) : 1,
                rewardQuantity: requiresProductRule ? normalizedRewardQuantity : 0,
                startsAt: hasStartDate ? startsAt : nil,
                endsAt: hasEndDate ? endsAt : nil
            )
            modelContext.insert(newPromo)
        }

        try? modelContext.save()

        // Trigger sync in the background
        let context = modelContext
        Task {
            await SyncEngine.shared.syncAll(modelContext: context)
        }

        dismiss()
    }

    private var normalizedDiscountValue: Double {
        if discountType == "percentage" {
            return min(100, max(0, discountValue))
        }
        if discountType == "fixed" {
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
                presetButton("Banner", systemImage: "megaphone") {
                    discountType = "none"
                    discountValue = 0
                    minimumSpend = 0
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

    private func temporaryMediaURL(base64: String, extension fileExtension: String) -> URL? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alphapos-promo-form-\(base64.hashValue)")
            .appendingPathExtension(fileExtension)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        let newRatio = min(widthRatio, heightRatio)

        // If image is already smaller, don't upscale it
        if newRatio >= 1.0 {
            return image
        }

        let newSize = CGSize(width: size.width * newRatio, height: size.height * newRatio)
        let rect = CGRect(origin: .zero, size: newSize)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
}
