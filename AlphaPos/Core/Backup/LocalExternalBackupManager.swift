import CryptoKit
import Combine
import Foundation
import SQLite3
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum LocalExternalBackupError: LocalizedError {
    case destinationNotConfigured
    case destinationUnavailable
    case storeUnavailable
    case snapshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationNotConfigured: return "กรุณาเลือกโฟลเดอร์ Backup ในแอป Files ก่อนปิดกะ"
        case .destinationUnavailable: return "ไม่สามารถเข้าถึงโฟลเดอร์ Backup ที่เลือกไว้ กรุณาเลือกโฟลเดอร์ใหม่"
        case .storeUnavailable: return "ไม่พบฐานข้อมูล SwiftData สำหรับสำรองข้อมูล"
        case .snapshotFailed(let message): return "สร้าง Local Backup ไม่สำเร็จ: \(message)"
        }
    }
}

/// Writes snapshots to a user-selected Files folder. The folder is outside the
/// app container, so its files survive uninstalling AlphaPos.
@MainActor
final class LocalExternalBackupManager: ObservableObject {
    static let shared = LocalExternalBackupManager()

    @Published private(set) var lastBackupURL: URL?
    @Published private(set) var lastError: String?

    private let bookmarkKey = "local_external_backup_directory_bookmark"
    private let displayNameKey = "local_external_backup_directory_name"

    var configuredDirectoryName: String? {
        UserDefaults.standard.string(forKey: displayNameKey)
    }

    private init() {}

    func setDestination(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: displayNameKey)
        lastError = nil
    }

    @discardableResult
    func createShiftCloseBackup(modelContext: ModelContext, sessionID: UUID, closedAt: Date) throws -> URL {
        try modelContext.save()
        let destination = try resolvedDestination()
        let accessed = destination.startAccessingSecurityScopedResource()
        guard accessed else { throw LocalExternalBackupError.destinationUnavailable }
        defer { destination.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalExternalBackupError.storeUnavailable
        }
        let store = support.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: store.path) else { throw LocalExternalBackupError.storeUnavailable }

        let backupID = UUID()
        let temporaryStore = fm.temporaryDirectory.appendingPathComponent("local-backup-\(backupID).sqlite")
        defer { try? fm.removeItem(at: temporaryStore) }
        try Self.sqliteSnapshot(source: store, destination: temporaryStore)

        let database = try Data(contentsOf: temporaryStore)
        let supportFiles = try Self.readFiles(in: support.appendingPathComponent("default.store_SUPPORT", isDirectory: true))
        let preferences = UserDefaults.standard.dictionaryRepresentation().filter {
            !["is_logged_in", "logged_in_email", "logged_in_name"].contains($0.key)
        }
        let preferencesData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let merchantID = UserDefaults.standard.string(forKey: "active_merchant_id")?.lowercased() ?? "offline"
        let package: [String: Any] = [
            "format": "AlphaPosCloudSnapshot",
            "merchantId": merchantID,
            "backupId": backupID.uuidString.lowercased(),
            "schemaVersion": CloudBackupManager.schemaVersion,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "createdAt": closedAt,
            "sessionId": sessionID.uuidString.lowercased(),
            "database": database,
            "supportFiles": supportFiles,
            "preferences": preferencesData
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: package, format: .binary, options: 0)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "AlphaPos_ShiftClose_\(formatter.string(from: closedAt))_\(sessionID.uuidString.prefix(8)).alphaposbackup"
        let output = destination.appendingPathComponent(filename)
        try data.write(to: output, options: .atomic)
        lastBackupURL = output
        lastError = nil
        UserDefaults.standard.set(closedAt.timeIntervalSince1970, forKey: "last_local_external_backup_at")
        return output
    }

    private func resolvedDestination() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw LocalExternalBackupError.destinationNotConfigured
        }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale { try setDestination(url) }
        return url
    }

    private static func sqliteSnapshot(source: URL, destination: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(destination.path, &destinationDB) == SQLITE_OK,
              let sourceDB, let destinationDB else {
            if sourceDB != nil { sqlite3_close(sourceDB) }
            if destinationDB != nil { sqlite3_close(destinationDB) }
            throw LocalExternalBackupError.snapshotFailed("เปิดฐานข้อมูลไม่ได้")
        }
        defer { sqlite3_close(sourceDB); sqlite3_close(destinationDB) }
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw LocalExternalBackupError.snapshotFailed(String(cString: sqlite3_errmsg(destinationDB)))
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else {
            throw LocalExternalBackupError.snapshotFailed("SQLite code \(result)")
        }
    }

    private static func readFiles(in root: URL) throws -> [String: Data] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [:] }
        var result: [String: Data] = [:]
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            result[relative] = try Data(contentsOf: file)
        }
        return result
    }
}

struct BackupDirectoryPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct LocalBackupFilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType(filenameExtension: "alphaposbackup") ?? .data
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [type, .data])
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
