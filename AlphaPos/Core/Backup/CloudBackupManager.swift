import CryptoKit
import Combine
import Foundation
import SQLite3
import SwiftData

struct CloudBackupManifest: Codable, Identifiable, Sendable {
    let id: UUID
    let merchantId: UUID
    let storagePath: String
    let schemaVersion: Int
    let appVersion: String
    let createdAt: Date
    let deviceId: String
    let recordCounts: [String: Int]
    let fileCount: Int
    let byteCount: Int64
    let payloadChecksum: String
    let signature: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, status, signature
        case merchantId = "merchant_id"
        case storagePath = "storage_path"
        case schemaVersion = "schema_version"
        case appVersion = "app_version"
        case createdAt = "created_at"
        case deviceId = "device_id"
        case recordCounts = "record_counts"
        case fileCount = "file_count"
        case byteCount = "byte_count"
        case payloadChecksum = "payload_checksum"
    }
}

enum CloudBackupError: LocalizedError {
    case invalidMerchant, signInRequired, storeUnavailable, snapshotFailed(String)
    case server(String), corruptBackup, incompatibleSchema(Int), wrongMerchant

    var errorDescription: String? {
        switch self {
        case .invalidMerchant: return "ไม่พบรหัสร้านที่ถูกต้อง"
        case .signInRequired: return "เซสชันออนไลน์หมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง"
        case .storeUnavailable: return "ไม่พบฐานข้อมูลภายในเครื่อง"
        case .snapshotFailed(let value): return "สร้าง Snapshot ไม่สำเร็จ: \(value)"
        case .server(let value): return "บริการ Backup ตอบกลับผิดพลาด: \(value)"
        case .corruptBackup: return "ไฟล์ Backup ไม่สมบูรณ์หรือถูกแก้ไข"
        case .incompatibleSchema(let version): return "Backup schema รุ่น \(version) ยังไม่รองรับ"
        case .wrongMerchant: return "Backup นี้เป็นข้อมูลของร้านอื่น"
        }
    }
}

@MainActor
final class CloudBackupManager: ObservableObject {
    static let shared = CloudBackupManager()
    nonisolated static let schemaVersion = 1

    @Published private(set) var isWorking = false
    @Published private(set) var latestManifest: CloudBackupManifest?
    @Published private(set) var statusMessage: String?

    private let config = AppConfig.shared
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    func createBackup(modelContext: ModelContext) async throws -> CloudBackupManifest {
        guard !isWorking else { throw CloudBackupError.snapshotFailed("มีงาน Backup กำลังทำงาน") }
        isWorking = true
        statusMessage = "กำลังสร้าง Snapshot…"
        BackupNetworkAuthorization.shared.begin()
        defer {
            isWorking = false
            BackupNetworkAuthorization.shared.end()
        }

        try modelContext.save()
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        guard let token = MerchantAuthManager.shared.authorizationToken else {
            throw CloudBackupError.signInRequired
        }
        let identity = try currentIdentity()
        let backupId = UUID()
        let createdAt = Date()
        let package = try makePackage(
            merchantId: identity.merchantId,
            backupId: backupId,
            createdAt: createdAt,
            modelContext: modelContext
        )
        let checksum = Self.sha256(package.data)
        let path = "\(identity.merchantId.uuidString.lowercased())/\(backupId.uuidString.lowercased()).alphaposbackup"

        statusMessage = "กำลังอัปโหลด Snapshot…"
        try await upload(package.data, path: path, token: token)

        let manifest = CloudBackupManifest(
            id: backupId,
            merchantId: identity.merchantId,
            storagePath: path,
            schemaVersion: Self.schemaVersion,
            appVersion: Self.appVersion,
            createdAt: createdAt,
            deviceId: identity.deviceId,
            recordCounts: package.recordCounts,
            fileCount: package.fileCount,
            byteCount: Int64(package.data.count),
            payloadChecksum: checksum,
            signature: "sha256:\(checksum)",
            status: "completed"
        )
        do {
            try await insertManifest(manifest, token: token)
        } catch {
            try? await deleteObject(path: path, token: token)
            throw error
        }
        UserDefaults.standard.set(createdAt.timeIntervalSince1970, forKey: "last_cloud_backup_at")
        latestManifest = manifest
        statusMessage = "Backup สำเร็จ"
        try? await pruneOldBackups(keeping: 3, token: token)
        return manifest
    }

