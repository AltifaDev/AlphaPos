import SwiftUI
import SwiftData

struct POSCatalogItemSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let price: Double
    let imageURL: String?
    let colorHex: String?
    let isAvailable: Bool
    let isFavorite: Bool
    let isBestseller: Bool
    let hasNegativeStock: Bool
    let hasLowStock: Bool
}

@Observable @MainActor
final class POSCatalogStore {
    static let pageSize = 80
    private(set) var items: [POSCatalogItemSnapshot] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var totalAvailableItems = 0
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var liveItems: [String: MenuItem] = [:]
    @ObservationIgnored private var generation = UUID()
    private(set) var favoritesOnly = false
    private var categoryID: UUID?
    private var searchQuery = ""

    func configure(_ context: ModelContext) { self.context = context }

    func reload(favoritesOnly: Bool, categoryID: UUID?, searchQuery: String) async {
        self.favoritesOnly = favoritesOnly
        self.categoryID = categoryID
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        generation = UUID(); items = []; liveItems = [:]; hasMore = false; hasLoaded = false
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, let context else { return }
        isLoading = true; defer { isLoading = false; hasLoaded = true }
        let token = generation
        let selectedCategoryID = categoryID
        var descriptor: FetchDescriptor<MenuItem>
        if favoritesOnly, let selectedCategoryID {
            descriptor = FetchDescriptor(predicate: #Predicate { !$0.isDeleted && $0.isFavorite == true && $0.category?.id == selectedCategoryID }, sortBy: [SortDescriptor(\MenuItem.name)])
        } else if favoritesOnly {
            descriptor = FetchDescriptor(predicate: #Predicate { !$0.isDeleted && $0.isFavorite == true }, sortBy: [SortDescriptor(\MenuItem.name)])
        } else if let selectedCategoryID {
            descriptor = FetchDescriptor(predicate: #Predicate { !$0.isDeleted && $0.category?.id == selectedCategoryID }, sortBy: [SortDescriptor(\MenuItem.name)])
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { !$0.isDeleted }, sortBy: [SortDescriptor(\MenuItem.name)])
        }
        let searching = !searchQuery.isEmpty
        descriptor.fetchOffset = searching ? 0 : items.count
        descriptor.fetchLimit = searching ? Self.pageSize * 5 : Self.pageSize + 1
        let fetched = (try? context.fetch(descriptor)) ?? []
        guard token == generation else { return }
        let needle = Self.normalize(searchQuery)
        let matching = needle.isEmpty ? fetched : fetched.filter {
            Self.normalize($0.name).contains(needle) || Self.normalize($0.sku ?? "").contains(needle) || Self.normalize($0.barcode ?? "").contains(needle)
        }
        let page = Array(matching.prefix(Self.pageSize))
        hasMore = searching ? matching.count > Self.pageSize : fetched.count > Self.pageSize
        page.forEach { liveItems[$0.id] = $0 }
        items.append(contentsOf: page.map(Self.makeSnapshot))
        if items.count == page.count {
            totalAvailableItems = (try? context.fetchCount(FetchDescriptor<MenuItem>(predicate: #Predicate { !$0.isDeleted }))) ?? items.count
        }
        RemoteImageManager.shared.prefetchThumbnails(urls: page.prefix(12).compactMap(\.imageUrl), targetPixelSize: 360)
    }

    func resolve(_ id: String) -> MenuItem? {
        if let item = liveItems[id], !item.isDeleted { return item }
        guard let context else { return nil }
        var descriptor = FetchDescriptor<MenuItem>(predicate: #Predicate { $0.id == id && !$0.isDeleted })
        descriptor.fetchLimit = 1
        let item = try? context.fetch(descriptor).first
        if let item { liveItems[id] = item }
        return item
    }

    func exactMatch(_ value: String) -> MenuItem? {
        guard let context else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<MenuItem>(predicate: #Predicate { !$0.isDeleted && ($0.sku == key || $0.barcode == key) })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeSnapshot(_ item: MenuItem) -> POSCatalogItemSnapshot {
        return .init(id: item.id, name: item.localizedName, price: item.price, imageURL: item.imageUrl,
            colorHex: item.colorHex, isAvailable: item.isAvailable, isFavorite: item.isFavorite ?? false,
            isBestseller: item.isBestseller ?? false,
            hasNegativeStock: false, hasLowStock: false)
    }
}

struct POSProductPanel: View {
    let catalog: POSCatalogStore
    @Binding var animateItems: Bool
    let quantitiesByItemID: [String: Int]
    let displayPrice: (MenuItem) -> Double
    let onIncrease: (MenuItem) -> Void
    let onDecrease: (String) -> Void
    let onShowAll: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let count = min(4, max(1, Int((geometry.size.width + 10) / 138)))
            let columns = Array(repeating: GridItem(.flexible(minimum: 128), spacing: 10), count: count)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    if catalog.hasLoaded && catalog.items.isEmpty && !catalog.isLoading {
                        VStack(spacing: 10) {
                            Image(systemName: catalog.favoritesOnly ? "star.slash" : "shippingbox")
                                .font(.system(size: 30)).foregroundStyle(.secondary)
                            Text(catalog.favoritesOnly ? "ยังไม่มีรายการโปรด" : "ไม่พบสินค้า")
                                .foregroundStyle(.secondary)
                            if catalog.favoritesOnly { Button("แสดงสินค้าทั้งหมด", action: onShowAll) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 48).gridCellColumns(count)
                    }
                    ForEach(Array(catalog.items.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if let liveItem = catalog.resolve(item.id) {
                                POSProductCard(
                                    item: liveItem,
                                    countInCart: quantitiesByItemID[item.id, default: 0],
                                    displayPrice: displayPrice(liveItem),
                                    onIncrease: { onIncrease(liveItem) },
                                    onDecrease: { onDecrease(item.id) }
                                )
                            }
                        }
                        .onAppear {
                            if index >= catalog.items.count - 12, catalog.hasMore { Task { await catalog.loadNextPage() } }
                            RemoteImageManager.shared.prefetchThumbnails(urls: catalog.items.dropFirst(index + 4).prefix(12).compactMap(\.imageURL), targetPixelSize: 360)
                        }
                    }
                    if catalog.isLoading { ProgressView().gridCellColumns(count).padding() }
                }.padding(12)
            }
        }
        .background(POSReferencePalette.background)
        .offset(x: animateItems ? 0 : -40).opacity(animateItems ? 1 : 0)
        .animation(.easeOut(duration: 0.22), value: animateItems)
    }
}

struct MenuItemButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1) } }
private struct POSCategoryChipStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View { content.font(.system(size: 14, weight: selected ? .semibold : .regular)).foregroundColor(selected ? .textPrimary : .textSecondary).padding(.horizontal, 8).frame(height: 38) }
}
extension View { func posCategoryChip(selected: Bool) -> some View { modifier(POSCategoryChipStyle(selected: selected)) } }
struct PaymentButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).brightness(configuration.isPressed ? -0.04 : 0) } }
