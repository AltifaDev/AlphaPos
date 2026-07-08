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

                    // L-9: Physical KDS Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("kds_physical_section_title".t)
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.appAccent).tracking(1.0)

                        VStack(spacing: 0) {
                            Toggle(isOn: $kdsKeyboardShortcutsEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("kds_keyboard_shortcuts_toggle".t)
                                        .foregroundColor(.textPrimary)
                                    Text("kds_keyboard_shortcuts_desc".t)
                                        .font(.caption2)
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
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.appAccent).tracking(1.0)

                    let routing = (try? JSONDecoder().decode(
                        [String: String].self,
                        from: kdsCategoryRoutingJson.data(using: .utf8) ?? Data()
                    )) ?? [:]

                    if categories.filter({ !$0.isDeleted }).isEmpty {
                        Text("kds_no_categories_hint".t)
                            .font(.caption2).foregroundColor(.textTertiary)
                            .padding(10).background(Color.appSurfaceHigh).cornerRadius(8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(categories.filter { !$0.isDeleted }) { cat in
                                HStack {
                                    Text(cat.name)
                                        .font(.subheadline).foregroundColor(.textPrimary)
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { routing[cat.name] ?? "kitchen" },
                                        set: { newVal in
                                            var updated = routing
                                            updated[cat.name] = newVal
                                            if let data = try? JSONEncoder().encode(updated),
                                               let str = String(data: data, encoding: .utf8) {
                                                kdsCategoryRoutingJson = str
                                            }
                                            APHaptic.trigger()
                                        }
                                    )) {
                                        Text("kds_route_kitchen".t).tag("kitchen")
                                        Text("kds_route_bar".t).tag("bar")
                                        Text("kds_route_both".t).tag("both")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)
                                }
                                .padding(10)
                                .background(Color.appSurface)
                                .cornerRadius(10)
                            }
                        }
                    }

                    Text("kds_routing_hint".t)
                        .font(.caption2).foregroundColor(.textTertiary)
                }
                .padding(.horizontal)

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
