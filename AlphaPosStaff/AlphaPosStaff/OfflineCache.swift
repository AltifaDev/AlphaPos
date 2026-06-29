// OfflineCache.swift
// AlphaPosStaff — Offline Cache Manager
// Caches critical data to device storage for offline operation.
// Auto-syncs queued orders when connection is restored.

import Foundation
import SwiftUI
import Network

// MARK: - Offline Cache Manager

@MainActor
final class OfflineCache {
    static let shared = OfflineCache()
    
    // MARK: - State
    
    /// True when device cannot reach Supabase
    var isOffline: Bool = false

    /// Maximum retry attempts per queued order before it is moved to dead-letter
    private let maxRetryAttempts = 5

    // MARK: - NWPathMonitor (real-time connectivity)

    @ObservationIgnored
    private let pathMonitor = NWPathMonitor()
    @ObservationIgnored
    private let monitorQueue = DispatchQueue(label: "com.alphapos.offlinecache.monitor", qos: .utility)

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nowOffline = (path.status != .satisfied)
                if self.isOffline && !nowOffline {
                    // Just came back online — trigger sync
                    self.isOffline = false
                    if self.queuedOrderCount > 0 {
                        Task { let _ = await self.syncOfflineQueue() }
                    }
                    await NetworkService.shared.refreshAll()
                } else {
                    self.isOffline = nowOffline
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    /// Number of orders waiting to be submitted
    var queuedOrderCount: Int { pendingOrders.count }
    
    /// Queued orders (created offline, waiting for connectivity)
    private(set) var pendingOrders: [QueuedOrder] = []
    
    // MARK: - File Paths
    
    private var cacheDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // MERCHANT-NAMESPACED: each merchant gets its own cache directory
        // so data from merchant A never bleeds into merchant B on the same device.
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "default"
        let safeId = merchantId.trimmingCharacters(in: .whitespacesAndNewlines)
                               .replacingOccurrences(of: "/", with: "_")
        let dir = docs.appendingPathComponent("OfflineCache/\(safeId)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var menuCacheURL: URL { cacheDir.appendingPathComponent("menu_cache.json") }
    private var tablesCacheURL: URL { cacheDir.appendingPathComponent("tables_cache.json") }
    private var ordersCacheURL: URL { cacheDir.appendingPathComponent("orders_cache.json") }
    private var queueURL: URL { cacheDir.appendingPathComponent("offline_queue.json") }
    
    // MARK: - Init
    
    private init() {
        loadPendingOrders()
        startPathMonitor()
    }
    
    // MARK: - Menu Cache
    
    func cacheMenu(_ items: [MenuItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: menuCacheURL)
            #if DEBUG
            print("[OfflineCache] Cached \(items.count) menu items")
            #endif
        } catch {
            #if DEBUG
            print("[OfflineCache] Failed to cache menu: \(error)")
            #endif
        }
    }
    
    func loadCachedMenu() -> [MenuItem]? {
        guard let data = try? Data(contentsOf: menuCacheURL),
              let items = try? JSONDecoder().decode([MenuItem].self, from: data) else {
            return nil
        }
        #if DEBUG
        print("[OfflineCache] Loaded \(items.count) cached menu items")
        #endif
        return items
    }
    
    // MARK: - Tables Cache
    
    func cacheTables(_ tables: [RestaurantTable]) {
        do {
            let data = try JSONEncoder().encode(tables)
            try data.write(to: tablesCacheURL)
            #if DEBUG
            print("[OfflineCache] Cached \(tables.count) tables")
            #endif
        } catch {
            #if DEBUG
            print("[OfflineCache] Failed to cache tables: \(error)")
            #endif
        }
    }
    
    func loadCachedTables() -> [RestaurantTable]? {
        guard let data = try? Data(contentsOf: tablesCacheURL),
              let tables = try? JSONDecoder().decode([RestaurantTable].self, from: data) else {
            return nil
        }
        #if DEBUG
        print("[OfflineCache] Loaded \(tables.count) cached tables")
        #endif
        return tables
    }
    
    // MARK: - Active Orders Cache
    
    func cacheOrders(_ orders: [Order]) {
        do {
            let data = try JSONEncoder().encode(orders)
            try data.write(to: ordersCacheURL)
        } catch {
            #if DEBUG
            print("[OfflineCache] Failed to cache orders: \(error)")
            #endif
        }
    }
    
    func loadCachedOrders() -> [Order]? {
        guard let data = try? Data(contentsOf: ordersCacheURL),
              let orders = try? JSONDecoder().decode([Order].self, from: data) else {
            return nil
        }
        return orders
    }
    
    // MARK: - Offline Order Queue
    
    /// Queue an order that was created while offline
    func queueOrder(_ order: QueuedOrder) {
        pendingOrders.append(order)
        savePendingOrders()
        #if DEBUG
        print("[OfflineCache] Queued order #\(order.orderNumber) — total queue: \(pendingOrders.count)")
        #endif
    }
    
    /// Submit all queued orders to server (call when back online)
    func syncOfflineQueue() async -> Int {
        guard !pendingOrders.isEmpty else { return 0 }
        
        var successCount = 0
        var failedOrders: [QueuedOrder] = []
        
        for order in pendingOrders {
            do {
                let success = try await NetworkService.shared.uploadOrder(
                    orderId: order.id,
                    orderNumber: order.orderNumber,
                    tableNumber: order.tableNumber,
                    total: order.total,
                    items: order.itemsPayload,
                    sessionToken: order.sessionToken,
                    guestCount: order.guestCount,
                    orderType: order.orderType
                )
                if success {
                    successCount += 1
                    #if DEBUG
                    print("[OfflineCache] Synced queued order #\(order.orderNumber)")
                    #endif
                } else {
                    // Server rejected (non-throw) — increment retry counter
                    var bumped = order
                    bumped.retryCount += 1
                    if bumped.retryCount < maxRetryAttempts {
                        failedOrders.append(bumped)
                    } else {
                        #if DEBUG
                        print("[OfflineCache] Dead-lettering order #\(order.orderNumber) after \(bumped.retryCount) retries")
                        #endif
                    }
                }
            } catch {
                var bumped = order
                bumped.retryCount += 1
                if bumped.retryCount < maxRetryAttempts {
                    failedOrders.append(bumped)
                } else {
                    #if DEBUG
                    print("[OfflineCache] Dead-lettering order #\(order.orderNumber) after \(bumped.retryCount) retries: \(error.localizedDescription)")
                    #endif
                }
                #if DEBUG
                print("[OfflineCache] Retry \(order.retryCount+1)/\(maxRetryAttempts) for order #\(order.orderNumber): \(error.localizedDescription)")
                #endif
            }
        }
        
        await MainActor.run {
            self.pendingOrders = failedOrders
            self.savePendingOrders()
        }
        
        #if DEBUG
        print("[OfflineCache] Queue sync complete: \(successCount) sent, \(failedOrders.count) remaining")
        #endif
        
        return successCount
    }
    
    /// Remove a specific order from queue (e.g. user cancels)
    func removeFromQueue(orderId: String) {
        pendingOrders.removeAll { $0.id == orderId }
        savePendingOrders()
    }
    
    /// Clear entire queue (danger!)
    func clearQueue() {
        pendingOrders.removeAll()
        savePendingOrders()
    }
    
    // MARK: - Cache Metadata
    
    var menuCacheAge: TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: menuCacheURL.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(date)
    }
    
