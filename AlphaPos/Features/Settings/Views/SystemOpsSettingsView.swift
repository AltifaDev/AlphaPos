import SwiftUI
import SwiftData

struct SystemOpsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var statusMessage = ""
    @State private var showingStatusAlert = false
    @State private var showingResetConfirmAlert = false
    @State private var isResettingTransactions = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.systemOps.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 12) {
                            Button(action: forceReSeedData) {
                                Label("Re-Seed Sample Restaurant Data", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.appAccent)
                            
                            Button(action: clearLocalCache) {
                                Label("Clear Database Cache (Reset)", systemImage: "trash.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.appRose)
                            
                            Button(action: { showingResetConfirmAlert = true }) {
                                if isResettingTransactions {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Reset Store Transactions & Sessions", systemImage: "arrow.counterclockwise.circle.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.appRose)
                            .disabled(isResettingTransactions)
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.systemOps.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .alert("Database Operation", isPresented: $showingStatusAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
        .alert("Wipe Transactions & Sessions?", isPresented: $showingResetConfirmAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Wipe Transactions", role: .destructive) {
                performStoreTransactionsReset()
            }
        } message: {
            Text("This will delete all active table sessions, orders, payments, and service requests from both this local device and Supabase. Menu items, categories, and employees will remain untouched.")
        }
    }
    
    private func forceReSeedData() {
        APHaptic.trigger()
        
        SampleDataSeeder.seedAll(modelContext: modelContext)
        
        statusMessage = "All sample restaurant data, tables, and menus have been seeded successfully."
        showingStatusAlert = true
        
        // Immediately sync seeded data to Supabase
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    private func clearLocalCache() {
        APHaptic.trigger()
        
        // Fetch and delete all tables & orders
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for table in tables { modelContext.delete(table) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for order in orders { modelContext.delete(order) }
        }
        if let categories = try? modelContext.fetch(FetchDescriptor<Category>()) {
            for cat in categories { modelContext.delete(cat) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<MenuItem>()) {
            for item in items { modelContext.delete(item) }
        }
        
        try? modelContext.save()
        
        statusMessage = "Local database cache has been cleared and reset."
        showingStatusAlert = true
    }
    
    private func wipeLocalTransactionsAndSessions() {
        if let sessions = try? modelContext.fetch(FetchDescriptor<TableSession>()) {
            for session in sessions { modelContext.delete(session) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for order in orders { modelContext.delete(order) }
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<Payment>()) {
            for payment in payments { modelContext.delete(payment) }
        }
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for table in tables {
                table.status = "vacant"
            }
        }
        try? modelContext.save()
    }
    
    private func performStoreTransactionsReset() {
        APHaptic.trigger()
        isResettingTransactions = true
        
        Task {
            do {
                // 1. Wipe remote transactions from Supabase
                _ = try await NetworkManager.shared.wipeRemoteTransactionsAndSessions()
                
                // 2. Wipe local transactional data
                await MainActor.run {
                    wipeLocalTransactionsAndSessions()
                    isResettingTransactions = false
                    statusMessage = "All active sessions, orders, and payments have been wiped from both server and local device. Tables have been reset to vacant."
                    showingStatusAlert = true
                }
            } catch {
                await MainActor.run {
                    isResettingTransactions = false
                    statusMessage = "Reset failed: \(error.localizedDescription)"
                    showingStatusAlert = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SystemOpsSettingsView()
    }
}
