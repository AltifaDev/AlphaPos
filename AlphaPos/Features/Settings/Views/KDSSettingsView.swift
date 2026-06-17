import SwiftUI
import SwiftData

struct KDSSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    @AppStorage("kitchen_workflow_required") private var kitchenWorkflowRequired = true
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.kds.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 14) {
                            Toggle(isOn: $kdsShowKitchen) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Display Kitchen Food Items") // or L translation if exists
                                        .foregroundColor(.textPrimary)
                                    Text("Show food, appetizers, and desserts on this device.")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: kdsShowKitchen) { APHaptic.trigger() }
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            Toggle(isOn: $kdsShowBar) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Display Drink Bar Items")
                                        .foregroundColor(.textPrimary)
                                    Text("Show beverages, juices, and bar drinks on this device.")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: kdsShowBar) { APHaptic.trigger() }
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            Toggle(isOn: $kitchenWorkflowRequired) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Kitchen Workflow Required")
                                        .foregroundColor(.textPrimary)
                                    Text("When enabled, all items must be served by kitchen/bar before checkout is allowed. Disable to skip kitchen confirmation.")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: kitchenWorkflowRequired) {
                                APHaptic.trigger()
                                Task {
                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.kds.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
    }
}

#Preview {
    NavigationStack {
        KDSSettingsView()
    }
}
