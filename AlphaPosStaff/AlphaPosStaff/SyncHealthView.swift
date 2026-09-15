import SwiftUI

struct SyncHealthView: View {
    @State private var health: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("REST", value: NetworkService.shared.isOnline ? "Online" : "Offline")
                LabeledContent("Realtime", value: NetworkService.shared.isRealtimeConnected ? "Connected" : "Disconnected")
                LabeledContent("Queued orders", value: "\(OfflineCache.shared.queuedOrderCount)")
                LabeledContent("Manual retry required", value: "\(OfflineCache.shared.failedOrderCount)")
            }
            Section("Server sync health") {
                if isLoading { ProgressView() }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                ForEach(health.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: health[key] ?? "")
                }
            }
            Section("Recent request failures") {
                if NetworkDiagnostics.shared.recentFailures.isEmpty { Text("No recent failures") }
                ForEach(NetworkDiagnostics.shared.recentFailures.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(event.method) \(event.endpoint)").font(.subheadline.bold())
                        Text(event.error ?? "").font(.caption).foregroundStyle(.secondary)
                        Text(event.requestId).font(.caption2).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Sync Health")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await NetworkService.shared.fetchSyncHealth()
            health = result.reduce(into: [:]) { $0[$1.key] = String(describing: $1.value) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
