import SwiftUI

struct TableSystemSettingsView: View {
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.tableSystem.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 14) {
                            Toggle(isOn: $enableTableSystem) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.TableSystem.enableTable.t)
                                        .foregroundColor(.textPrimary)
                                    Text(L.TableSystem.enableTableDesc.t)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: enableTableSystem) { APHaptic.trigger() }
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            Toggle(isOn: $enableWebOrdering) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.TableSystem.enableWebOrdering.t)
                                        .foregroundColor(.textPrimary)
                                    Text(L.TableSystem.enableWebDesc.t)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: enableWebOrdering) { APHaptic.trigger() }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.tableSystem.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
    }
}

#Preview {
    NavigationStack {
        TableSystemSettingsView()
    }
}
