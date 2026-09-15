import SwiftUI
import SwiftData

/// Clear glass over photography; retain contrast when accessibility settings
/// request an opaque treatment. Keep this local rather than changing app chrome.
private struct POSPhotoGlass<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.foregroundStyle(.primary)
                .background(.regularMaterial, in: shape)
        } else if #available(iOS 26.0, *) {
            content.foregroundStyle(.primary)
                .glassEffect(.clear.interactive(interactive), in: shape)
        } else {
            content.foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Read-only stock diagnostics are available to POS staff. Stock writes continue
/// through the existing permission-checked receiving workflow.
private struct POSStockDetailsSheet: View {
    let item: MenuItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query private var recipes: [Recipe]
    @Query private var inventory: [InventoryItem]
    @State private var receivingItem: InventoryItem?

    private var branch: Branch? { try? BranchContext.shared.requireActiveBranch(in: modelContext) }
    private var requirements: [StockAvailability.Requirement] {
        // Observe stock writes, including completion of the receiving sheet.
        _ = inventory.count
        return StockAvailability.requirements(menuItem: item, activeBranch: branch, modelContext: modelContext)
    }
    private var canReceive: Bool {
        sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage)
    }
    private func affectedMenus(_ requirement: StockAvailability.Requirement) -> [String] {
        Array(Set(recipes.compactMap { recipe -> String? in
            guard !recipe.isDeleted, let menu = recipe.menuItem, !menu.isDeleted,
                  let ingredient = recipe.inventoryItem,
                  StockAvailability.resolveBranchItem(ingredient, branch: branch, context: modelContext)?.id == requirement.id
                    || ingredient.id == requirement.source.id else { return nil }
            return menu.name
        })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.name).font(.headline)
                    if !item.isAvailable {
                        Label("สินค้าถูกตั้งเป็นไม่พร้อมขาย", systemImage: "pause.circle")
                        Text("การรับสต๊อกจะไม่เปลี่ยนสถานะพร้อมขายที่ตั้งไว้ด้วยตนเอง")
                            .foregroundStyle(.secondary)
                    } else if requirements.contains(where: { $0.blocksSale }) {
                        Label("สต๊อกไม่พอสำหรับ 1 หน่วยขาย", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        Label("สต๊อกไม่ขัดขวางการขาย", systemImage: "checkmark.circle")
                    }
                    Text("ปริมาณตามสูตรต่อ 1 หน่วยขาย ยังไม่หักรายการในตะกร้า")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(item.resolvedTrackingMode == .finishedGood ? "สินค้าสำเร็จรูป" : "วัตถุดิบตามสูตร") {
                    if requirements.isEmpty {
                        Text("ไม่มีรายการสต๊อกที่ติดตามตามสูตร")
                    }
                    ForEach(requirements) { requirement in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(requirement.local?.name ?? requirement.source.name).font(.headline)
                            let unit = requirement.local?.unit ?? requirement.source.unit
                            Text("ต้องใช้ \(requirement.required.formatted()) \(unit) · เหลือ \(requirement.available.formatted()) \(unit)")
                            if requirement.local == nil {
                                Text("ยังไม่ได้ตั้งค่าสต๊อกสำหรับสาขานี้").foregroundStyle(.red)
                            } else if requirement.shortage > 0 {
                                Text("ขาด \(requirement.shortage.formatted()) \(unit)")
                                    .foregroundStyle(requirement.blocksSale ? Color.red : Color.orange)
                                if !requirement.blocksSale {
                                    Text("อนุญาตขายโดยติดลบ").foregroundStyle(.orange)
                                }
                            }
                            DisclosureGroup("เมนูที่ใช้ร่วมกัน (\(affectedMenus(requirement).count))") {
                                ForEach(affectedMenus(requirement), id: \.self) { name in Text(name) }
                            }
                            if let local = requirement.local, canReceive {
                                Button("รับสต๊อกรายการนี้", systemImage: "plus.circle") {
                                    receivingItem = local
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                if !canReceive {
                    Section {
                        Label("ไม่มีสิทธิ์รับสต๊อก กรุณาให้ผู้จัดการหรือผู้มีสิทธิ์ดำเนินการ", systemImage: "lock")
                    }
                }
            }
            .navigationTitle("ความพร้อมขาย")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("ปิด") { dismiss() } }
            }
            .sheet(item: $receivingItem) { stockItem in
                if sessionManager.can(.productCostsView) {
                ReceiveStockView(item: stockItem, viewModel: InventoryViewModel(modelContext: modelContext)) {
                    receivingItem = nil
                }
                } else {
                    OperationalReceiveStockView(item: stockItem) { receivingItem = nil }
                }
            }
        }
    }
}

// MARK: - Menu Item Card

struct POSProductCard: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    let item:     MenuItem
    let countInCart: Int
    let displayPrice: Double
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var lm: LocalizationManager
    @State private var isGlowActive = false
    @State private var showingStockDetails = false

    private var activeBranch: Branch? {
        try? BranchContext.shared.requireActiveBranch(in: modelContext)
    }

    private var isLocked: Bool {
        // The current backflush policy deliberately allows negative stock and
        // StockAvailability.sellableUnits therefore has no blocking ceiling.
        // Calling through that path for every visible card still resolved the
        // active branch during every render, despite always returning false.
        !item.isAvailable
    }

    private var stockBlockedLabel: String {
        guard item.isAvailable else { return "สินค้าปิดขาย" }
        if sessionManager.can(.inventoryManage) {
            if item.resolvedTrackingMode == .finishedGood { return "สินค้าหมด · ดูสาเหตุ" }
            let count = StockAvailability.requirements(menuItem: item, activeBranch: activeBranch, modelContext: modelContext)
                .filter { $0.blocksSale }.count
            return "วัตถุดิบขาด \(count) · ดูสาเหตุ"
        } else {
            return "สินค้าหมด"
        }
    }

    private var isLowStock: Bool {
        (UserDefaults.standard.object(forKey: "enable_realtime_stock_warning") as? Bool ?? true)
            && item.recipes.contains { recipe in
                guard let inventoryItem = recipe.inventoryItem else { return false }
                return inventoryItem.currentQuantity <= inventoryItem.safetyStockLevel
            }
    }

    private var hasNegativeIngredients: Bool {
        StockAvailability.hasNegativeIngredients(
            menuItem: item,
            activeBranch: activeBranch,
            modelContext: modelContext
        )
    }

    var body: some View {
        cardAppearance
            .contextMenu { cardContextMenu }
            .sheet(isPresented: Binding(
                get: { showingStockDetails && sessionManager.can(.inventoryManage) },
                set: { showingStockDetails = $0 }
            )) {
                POSStockDetailsSheet(item: item)
            }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            Button(action: increase) {
                VStack(spacing: 0) {
                    productImage
                    productInfo
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                Button(action: {
                    onDecrease()
                    APSoundEffect.itemRemoved()
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.appDivider, lineWidth: 1))
                }
                .disabled(countInCart == 0)
                .opacity(countInCart == 0 ? 0.55 : 1)

                Text("\(countInCart)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .contentTransition(
                        reduceMotion
                            ? .opacity
                            : .numericText(value: Double(countInCart))
                    )
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28),
                        value: countInCart
                    )

                Button(action: increase) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(POSReferencePalette.accent)
                        .clipShape(Circle())
                }
                .opacity(isLocked ? 0.5 : 1)
                .accessibilityLabel(isLocked ? "ดูสาเหตุที่ขายไม่ได้" : "เพิ่มสินค้า")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(POSReferencePalette.subtle)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.appDivider.opacity(0.65), lineWidth: 0.8)
            )
            .padding(.horizontal, 7)
            .padding(.top, 2)
            .padding(.bottom, 5)
        }
    }

    private var cardAppearance: some View {
        cardContent
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(countInCart > 0 ? POSReferencePalette.accent : Color.appDivider.opacity(0.8), lineWidth: countInCart > 0 ? 1.8 : 1)
        )
        .opacity(isLocked ? 0.58 : 1)
        .overlay {
            if isLocked {
                Color.black.opacity(0.12)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        Text(stockBlockedLabel)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.appRose.opacity(0.9))
                            .clipShape(Capsule())
                    )
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: isGlowActive ? POSReferencePalette.accent.opacity(0.25) : Color.black.opacity(0.06), radius: isGlowActive ? 9 : 5, x: 0, y: 2)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }

    private var stockDetailsButton: some View {
        Button {
            showingStockDetails = true
        } label: {
            Image(systemName: "info")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .modifier(POSPhotoGlass(shape: Circle(), interactive: true))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.trailing, 4)
        .accessibilityLabel(Text("ดูความพร้อมขายและวัตถุดิบของ \(item.name)"))
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        if sessionManager.can(.inventoryManage) {
            Button {
                showingStockDetails = true
            } label: {
                Label("ความพร้อมขาย / วัตถุดิบที่ขาด", systemImage: "info.circle")
            }
        }
        if sessionManager.can(.inventoryManage) || sessionManager.can(.posSell) {
            Button {
                item.isAvailable.toggle()
                item.isSynced = false
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label(item.isAvailable ? "ทำเครื่องหมาย: ปิดขายชั่วคราว (86)" : "ทำเครื่องหมาย: พร้อมขาย", systemImage: item.isAvailable ? "slash.circle" : "checkmark.circle")
            }
        }
        if sessionManager.can(.inventoryManage) {
            Button {
                guard sessionManager.can(.inventoryManage) else { return }
                item.isFavorite = !(item.isFavorite ?? false)
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label((item.isFavorite ?? false) ? "เอาออกจากรายการโปรด" : "เพิ่มเป็นรายการโปรด", systemImage: (item.isFavorite ?? false) ? "star.slash" : "star.fill")
            }

            Button {
                guard sessionManager.can(.inventoryManage) else { return }
                item.isBestseller = !(item.isBestseller ?? false)
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label((item.isBestseller ?? false) ? "เอาออกจากสินค้าขายดี" : "เพิ่มเป็นสินค้าขายดี", systemImage: (item.isBestseller ?? false) ? "flame.fill" : "flame")
            }

            Button {
                guard sessionManager.can(.inventoryManage) else { return }
                item.salesRole = item.resolvedSalesRole == .main
                    ? MenuItemSalesRole.addOn.rawValue
                    : MenuItemSalesRole.main.rawValue
                item.isSalesRoleConfirmed = true
                item.isSynced = false
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label(
                    item.resolvedSalesRole == .main ? "กำหนดเป็นรายการเสริม" : "กำหนดเป็นเมนูหลัก",
                    systemImage: item.resolvedSalesRole == .main ? "plus.circle" : "fork.knife"
                )
            }
        }
    }

    private var productImage: some View {
        let isDrink = item.category?.name.localizedCaseInsensitiveContains("drink") == true
            || item.category?.name.localizedCaseInsensitiveContains("bever") == true
            || item.name.localizedCaseInsensitiveContains("iced")
        let fallbackIcon = isDrink ? "wineglass.fill" : "fork.knife"
        let fallbackColor = Color(hex: item.colorHex ?? "1E1B4B")

        return Color.clear
            .aspectRatio(1.50, contentMode: .fit)
            .overlay {
                RemoteImageView(
                    imageUrl: item.imageUrl,
                    imageData: item.imageData,
                    fallbackColor: fallbackColor,
                    fallbackIcon: fallbackIcon
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) { imageBadges }
            .padding(.horizontal, 7)
            .padding(.top, 7)
            .contentShape(Rectangle())
    }

    private var productInfo: some View {
        VStack(spacing: 0) {
            Text(item.localizedName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.center)
                .frame(height: 18)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 6)
                .padding(.top, 3)

            Text(String(format: "฿%.0f", displayPrice))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.textPrimary)
                .padding(.top, 1)
                .padding(.bottom, 3)
        }
    }

    private func increase() {
        guard !isLocked else {
            APHaptic.trigger()
            APSoundEffect.alert()
            if sessionManager.can(.inventoryManage) {
                showingStockDetails = true
            }
            return
        }
        onIncrease()
        APSoundEffect.itemTap()
        withAnimation(.easeOut(duration: 0.12)) { isGlowActive = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.25)) { isGlowActive = false }
        }
    }

    private func availabilityBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }

    private var imageBadges: some View {
        HStack(spacing: 3) {
            if isLocked {
                availabilityBadge(text: item.isAvailable ? "ของหมด" : "ปิดขาย", color: .appRose)
            } else if hasNegativeIngredients {
                availabilityBadge(text: "สต็อกติดลบ", color: .appRose)
            } else if isLowStock {
                availabilityBadge(text: "ใกล้หมด", color: .orange)
            }

            if item.resolvedSalesRole == .addOn {
                Text("รายการเสริม")
                    .font(.system(size: 7.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .modifier(POSPhotoGlass(shape: Capsule()))
            }

            if item.isBestseller ?? false {
                badgeIcon("flame.fill", color: .orange)
            }

            Spacer()

            if item.isFavorite ?? false {
                badgeIcon("star.fill", color: .appAmber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .zIndex(1)
    }

    private func badgeIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(.white)
            .padding(3)
            .background(color)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 1.5)
    }
}