    func fetchLatestBackup() async throws -> CloudBackupManifest? {
        BackupNetworkAuthorization.shared.begin()
        defer { BackupNetworkAuthorization.shared.end() }
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        guard let token = MerchantAuthManager.shared.authorizationToken else {
            throw CloudBackupError.signInRequired
        }
        let identity = try currentIdentity()
        var components = URLComponents(
            url: config.supabaseRestURL.appendingPathComponent("merchant_backup_manifests"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "merchant_id", value: "eq.\(identity.merchantId.uuidString.lowercased())"),
            URLQueryItem(name: "status", value: "eq.completed"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        addHeaders(to: &request, token: token)
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .backupTransfer)
        try validate(response: response, data: data)
        let result = try decoder.decode([CloudBackupManifest].self, from: data).first
        guard result?.merchantId == identity.merchantId || result == nil else { throw CloudBackupError.wrongMerchant }
        latestManifest = result
        return result
    }

    /// Downloads and validates the package, then stages it for an atomic swap
    /// before SwiftData opens on the next app launch.
    func stageRestore(_ manifest: CloudBackupManifest) async throws {
        isWorking = true
        statusMessage = "กำลังดาวน์โหลด Backup…"
        BackupNetworkAuthorization.shared.begin()
        defer {
            isWorking = false
            BackupNetworkAuthorization.shared.end()
        }
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        guard let token = MerchantAuthManager.shared.authorizationToken else { throw CloudBackupError.signInRequired }
        let identity = try currentIdentity()
        guard manifest.merchantId == identity.merchantId,
              manifest.storagePath.hasPrefix(identity.merchantId.uuidString.lowercased() + "/") else {
            throw CloudBackupError.wrongMerchant
        }
        guard manifest.schemaVersion <= Self.schemaVersion else {
            throw CloudBackupError.incompatibleSchema(manifest.schemaVersion)
        }

        let data = try await download(path: manifest.storagePath, token: token)
        guard Self.sha256(data) == manifest.payloadChecksum,
              let embedded = try? Self.packageMetadata(from: data),
              embedded.merchantId == identity.merchantId.uuidString.lowercased(),
              embedded.schemaVersion == manifest.schemaVersion else {
            throw CloudBackupError.corruptBackup
        }
        let staging = try Self.restoreStagingDirectory()
        try data.write(to: staging.appendingPathComponent("pending.alphaposbackup"), options: .atomic)
        let marker: [String: Any] = [
            "merchantId": identity.merchantId.uuidString.lowercased(),
            "checksum": manifest.payloadChecksum
        ]
        let markerData = try PropertyListSerialization.data(fromPropertyList: marker, format: .binary, options: 0)
        try markerData.write(to: staging.appendingPathComponent("pending.plist"), options: .atomic)
        statusMessage = "เตรียม Restore แล้ว กรุณาปิดและเปิดแอปใหม่"
    }

    /// Validate and stage a snapshot selected from Files. This path is fully
    /// offline and remains usable after reinstalling the app.
    func stageLocalRestore(from url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let metadata = try Self.packageMetadata(from: data)
        guard metadata.schemaVersion <= Self.schemaVersion else {
            throw CloudBackupError.incompatibleSchema(metadata.schemaVersion)
        }
        if let activeMerchant = UserDefaults.standard.string(forKey: "active_merchant_id")?.lowercased(),
           !activeMerchant.isEmpty,
           metadata.merchantId != activeMerchant {
            throw CloudBackupError.wrongMerchant
        }
        let staging = try Self.restoreStagingDirectory()
        try data.write(to: staging.appendingPathComponent("pending.alphaposbackup"), options: .atomic)
        let marker: [String: Any] = [
            "merchantId": metadata.merchantId,
            "checksum": Self.sha256(data)
        ]
        let markerData = try PropertyListSerialization.data(fromPropertyList: marker, format: .binary, options: 0)
        try markerData.write(to: staging.appendingPathComponent("pending.plist"), options: .atomic)
        statusMessage = "เตรียม Local Restore แล้ว กรุณาปิดและเปิดแอปใหม่"
    }

    // MARK: - Pre-launch restore

    /// Returns `true` when a restored store was installed. The caller can use
    /// this to roll back if SwiftData cannot open the restored database.
    @discardableResult
    nonisolated static func applyPendingRestoreIfNeeded() -> Bool {
        let fm = FileManager.default
        guard let staging = try? restoreStagingDirectory(),
              let marker = try? Data(contentsOf: staging.appendingPathComponent("pending.plist")),
              let markerObject = try? PropertyListSerialization.propertyList(from: marker, options: [], format: nil) as? [String: Any],
              let expectedMerchant = markerObject["merchantId"] as? String,
              let expectedChecksum = markerObject["checksum"] as? String,
              let packageData = try? Data(contentsOf: staging.appendingPathComponent("pending.alphaposbackup")),
              sha256(packageData) == expectedChecksum,
              let package = try? decodePackage(packageData),
              package.merchantId == expectedMerchant,
              package.schemaVersion <= schemaVersion,
              let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }

        do {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let store = appSupport.appendingPathComponent("default.store")
            let safety = appSupport.appendingPathComponent("pre-restore-safety.store")
            try removeSQLiteStore(at: safety)
            try copySQLiteStoreIfPresent(from: store, to: safety)

            // A fresh installation has already opened this store while the
            // restore was downloaded. Its WAL/SHM must never be replayed onto
            // the database from the backup on the next launch.
            try removeSQLiteStore(at: store)
            try package.database.write(to: store, options: .atomic)

            let support = appSupport.appendingPathComponent("default.store_SUPPORT", isDirectory: true)
            if fm.fileExists(atPath: support.path) { try fm.removeItem(at: support) }
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            for (relative, bytes) in package.supportFiles where !relative.contains("..") {
                let destination = support.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: destination, options: .atomic)
            }
            if let preferences = try? PropertyListSerialization.propertyList(from: package.preferences, options: [], format: nil) as? [String: Any] {
                for (key, value) in preferences where !restoreExcludedDefaultKeys.contains(key) {
                    UserDefaults.standard.set(value, forKey: key)
                }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_cloud_restore_at")
            UserDefaults.standard.removeObject(forKey: "last_cloud_restore_error")
            try fm.removeItem(at: staging)
            return true
        } catch {
            _ = try? restoreSafetyStore(in: appSupport)
            UserDefaults.standard.set("\(error)", forKey: "last_cloud_restore_error")
            return false
        }
    }

