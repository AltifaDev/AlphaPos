import Foundation
import Combine

struct SyncConflictJournalRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let merchantId: String
    let source: String
    let strategy: String
    let decision: String
    let baseSnapshot: String?
    let localSnapshot: String
    let remoteSnapshot: String
    let detectedAt: Date
    var resolvedAt: Date?
}

/// Durable, tenant-scoped audit journal for sync conflicts. The journal stores
/// immutable decision evidence and never contains business payload or PII.
@MainActor
final class SyncConflictJournal: ObservableObject {
    static let shared = SyncConflictJournal()
    @Published private(set) var records: [SyncConflictJournalRecord] = []

    private let maximumRecords = 500
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() { load() }

    var activeMerchantRecords: [SyncConflictJournalRecord] {
        let merchant = activeMerchantId
        return records.filter { $0.merchantId == merchant }
    }

    func record(source: String, strategy: String, decision: String,
                baseAt: Date?, localAt: Date, remoteAt: Date) {
        let formatter = ISO8601DateFormatter()
        let entry = SyncConflictJournalRecord(
            id: UUID(), merchantId: activeMerchantId, source: source,
            strategy: strategy, decision: decision,
            baseSnapshot: baseAt.map(formatter.string(from:)),
            localSnapshot: formatter.string(from: localAt),
            remoteSnapshot: formatter.string(from: remoteAt),
            detectedAt: Date(), resolvedAt: decision == "manual_pending" ? nil : Date()
        )
        records.insert(entry, at: 0)
        if records.count > maximumRecords { records.removeLast(records.count - maximumRecords) }
        persist()
    }

    func acknowledge(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].resolvedAt = Date()
        persist()
    }

    private var activeMerchantId: String {
        (UserDefaults.standard.string(forKey: "active_merchant_id") ?? "unbound").lowercased()
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("sync-conflict-journal.json")
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([SyncConflictJournalRecord].self, from: data) else { return }
        records = Array(decoded.prefix(maximumRecords))
    }

    private func persist() {
        guard let url = fileURL, let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
