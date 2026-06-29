import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.appearance.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 14) {
                            // Dark Mode Toggle
                            Toggle(isOn: Binding(
                                get: { appTheme == AppTheme.dark.rawValue },
                                set: { isDark in selectTheme(isDark ? .dark : .light) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("dark_mode".t)
                                        .foregroundColor(.textPrimary)
                                    Text("dark_mode_desc".t)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .disabled(appTheme == AppTheme.system.rawValue)
                            .opacity(appTheme == AppTheme.system.rawValue ? 0.5 : 1.0)
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            // Follow System Toggle
                            Toggle(isOn: Binding(
                                get: { appTheme == AppTheme.system.rawValue },
                                set: { useSystem in selectTheme(useSystem ? .system : (appTheme == AppTheme.light.rawValue ? .light : .dark)) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("match_system_theme".t)
                                        .foregroundColor(.textPrimary)
                                    Text("match_system_theme_desc".t)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.appearance.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .apColorScheme()
    }
    
    private func selectTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.25)) {
            appTheme = theme.rawValue
            UserDefaults.standard.set(theme.rawValue, forKey: "app_theme")
        }
        APHaptic.trigger()
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