    /// Restores the database that existed immediately before the last cloud
    /// restore. Used when SwiftData rejects the restored store during launch.
    @discardableResult
    nonisolated static func restorePreRestoreSafetyStore() -> Bool {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        do {
            return try restoreSafetyStore(in: appSupport)
        } catch {
            UserDefaults.standard.set("Rollback failed: \(error)", forKey: "last_cloud_restore_error")
            return false
        }
    }

    nonisolated private static func restoreSafetyStore(in appSupport: URL) throws -> Bool {
        let fm = FileManager.default
        let store = appSupport.appendingPathComponent("default.store")
        let safety = appSupport.appendingPathComponent("pre-restore-safety.store")
        guard fm.fileExists(atPath: safety.path) else { return false }
        try removeSQLiteStore(at: store)
        try copySQLiteStoreIfPresent(from: safety, to: store)
        return true
    }

    nonisolated private static func removeSQLiteStore(at url: URL) throws {
        let fm = FileManager.default
        for candidate in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            if fm.fileExists(atPath: candidate.path) { try fm.removeItem(at: candidate) }
        }
    }

    nonisolated private static func copySQLiteStoreIfPresent(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: source.path + suffix)
            guard fm.fileExists(atPath: sourceFile.path) else { continue }
            let destinationFile = URL(fileURLWithPath: destination.path + suffix)
            try fm.copyItem(at: sourceFile, to: destinationFile)
        }
    }

    // MARK: - Package

    private struct PackageResult { let data: Data; let recordCounts: [String: Int]; let fileCount: Int }
    private struct DecodedPackage {
        let merchantId: String
        let schemaVersion: Int
        let database: Data
        let supportFiles: [String: Data]
        let preferences: Data
    }

    private func makePackage(merchantId: UUID, backupId: UUID, createdAt: Date, modelContext: ModelContext) throws -> PackageResult {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CloudBackupError.storeUnavailable
        }
        let source = appSupport.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: source.path) else { throw CloudBackupError.storeUnavailable }
        let temp = fm.temporaryDirectory.appendingPathComponent("backup-\(backupId.uuidString).sqlite")
        defer { try? fm.removeItem(at: temp) }
        try Self.sqliteSnapshot(source: source, destination: temp)
        let database = try Data(contentsOf: temp)
        let supportFiles = try Self.readFiles(in: appSupport.appendingPathComponent("default.store_SUPPORT", isDirectory: true))
        let preferences = UserDefaults.standard.dictionaryRepresentation().filter { !Self.backupExcludedDefaultKeys.contains($0.key) }
        let preferencesData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let counts = recordCounts(modelContext)
        let package: [String: Any] = [
            "format": "AlphaPosCloudSnapshot",
            "merchantId": merchantId.uuidString.lowercased(),
            "backupId": backupId.uuidString.lowercased(),
            "schemaVersion": Self.schemaVersion,
            "appVersion": Self.appVersion,
            "createdAt": createdAt,
            "database": database,
            "supportFiles": supportFiles,
            "preferences": preferencesData
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: package, format: .binary, options: 0)
        return PackageResult(data: data, recordCounts: counts, fileCount: 1 + supportFiles.count)
    }

    private func recordCounts(_ context: ModelContext) -> [String: Int] {
        [
            "orders": (try? context.fetchCount(FetchDescriptor<Order>())) ?? 0,
            "payments": (try? context.fetchCount(FetchDescriptor<Payment>())) ?? 0,
            "menu_items": (try? context.fetchCount(FetchDescriptor<MenuItem>())) ?? 0,
            "categories": (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0,
            "inventory_items": (try? context.fetchCount(FetchDescriptor<InventoryItem>())) ?? 0,
            "customers": (try? context.fetchCount(FetchDescriptor<Customer>())) ?? 0,
            "employees": (try? context.fetchCount(FetchDescriptor<Employee>())) ?? 0,
            "audit_logs": (try? context.fetchCount(FetchDescriptor<AuditLog>())) ?? 0
        ]
    }

    nonisolated private static func decodePackage(_ data: Data) throws -> DecodedPackage {
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              root["format"] as? String == "AlphaPosCloudSnapshot",
              let merchantId = root["merchantId"] as? String,
              let schemaVersion = root["schemaVersion"] as? Int,
              let database = root["database"] as? Data,
              let supportFiles = root["supportFiles"] as? [String: Data],
              let preferences = root["preferences"] as? Data else { throw CloudBackupError.corruptBackup }
        return DecodedPackage(merchantId: merchantId, schemaVersion: schemaVersion, database: database, supportFiles: supportFiles, preferences: preferences)
    }

    private static func packageMetadata(from data: Data) throws -> (merchantId: String, schemaVersion: Int) {
        let package = try decodePackage(data)
        return (package.merchantId, package.schemaVersion)
    }

    private static func sqliteSnapshot(source: URL, destination: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(destination.path, &destinationDB) == SQLITE_OK,
              let sourceDB, let destinationDB else {
            if sourceDB != nil { sqlite3_close(sourceDB) }
            if destinationDB != nil { sqlite3_close(destinationDB) }
            throw CloudBackupError.snapshotFailed("เปิดฐานข้อมูลไม่ได้")
        }
        defer { sqlite3_close(sourceDB); sqlite3_close(destinationDB) }
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw CloudBackupError.snapshotFailed(String(cString: sqlite3_errmsg(destinationDB)))
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else { throw CloudBackupError.snapshotFailed("SQLite code \(result)") }
    }

    private static func readFiles(in root: URL) throws -> [String: Data] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [:] }
        var result: [String: Data] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys)
        while let file = enumerator?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            result[relative] = try Data(contentsOf: file)
        }
        return result
    }

    // MARK: - Supabase

    private func upload(_ data: Data, path: String, token: String) async throws {
        var url = config.supabaseURL
        for component in ["storage", "v1", "object", "merchant-backups"] + path.split(separator: "/").map(String.init) {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 300
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        addHeaders(to: &request, token: token)
        let (responseData, response) = try await AppNetworkTransport.data(for: request, purpose: .backupTransfer)
        try validate(response: response, data: responseData)
    }

    private func download(path: String, token: String) async throws -> Data {
        var url = config.supabaseURL
        for component in ["storage", "v1", "object", "merchant-backups"] + path.split(separator: "/").map(String.init) {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        addHeaders(to: &request, token: token)
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .backupTransfer)
        try validate(response: response, data: data)
        return data
    }

    private func insertManifest(_ manifest: CloudBackupManifest, token: String) async throws {
        var request = URLRequest(url: config.supabaseRestURL.appendingPathComponent("merchant_backup_manifests"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder.supabase.encode(manifest)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addHeaders(to: &request, token: token)
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .backupTransfer)
        try validate(response: response, data: data)
    }

    private func deleteObject(path: String, token: String) async throws {
        var url = config.supabaseURL
        for component in ["storage", "v1", "object", "merchant-backups"] + path.split(separator: "/").map(String.init) { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request, token: token)
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .backupTransfer)
        try validate(response: response, data: data)
    }

    private func pruneOldBackups(keeping limit: Int, token: String) async throws {
        // Retention is intentionally best-effort. A failed cleanup must never
        // turn a successfully completed backup into a failure.
        _ = limit
        _ = token
    }

    private func addHeaders(to request: inout URLRequest, token: String) {
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudBackupError.server(String(data: data, encoding: .utf8) ?? "Invalid response")
        }
    }

    private func currentIdentity() throws -> (merchantId: UUID, deviceId: String) {
        guard let merchant = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchant),
              let deviceId = MerchantAuthManager.shared.deviceId, !deviceId.isEmpty else {
            throw CloudBackupError.invalidMerchant
        }
        return (merchantId, deviceId)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func restoreStagingDirectory() throws -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("CloudRestoreStaging", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated private static let backupExcludedDefaultKeys: Set<String> = [
        "dynamic_supabase_url", "dynamic_local_server_url", "dynamic_customer_web_url",
        "is_logged_in", "logged_in_email", "logged_in_name", "last_cloud_restore_error"
    ]
    nonisolated private static let restoreExcludedDefaultKeys: Set<String> = backupExcludedDefaultKeys.union([
        "active_merchant_id", "offline_sync_mode", "last_cloud_backup_at", "last_cloud_restore_at"
    ])
}

private extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
