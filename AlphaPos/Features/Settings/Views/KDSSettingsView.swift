import SwiftUI
import SwiftData

struct KDSSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // L-7: Category routing
    @AppStorage("kds_category_routing_json") private var kdsCategoryRoutingJson = "{}"
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var showingRoutingEditor = false
    // L-9: Physical KDS / Bump Bar
    @AppStorage("kds_keyboard_shortcuts_enabled") private var kdsKeyboardShortcutsEnabled = true

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
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)

                        VStack(spacing: 14) {
                            Toggle(isOn: $kdsShowKitchen) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kds_show_kitchen_toggle".t)
                                        .foregroundColor(.textPrimary)
                                    Text("kds_show_kitchen_desc".t)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .disabled(kdsShowKitchen && !kdsShowBar)
                            .onChange(of: kdsShowKitchen) { APHaptic.trigger() }

                            Divider()
                                .background(Color.appDivider)

                            Toggle(isOn: $kdsShowBar) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kds_show_bar_toggle".t)
                                        .foregroundColor(.textPrimary)
                                    Text("kds_show_bar_desc".t)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .disabled(kdsShowBar && !kdsShowKitchen)
                            .onChange(of: kdsShowBar) { APHaptic.trigger() }

                            Divider()
                                .background(Color.appDivider)

                            Toggle(isOn: $kitchenWorkflowRequired) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kitchen_workflow_required".t)
                                        .foregroundColor(.textPrimary)
                                    Text("kitchen_workflow_required_desc".t)
                                        .font(.system(size: 12))
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

                    // L-9: Physical KDS Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("kds_physical_section_title".t)
                            .font(.system(size: 12)).fontWeight(.bold)
                            .foregroundColor(.appAccent).tracking(1.0)

                        VStack(spacing: 0) {
                            Toggle(isOn: $kdsKeyboardShortcutsEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kds_keyboard_shortcuts_toggle".t)
                                        .foregroundColor(.textPrimary)
                                    Text("kds_keyboard_shortcuts_desc".t)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: kdsKeyboardShortcutsEnabled) { APHaptic.trigger() }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)

                }

                // L-7: Category Routing Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("kds_routing_section_title".t)
                        .font(.system(size: 12)).fontWeight(.bold)
                        .foregroundColor(.appAccent).tracking(1.0)

                    let routing = (try? JSONDecoder().decode(
                        [String: String].self,
                        from: kdsCategoryRoutingJson.data(using: .utf8) ?? Data()
                    )) ?? [:]

                    // De-duplicate by name for display — the local store may contain
                    // legacy duplicate categories (same name, different id) created by
                    // multiple seed/import paths. Hide categories with no active menu.
                    let uniqueCategories: [Category] = {
                        var seen = Set<String>()
                        var result: [Category] = []
                        for cat in categories.filter({
                            !$0.isDeleted && $0.menuItems.contains { !$0.isDeleted && $0.isAvailable }
                        })
                            .sorted(by: { ($0.isSynced ? 0 : 1, $0.updatedAt) < ($1.isSynced ? 0 : 1, $1.updatedAt) }) {
                            let key = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if seen.insert(key).inserted {
                                result.append(cat)
                            }
                        }
                        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    }()

                    if uniqueCategories.isEmpty {
                        Text("kds_no_categories_hint".t)
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                            .padding(10).background(Color.appSurfaceHigh).cornerRadius(8)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                Text("kds_default_route".t)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                routePicker(selection: Binding(
                                    get: { routing["*"] ?? "kitchen" },
                                    set: { saveRoute($0, for: "*", in: routing) }
                                ))
                            }
                            .padding(10)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(10)

                            ForEach(uniqueCategories) { cat in
                                HStack {
                                    Text(cat.name)
                                        .font(.system(size: 12)).foregroundColor(.textPrimary)
                                    Spacer()
                                    let categoryKey = cat.id.uuidString.lowercased()
                                    routePicker(selection: Binding(
                                        get: {
                                            routing[categoryKey]
                                                ?? routing[cat.name]
                                                ?? routing[cat.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
                                                ?? routing["*"]
                                                ?? "kitchen"
                                        },
                                        set: { saveRoute($0, for: categoryKey, in: routing) }
                                    ))
                                }
                                .padding(10)
                                .background(Color.appSurface)
                                .cornerRadius(10)
                            }
                        }
                    }

                    Text("kds_routing_hint".t)
                        .font(.system(size: 12)).foregroundColor(.textTertiary)
                }
                .padding(.horizontal)

            }
        }
        .navigationTitle(L.Sections.kds.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
    }

    private func saveRoute(_ route: String, for key: String, in routing: [String: String]) {
        var updated = routing
        updated[key] = route
        guard let data = try? JSONEncoder().encode(updated),
              let json = String(data: data, encoding: .utf8) else { return }
        kdsCategoryRoutingJson = json
        APHaptic.trigger()
    }

    private func routePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text("kds_route_kitchen".t).tag("kitchen")
                .disabled(!kdsShowKitchen)
            Text("kds_route_bar".t).tag("bar")
                .disabled(!kdsShowBar)
            Text("kds_route_both".t).tag("both")
                .disabled(!kdsShowKitchen || !kdsShowBar)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }
}

#Preview {
    NavigationStack {
        KDSSettingsView()
    }
}