    var hasCachedMenu: Bool {
        FileManager.default.fileExists(atPath: menuCacheURL.path)
    }
    
    var hasCachedTables: Bool {
        FileManager.default.fileExists(atPath: tablesCacheURL.path)
    }
    
    // MARK: - Clear All Cache
    
    func clearAll() {
        try? FileManager.default.removeItem(at: menuCacheURL)
        try? FileManager.default.removeItem(at: tablesCacheURL)
        try? FileManager.default.removeItem(at: ordersCacheURL)
        clearQueue()
    }
    
    // MARK: - Private Helpers
    
    private func savePendingOrders() {
        do {
            let data = try JSONEncoder().encode(pendingOrders)
            try data.write(to: queueURL)
        } catch {
            #if DEBUG
            print("[OfflineCache] Failed to save queue: \(error)")
            #endif
        }
    }
    
    private func loadPendingOrders() {
        guard let data = try? Data(contentsOf: queueURL),
              let orders = try? JSONDecoder().decode([QueuedOrder].self, from: data) else {
            return
        }
        pendingOrders = orders
        #if DEBUG
        if !orders.isEmpty {
            print("[OfflineCache] Loaded \(orders.count) queued orders from disk")
        }
        #endif
    }
}

// MARK: - Queued Order Model

struct QueuedOrder: Codable, Identifiable {
    let id: String
    let orderNumber: String
    let tableNumber: String
    let total: Double
    let itemsPayload: [[String: Any]]
    let sessionToken: String?
    let guestCount: Int
    let orderType: String  // "takeaway", "delivery", "walk_in", "dine_in"
    let createdAt: Date
    var retryCount: Int

    // Custom Codable for [[String: Any]]
    enum CodingKeys: String, CodingKey {
        case id, orderNumber, tableNumber, total, itemsData, sessionToken, guestCount, orderType, createdAt, retryCount
    }

    init(id: String = UUID().uuidString, orderNumber: String, tableNumber: String, total: Double, itemsPayload: [[String: Any]], sessionToken: String? = nil, guestCount: Int = 1, orderType: String = "takeaway", createdAt: Date = Date(), retryCount: Int = 0) {
        self.id = id
        self.orderNumber = orderNumber
        self.tableNumber = tableNumber
        self.total = total
        self.itemsPayload = itemsPayload
        self.sessionToken = sessionToken
        self.guestCount = guestCount
        self.orderType = orderType
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderNumber = try container.decode(String.self, forKey: .orderNumber)
        tableNumber = try container.decode(String.self, forKey: .tableNumber)
        total = try container.decode(Double.self, forKey: .total)
        sessionToken = try container.decodeIfPresent(String.self, forKey: .sessionToken)
        guestCount = try container.decode(Int.self, forKey: .guestCount)
        orderType = try container.decode(String.self, forKey: .orderType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retryCount = (try? container.decode(Int.self, forKey: .retryCount)) ?? 0
        
        let itemsData = try container.decode(Data.self, forKey: .itemsData)
        itemsPayload = (try? JSONSerialization.jsonObject(with: itemsData) as? [[String: Any]]) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(orderNumber, forKey: .orderNumber)
        try container.encode(tableNumber, forKey: .tableNumber)
        try container.encode(total, forKey: .total)
        try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
        try container.encode(guestCount, forKey: .guestCount)
        try container.encode(orderType, forKey: .orderType)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(retryCount, forKey: .retryCount)
        
        let itemsData = (try? JSONSerialization.data(withJSONObject: itemsPayload)) ?? Data()
        try container.encode(itemsData, forKey: .itemsData)
    }
}
