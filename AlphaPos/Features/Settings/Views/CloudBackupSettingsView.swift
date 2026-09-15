import SwiftData
import SwiftUI

struct CloudBackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @ObservedObject private var manager = CloudBackupManager.shared
    @ObservedObject private var localManager = LocalExternalBackupManager.shared
    @AppStorage("last_cloud_backup_at") private var lastBackupTimestamp: Double = 0

    @State private var showBackupConfirmation = false
    @State private var restoreCandidate: CloudBackupManifest?
    @State private var showRestoreConfirmation = false
    @State private var showRestartNotice = false
    @State private var errorMessage: String?
    @State private var showDirectoryPicker = false
    @State private var showLocalRestorePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                localBackupCard
                warningCard
                statusCard
                actionCard

                if let manifest = manager.latestManifest {
                    manifestCard(manifest)
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showDirectoryPicker) {
            BackupDirectoryPicker { url in
                do {
                    try localManager.setDestination(url)
                    showDirectoryPicker = false
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showLocalRestorePicker) {
            LocalBackupFilePicker { url in
                do {
                    try manager.stageLocalRestore(from: url)
                    showLocalRestorePicker = false
                    showRestartNotice = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(text("สำรองข้อมูลไปยัง Cloud", "Back Up to Cloud"), isPresented: $showBackupConfirmation) {
            Button(text("เริ่ม Backup", "Start Backup")) { Task { await createBackup() } }
            Button(text("ยกเลิก", "Cancel"), role: .cancel) {}
        } message: {
            Text(text("ระบบจะเปิดอินเทอร์เน็ตเฉพาะช่องทาง Backup และกลับสู่โหมดออฟไลน์ทันทีเมื่อเสร็จ", "Internet access will be enabled only for the backup and disabled again when finished."))
        }
        .confirmationDialog(text("กู้คืนข้อมูลร้าน", "Restore Store Data"), isPresented: $showRestoreConfirmation) {
            Button(text("ดาวน์โหลดและเตรียม Restore", "Download and Prepare Restore"), role: .destructive) {
                if let restoreCandidate { Task { await stageRestore(restoreCandidate) } }
            }
            Button(text("ยกเลิก", "Cancel"), role: .cancel) {}
        } message: {
            Text(text("ระบบจะตรวจ merchantId, schema version และ checksum ก่อน และจะนำข้อมูลมาใช้เมื่อเปิดแอปครั้งถัดไป", "The merchant ID, schema version, and checksum will be verified before the data is applied on the next launch."))
        }
        .alert(text("ต้องเปิดแอปใหม่", "Restart Required"), isPresented: $showRestartNotice) {
            Button(text("ตกลง", "OK"), role: .cancel) {}
        } message: {
            Text(text("Restore ผ่านการตรวจสอบและถูกจัดเตรียมแล้ว กรุณาปิด AlphaPos จาก App Switcher แล้วเปิดใหม่", "The restore was verified and staged. Close AlphaPos from the App Switcher, then reopen it."))
        }
        .alert(text("ไม่สามารถดำเนินการได้", "Unable to Continue"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(text("ตกลง", "OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var localBackupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text("Backup ออฟไลน์ภายนอกแอป", "External Offline Backup"), systemImage: "externaldrive.fill.badge.checkmark")
                .font(.headline)
            Text(text("เมื่อปิดกะ ระบบจะบันทึก SwiftData snapshot ลงโฟลเดอร์ Files ที่เลือก ไฟล์ยังอยู่แม้ลบ AlphaPos", "When a shift closes, a SwiftData snapshot is saved to the selected Files folder and remains available even if AlphaPos is removed."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text("โฟลเดอร์ปลายทาง", "Destination Folder")).font(.caption).foregroundStyle(.secondary)
                    Text(localManager.configuredDirectoryName ?? text("ยังไม่ได้เลือก", "Not Selected"))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button(localManager.configuredDirectoryName == nil ? text("เลือกโฟลเดอร์", "Choose Folder") : text("เปลี่ยน", "Change")) {
                    showDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                showLocalRestorePicker = true
            } label: {
                Label(text("กู้คืนจากไฟล์ .alphaposbackup", "Restore from .alphaposbackup File"), systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.bordered)
            if let timestamp = UserDefaults.standard.object(forKey: "last_local_external_backup_at") as? Double {
                Text("\(text("Backup ล่าสุด", "Latest Backup")): \(Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(text("ข้อมูลออฟไลน์อยู่ในอุปกรณ์นี้", "Offline Data Is Stored on This Device"))
                    .font(.headline)
                Text(text("หากลบแอปก่อนทำ Backup ข้อมูลที่บันทึกเฉพาะในเครื่องจะสูญหายและไม่สามารถกู้คืนได้", "If the app is removed before a backup is created, device-only data will be permanently lost."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(text("Backup ล่าสุด", "Latest Backup"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastBackupText)
                    .font(.title3.bold())
                if let message = manager.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: lastBackupTimestamp > 0 ? "checkmark.icloud.fill" : "icloud.slash")
                .font(.system(size: 32))
                .foregroundStyle(lastBackupTimestamp > 0 ? Color.green : Color.orange)
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button { showBackupConfirmation = true } label: {
                Label(text("สำรองข้อมูลตอนนี้", "Back Up Now"), systemImage: "arrow.up.doc.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isWorking)

            Button { Task { await findBackup() } } label: {
                Label(text("ค้นหา Backup ของร้านนี้", "Find This Store's Backup"), systemImage: "arrow.clockwise.icloud")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(manager.isWorking)

            if manager.isWorking { ProgressView().padding(.top, 4) }
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func manifestCard(_ manifest: CloudBackupManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text("รายละเอียด Snapshot", "Snapshot Details")).font(.headline)
            detail(text("วันที่", "Date"), manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
            detail("App", manifest.appVersion)
            detail("Schema", "v\(manifest.schemaVersion)")
            detail(text("จำนวนข้อมูล", "Records"), "\(manifest.recordCounts.values.reduce(0, +))")
            detail(text("ขนาด", "Size"), ByteCountFormatter.string(fromByteCount: manifest.byteCount, countStyle: .file))

            Button(text("กู้คืน Snapshot นี้", "Restore This Snapshot")) {
                restoreCandidate = manifest
                showRestoreConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(manager.isWorking)
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }
            .font(.subheadline)
    }

    private var lastBackupText: String {
        guard lastBackupTimestamp > 0 else { return text("ยังไม่เคยสำรองข้อมูล", "No Backup Yet") }
        return Date(timeIntervalSince1970: lastBackupTimestamp).formatted(date: .abbreviated, time: .shortened)
    }

    private func createBackup() async {
        do { _ = try await manager.createBackup(modelContext: modelContext) }
        catch { errorMessage = error.localizedDescription }
    }

    private func findBackup() async {
        do {
            guard let found = try await manager.fetchLatestBackup() else {
                errorMessage = text("ไม่พบ Backup ออนไลน์ของร้านนี้", "No online backup was found for this store.")
                return
            }
            restoreCandidate = found
        } catch { errorMessage = error.localizedDescription }
    }

    private func stageRestore(_ manifest: CloudBackupManifest) async {
        do {
            try await manager.stageRestore(manifest)
            showRestartNotice = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func text(_ thai: String, _ english: String) -> String {
        lm.currentLanguage == .thai ? thai : english
    }
}
