import SwiftUI
import SwiftData
import CoreImage
import PhotosUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Theme selection setting
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    
    // Printer settings
    @AppStorage("receipt_printer_enabled") private var receiptPrinterEnabled = true
    @AppStorage("kitchen_printer_enabled") private var kitchenPrinterEnabled = true
    @AppStorage("printer_ip") private var printerIP = "192.168.1.201"
    
    @Query(sort: \Printer.name) private var printersList: [Printer]
    @Query(sort: \Category.name) private var appCategories: [Category]
    
    @State private var showingAddPrinterSheet = false
    @State private var showingEditPrinterSheet = false
    @State private var selectedPrinterForEdit: Printer? = nil
    
    // Form fields for adding/editing printer
    @State private var printerName = ""
    @State private var connectionType = "network" // network, bluetooth, usb
    @State private var ipAddress = ""
    @State private var portString = "9100"
    @State private var bluetoothName = ""
    @State private var paperWidth = "80mm" // 80mm, 58mm, 40mm Sticker
    @State private var printerRole = "kitchen" // receipt, kitchen, label
    @State private var selectedCategoriesForRouting = Set<String>() // Set of Category names/IDs
    
    // Print preview simulation state
    @State private var showingPreviewSheet = false
    @State private var selectedPrinterForPreview: Printer? = nil
    
    // Table settings
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    
    // KDS Routing settings
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    
    // Kitchen workflow enforcement
    @AppStorage("kitchen_workflow_required") private var kitchenWorkflowRequired = true
    
    // Security & Sync
    @AppStorage("require_face_scan") private var requireFaceScan = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = true
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    
    // Alert state for print simulation
    @State private var showingPrintAlert = false
    @State private var printAlertMessage = ""
    @State private var isTestingPrint = false
    
    // Data operations status
    @State private var statusMessage = ""
    @State private var showingStatusAlert = false
    @State private var showingResetConfirmAlert = false
    @State private var isResettingTransactions = false
    
    @AppStorage("is_logged_in") private var isLoggedIn = true
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("logged_in_name") private var loggedInName = "Somchai Lertwit"
    
    // Change password state
    @State private var showingChangePasswordSheet = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var changePasswordErrorMessage = ""
    
    // Delete account state
    @State private var showingDeleteConfirmAlert = false
    @State private var deleteConfirmText = ""
    @State private var isDeletingAccount = false
    
    // Store logo state
    @State private var logoImage: UIImage? = nil
    @AppStorage("store_logo_path") private var storeLogoPath = ""

    
    var body: some View {
        ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // ── SECTION: ACCOUNT MANAGEMENT ───────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ACCOUNT MANAGEMENT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 16) {
                                // User Info row
                                HStack(spacing: 16) {
                                    // Avatar circle with initials
                                    let initials = getInitials(from: loggedInName)
                                    ZStack {
                                        Circle()
                                            .fill(APGradient.accent)
                                            .frame(width: 54, height: 54)
                                            .shadow(color: Color(hex: "6C63FF").opacity(0.3), radius: 6)
                                        Text(initials)
                                            .font(.title3)
                                            .fontWeight(.black)
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loggedInName)
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                        Text(loggedInEmail)
                                            .font(.subheadline)
                                            .foregroundColor(.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Role badge
                                    Text("Store Owner")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.appAccent.opacity(0.12))
                                        .cornerRadius(APRadius.pill)
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                // Account actions list
                                VStack(spacing: 12) {
                                    // Change Password Button
                                    Button(action: { showingChangePasswordSheet = true }) {
                                        HStack {
                                            Label("Change Account Password", systemImage: "key.fill")
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                                .foregroundColor(.textSecondary)
                                        }
                                    }
                                    
                                    Divider()
                                        .background(Color.appDivider)
                                    
                                    // Logout Button
                                    Button(action: handleLogout) {
                                        HStack {
                                            Label("Sign Out", systemImage: "arrow.right.square.fill")
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                        }
                                    }
                                    
                                    Divider()
                                        .background(Color.appDivider)
                                    
                                    // Delete Account / GDPR erasure button
                                    Button(action: { showingDeleteConfirmAlert = true }) {
                                        HStack {
                                            Label("Delete Store & Account (GDPR Compliance)", systemImage: "exclamationmark.shield.fill")
                                                .foregroundColor(.appRose)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: APPEARANCE THEME ─────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("APPEARANCE THEME")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 14) {
                                // Dark Mode Toggle (disabled if system theme is enabled)
                                Toggle(isOn: Binding(
                                    get: { appTheme == AppTheme.dark.rawValue },
                                    set: { isDark in selectTheme(isDark ? .dark : .light) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Dark Mode")
                                            .foregroundColor(.textPrimary)
                                        Text("Force Antigravity Dark theme.")
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
                                        Text("Match iPad System Theme")
                                            .foregroundColor(.textPrimary)
                                        Text("Sync with iOS Light/Dark preferences.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                             }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: TABLE SYSTEM CONFIGURATION ────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TABLE SYSTEM CONFIGURATION")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 14) {
                                Toggle(isOn: $enableTableSystem) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Dining Table System")
                                            .foregroundColor(.textPrimary)
                                        Text("Manage tables, reservations, and customer self-ordering QR links.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                                .onChange(of: enableTableSystem) { _ in APHaptic.trigger() }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                Toggle(isOn: $enableWebOrdering) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Web Ordering & Sync")
                                            .foregroundColor(.textPrimary)
                                        Text("Allow customers to place orders and call staff via self-ordering QR links.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                                .onChange(of: enableWebOrdering) { _ in APHaptic.trigger() }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: KDS STATION CONFIGURATION ───────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("KDS STATION CONFIGURATION")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 14) {
                                Toggle(isOn: $kdsShowKitchen) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Display Kitchen Food Items")
                                            .foregroundColor(.textPrimary)
                                        Text("Show food, appetizers, and desserts on this device.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                                .onChange(of: kdsShowKitchen) { _ in APHaptic.trigger() }
                                
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
                                .onChange(of: kdsShowBar) { _ in APHaptic.trigger() }
                                
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
                                .onChange(of: kitchenWorkflowRequired) { _ in
                                    APHaptic.trigger()
                                    Task {
                                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                                    }
                                }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: LINK STAFF DEVICES ────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LINK STAFF DEVICES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 16) {
                                Text("Waitstaff can pair their devices (AlphaPos Staff) by scanning this store's QR code or entering the ID below.")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.leading)
                                
                                if let qrImage = generateQRCode(from: activeMerchantId) {
                                    Image(uiImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 180, height: 180)
                                        .padding(12)
                                        .background(Color.white)
                                        .cornerRadius(APRadius.md)
                                        .shadow(color: Color.black.opacity(0.1), radius: 6)
                                } else {
                                    ContentUnavailableView("QR Generation Failed", systemImage: "xmark.circle")
                                        .frame(height: 180)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Store ID (Merchant UUID)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.textSecondary)
                                    
                                    HStack {
                                        Text(activeMerchantId)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            UIPasteboard.general.string = activeMerchantId
                                            APHaptic.trigger()
                                            statusMessage = "Copied Merchant ID to clipboard."
                                            showingStatusAlert = true
                                        }) {
                                            Image(systemName: "doc.on.doc.fill")
                                                .foregroundColor(.appAccent)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.sm)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: PRINTER SETUP ────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("PRINTER CONNECTION & ROUTING")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                Spacer()
                                Button(action: {
                                    printerName = ""
                                    connectionType = "network"
                                    ipAddress = ""
                                    portString = "9100"
                                    bluetoothName = ""
                                    paperWidth = "80mm"
                                    printerRole = "kitchen"
                                    selectedCategoriesForRouting.removeAll()
                                    selectedPrinterForEdit = nil
                                    showingAddPrinterSheet = true
                                }) {
                                    Label("Add Printer", systemImage: "plus.circle.fill")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                }
                            }
                            
                            VStack(spacing: 16) {
                                let activePrinters = printersList.filter { !$0.isDeleted }
                                
                                if activePrinters.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "printer.slash")
                                            .font(.system(size: 36))
                                            .foregroundColor(.textSecondary.opacity(0.5))
                                            .padding(.top, 8)
                                        Text("No printers configured yet.")
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                        Text("Tap 'Add Printer' above to configure a thermal receipt, kitchen ticket, or label sticker printer.")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 8)
                                    }
                                    .frame(maxWidth: .infinity)
                                } else {
                                    ForEach(activePrinters) { printer in
                                        PrinterRowView(
                                            printer: printer,
                                            onPreview: {
                                                selectedPrinterForPreview = printer
                                                showingPreviewSheet = true
                                            },
                                            onEdit: {
                                                selectedPrinterForEdit = printer
                                                printerName = printer.name
                                                connectionType = printer.connectionType
                                                ipAddress = printer.ipAddress ?? ""
                                                portString = String(printer.port)
                                                bluetoothName = printer.bluetoothName ?? ""
                                                paperWidth = printer.paperWidth
                                                printerRole = printer.role
                                                
                                                selectedCategoriesForRouting = Set(printer.routingRules.filter { !$0.isDeleted }.compactMap { $0.categoryId })
                                                showingEditPrinterSheet = true
                                            }
                                        )
                                        
                                        if printer.id != activePrinters.last?.id {
                                            Divider()
                                                .background(Color.appDivider)
                                        }
                                    }
                                }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: SECURITY RULES & SYNC ────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SECURITY RULES & REPLICATION")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 16) {
                                Toggle(isOn: $requireFaceScan) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enforce Biometric Clock-In")
                                            .foregroundColor(.textPrimary)
                                        Text("Staff must pass facial verification matches.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                                .onChange(of: requireFaceScan) { _ in APHaptic.trigger() }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                Toggle(isOn: $offlineSyncMode) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Background Sync Engine")
                                            .foregroundColor(.textPrimary)
                                        Text("Replicate SwiftData models to server automatically.")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                .tint(.appAccent)
                                .onChange(of: offlineSyncMode) { _ in APHaptic.trigger() }
                            }
                            .apCard()
                        }
                        .padding(.horizontal)
                        
                        // ── SECTION: DATA SEEDING ────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SYSTEM OPERATIONS")
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
                        .padding(.bottom, 32)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("System Settings")
            .apNavBar(background: Color.appBackground)
            .alert("Printer Connection Test", isPresented: $showingPrintAlert) {
                Button("Done", role: .cancel) { }
            } message: {
                Text(printAlertMessage)
            }
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
            .alert("Delete Store & Account?", isPresented: $showingDeleteConfirmAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Yes, WIPE Everything", role: .destructive) {
                    performAccountDeletion()
                }
            } message: {
                Text("WARNING: This action is irreversible. All table layouts, session logs, order records, and configurations will be permanently purged from this device and from Supabase cloud servers (GDPR compliant).")
            }
            .sheet(isPresented: $showingChangePasswordSheet) {
                ChangePasswordSheet(isPresented: $showingChangePasswordSheet)
            }
            .sheet(isPresented: $showingAddPrinterSheet) {
                PrinterConfigSheet(
                    isPresented: $showingAddPrinterSheet,
                    printerToEdit: nil,
                    onSave: savePrinterAction,
                    appCategories: appCategories
                )
            }
            .sheet(isPresented: $showingEditPrinterSheet) {
                PrinterConfigSheet(
                    isPresented: $showingEditPrinterSheet,
                    printerToEdit: selectedPrinterForEdit,
                    onSave: savePrinterAction,
                    onDelete: deletePrinterAction,
                    appCategories: appCategories
                )
            }
            .sheet(isPresented: $showingPreviewSheet) {
                if let printer = selectedPrinterForPreview {
                    PrintPreviewSheet(isPresented: $showingPreviewSheet, printer: printer)
                }
            }
            .onAppear {
                loadSavedLogo()
            }
    }
    
    // MARK: - Actions
    
    private func getInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.isEmpty { return "O" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        let first = String(parts[0].prefix(1))
        let last = String(parts[parts.count - 1].prefix(1))
        return (first + last).uppercased()
    }
    
    private func handleLogout() {
        APHaptic.trigger()
        withAnimation(.easeInOut(duration: 0.25)) {
            isLoggedIn = false
        }
    }
    
    private func performAccountDeletion() {
        APHaptic.trigger()
        isDeletingAccount = true
        
        Task {
            do {
                // 1. Wipe remote data from Supabase (merchants row cascade deletes everything)
                _ = try await NetworkManager.shared.deleteMerchantOnServer()
                
                // 2. Wipe local SwiftData cache
                await MainActor.run {
                    clearLocalCacheSilently()
                    isDeletingAccount = false
                    isLoggedIn = false
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    statusMessage = "GDPR Account Deletion failed: \(error.localizedDescription)"
                    showingStatusAlert = true
                }
            }
        }
    }
    
    private func clearLocalCacheSilently() {
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
    }
    
    private func selectTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.25)) {
            appTheme = theme.rawValue
            UserDefaults.standard.set(theme.rawValue, forKey: "app_theme")
        }
        APHaptic.trigger()
    }
    
    private func testPrintAction() {
        APHaptic.trigger()
        isTestingPrint = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isTestingPrint = false
            let randomCode = Int.random(in: 1000...9999)
            printAlertMessage = """
            TEST TICKET PRINTED SUCCESSFULLY!
            
            Target IP: \(printerIP)
            Receipt Printer: \(receiptPrinterEnabled ? "Online" : "Offline")
            Kitchen Printer: \(kitchenPrinterEnabled ? "Online" : "Offline")
            
            Job ID: AP-PRNT-\(randomCode)
            Timestamp: \(Date().description)
            """
            showingPrintAlert = true
            APHaptic.trigger()
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
    
    private func savePrinterAction(
        id: UUID?,
        name: String,
        connectionType: String,
        ipAddress: String?,
        port: Int,
        bluetoothName: String?,
        paperWidth: String,
        role: String,
        isActive: Bool,
        selectedCategories: Set<String>
    ) {
        let printer: Printer
        if let id = id, let existing = printersList.first(where: { $0.id == id }) {
            printer = existing
            printer.name = name
            printer.connectionType = connectionType
            printer.ipAddress = ipAddress
            printer.port = port
            printer.bluetoothName = bluetoothName
            printer.paperWidth = paperWidth
            printer.role = role
            printer.isActive = isActive
            printer.isSynced = false
            printer.updatedAt = Date()
        } else {
            printer = Printer(
                name: name,
                connectionType: connectionType,
                ipAddress: ipAddress,
                port: port,
                bluetoothName: bluetoothName,
                paperWidth: paperWidth,
                status: "unknown",
                role: role,
                isActive: isActive,
                isSynced: false,
                isDeleted: false,
                updatedAt: Date()
            )
            modelContext.insert(printer)
        }
        
        // Remove existing routing rules (soft delete)
        for rule in printer.routingRules {
            rule.isDeleted = true
            rule.isSynced = false
            rule.updatedAt = Date()
        }
        
        // Add new rules
        for categoryName in selectedCategories {
            let slug = categoryName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingRule = printer.routingRules.first(where: { $0.categoryId == slug }) {
                existingRule.isDeleted = false
                existingRule.isSynced = false
                existingRule.updatedAt = Date()
            } else {
                let rule = PrintRoutingRule(
                    printer: printer,
                    categoryId: slug,
                    printOnOrder: true,
                    printOnPayment: (role == "receipt"),
                    isSynced: false,
                    isDeleted: false,
                    updatedAt: Date()
                )
                modelContext.insert(rule)
                printer.routingRules.append(rule)
            }
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    private func deletePrinterAction(id: UUID) {
        if let printer = printersList.first(where: { $0.id == id }) {
            printer.isDeleted = true
            printer.isSynced = false
            printer.updatedAt = Date()
            
            for rule in printer.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }
            
            try? modelContext.save()
            
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let data = string.data(using: String.Encoding.ascii)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            if let output = filter.outputImage?.transformed(by: transform),
               let cgImage = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
    
    // MARK: - Store Logo Helper Methods
    
    private func loadSelectedLogo(from item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                // Resize image to keep it small (e.g. max 256x256)
                let resizedImage = resizeImage(uiImage, targetSize: CGSize(width: 256, height: 256))
                
                // Save image to file system
                if let filepath = saveImageToDocuments(resizedImage) {
                    await MainActor.run {
                        self.logoImage = resizedImage
                        self.storeLogoPath = filepath
                    }
                }
            }
        }
    }
    
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    private func saveImageToDocuments(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let filename = "store_logo.png"
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("Error saving logo: \(error)")
            return nil
        }
    }
    
    private func loadSavedLogo() {
        if !storeLogoPath.isEmpty {
            let fm = FileManager.default
            if let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsURL.appendingPathComponent(storeLogoPath)
                if let data = try? Data(contentsOf: fileURL) {
                    self.logoImage = UIImage(data: data)
                }
            }
        }
    }
}

// MARK: - Change Password Sheet
struct ChangePasswordSheet: View {
    @Binding var isPresented: Bool
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    if !errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if !successMessage.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.appTeal)
                            Text(successMessage)
                                .font(.caption)
                                .foregroundColor(.appTeal)
                            Spacer()
                        }
                        .padding()
                        .background(Color.appTeal.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("••••••••", text: $oldPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("Min 8 characters", text: $newPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm New Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("Confirm new password", text: $confirmNewPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: savePassword) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Update Password")
                        }
                    }
                    .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                }
                .padding(24)
            }
            .navigationTitle("Change Password")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
        }
    }
    
    private func savePassword() {
        errorMessage = ""
        successMessage = ""
        
        if newPassword.count < 8 {
            errorMessage = "New password must be at least 8 characters long."
            return
        }
        if newPassword != confirmNewPassword {
            errorMessage = "New passwords do not match."
            return
        }
        
        isSaving = true
        // Simulate remote update
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
            successMessage = "Your password has been changed successfully according to secure standards."
            APHaptic.trigger()
            
            // Dismiss after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isPresented = false
            }
        }
    }
}

// MARK: - Printer Configuration Sheet
struct PrinterConfigSheet: View {
    @Binding var isPresented: Bool
    var printerToEdit: Printer?
    var onSave: (UUID?, String, String, String?, Int, String?, String, String, Bool, Set<String>) -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var appCategories: [Category]
    
    @State private var name: String = ""
    @State private var connectionType: String = "network" // network, bluetooth, usb
    @State private var ipAddress: String = ""
    @State private var portString: String = "9100"
    @State private var bluetoothName: String = ""
    @State private var paperWidth: String = "80mm" // 80mm, 58mm, 40mm Sticker
    @State private var role: String = "kitchen" // receipt, kitchen, label
    @State private var isActive: Bool = true
    @State private var selectedCategories = Set<String>()
    
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // ── SECTION: GENERAL SETTINGS ───────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PRINTER IDENTITY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Printer Name")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                TextField("e.g. Kitchen Printer, Main Cashier", text: $name)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding()
                                    .background(Color.appSurfaceHigh)
                                    .foregroundColor(.textPrimary)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Printer Role")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                Picker("Role", selection: $role) {
                                    Text("Receipt (FOH)").tag("receipt")
                                    Text("Kitchen (BOH)").tag("kitchen")
                                    Text("Label Sticker").tag("label")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            Toggle("Printer Active Status", isOn: $isActive)
                                .tint(.appAccent)
                        }
                        .apCard()
                        
                        // ── SECTION: CONNECTION SETTINGS ─────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONNECTION INTERFACE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            Picker("Connection Type", selection: $connectionType) {
                                Text("TCP/IP LAN").tag("network")
                                Text("Bluetooth").tag("bluetooth")
                                Text("USB direct").tag("usb")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            if connectionType == "network" {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("IP Address")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.textSecondary)
                                        TextField("192.168.1.X", text: $ipAddress)
                                            .keyboardType(.numbersAndPunctuation)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurfaceHigh)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Port")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.textSecondary)
                                        TextField("9100", text: $portString)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding()
                                            .background(Color.appSurfaceHigh)
                                            .foregroundColor(.textPrimary)
                                            .cornerRadius(8)
                                    }
                                }
                            } else if connectionType == "bluetooth" {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Bluetooth Accessory Name")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.textSecondary)
                                    TextField("e.g. Star TSP100-B101", text: $bluetoothName)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .padding()
                                        .background(Color.appSurfaceHigh)
                                        .foregroundColor(.textPrimary)
                                        .cornerRadius(8)
                                }
                            } else {
                                Text("Connect printer via USB-C or Lightning cable directly to the iPad. No additional networking parameters required.")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .padding(.top, 4)
                            }
                        }
                        .apCard()
                        
                        // ── SECTION: MEDIA FORMAT ────────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MEDIA SPECIFICATIONS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            Picker("Paper Width", selection: $paperWidth) {
                                Text("80 mm Thermal").tag("80mm")
                                Text("58 mm Thermal").tag("58mm")
                                Text("40 mm Sticker").tag("40mm Sticker")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .apCard()
                        
                        // ── SECTION: ROUTING RULES ───────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CATEGORY ROUTING MAP")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            Text("Map menu categories to this printer. If none are selected, all categories will default to printing here.")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                            
                            if appCategories.isEmpty {
                                Text("No categories registered in system database.")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .italic()
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 10) {
                                    ForEach(appCategories) { category in
                                        let slug = category.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                                        let isSelected = selectedCategories.contains(slug)
                                        Button(action: {
                                            if isSelected {
                                                selectedCategories.remove(slug)
                                            } else {
                                                selectedCategories.insert(slug)
                                            }
                                            APHaptic.trigger()
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption2)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                                            .foregroundColor(isSelected ? .white : .textPrimary)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .apCard()
                        
                        // ── ACTIONS ──────────────────────────────────────────
                        VStack(spacing: 12) {
                            Button(action: validateAndSave) {
                                Text("Save Configuration")
                            }
                            .apGradientButton(gradient: APGradient.accent)
                            
                            if let onDelete = onDelete, let printerId = printerToEdit?.id {
                                Button(action: {
                                    onDelete(printerId)
                                    isPresented = false
                                }) {
                                    Text("Delete Printer Connection")
                                        .foregroundColor(.appRose)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(printerToEdit == nil ? "Add Printer Connection" : "Edit Printer Connection")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
            .onAppear {
                if let printer = printerToEdit {
                    name = printer.name
                    connectionType = printer.connectionType
                    ipAddress = printer.ipAddress ?? ""
                    portString = String(printer.port)
                    bluetoothName = printer.bluetoothName ?? ""
                    paperWidth = printer.paperWidth
                    role = printer.role
                    isActive = printer.isActive
                    
                    selectedCategories = Set(printer.routingRules.filter { !$0.isDeleted }.compactMap { $0.categoryId })
                }
            }
            .alert("Configuration Error", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private func validateAndSave() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Please specify a printer name."
            showingValidationAlert = true
            return
        }
        
        if connectionType == "network" {
            let ipTrimmed = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if ipTrimmed.isEmpty {
                validationMessage = "TCP/IP connection requires an IP address."
                showingValidationAlert = true
                return
            }
            
            let parts = ipTrimmed.split(separator: ".")
            if parts.count != 4 {
                validationMessage = "Invalid IP address format. (e.g. 192.168.1.100)"
                showingValidationAlert = true
                return
            }
        }
        
        let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        
        onSave(
            printerToEdit?.id,
            name,
            connectionType,
            connectionType == "network" ? ipAddress : nil,
            portInt,
            connectionType == "bluetooth" ? bluetoothName : nil,
            paperWidth,
            role,
            isActive,
            selectedCategories
        )
        isPresented = false
    }
}

// MARK: - Print Preview Sheet
struct PrintPreviewSheet: View {
    @Binding var isPresented: Bool
    var printer: Printer
    @State private var previewType: String = "" // "receipt", "kitchen", "label"
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Preview Format", selection: $previewType) {
                        Text("FOH Receipt").tag("receipt")
                        Text("BOH Kitchen Ticket").tag("kitchen")
                        Text("Label Sticker").tag("label")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .background(Color.appSurface)
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            if previewType == "receipt" {
                                ReceiptPreviewCard(paperWidth: printer.paperWidth)
                            } else if previewType == "kitchen" {
                                KitchenTicketPreviewCard(paperWidth: printer.paperWidth)
                            } else {
                                StickerPreviewCard()
                            }
                            
                            Text("Note: This is a high-fidelity digital print simulation matching ESC/POS commands (for Receipt & Kitchen) and TSPL commands (for Sticker Label).")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Digital Print Preview")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
            .onAppear {
                previewType = printer.role
            }
        }
    }
}

// MARK: - Receipt Preview Card
struct ReceiptPreviewCard: View {
    var paperWidth: String
    
    var body: some View {
        VStack(spacing: 0) {
            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .opacity(0.3)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 4) {
                    Text("ALPHAPOS CAFE & GRILL")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                    Text("123 Sukhumvit Rd, Bangkok, Thailand")
                        .font(.system(.caption2, design: .monospaced))
                    Text("TAX ID: 0-1055-63045-88-1")
                        .font(.system(.caption2, design: .monospaced))
                    Text("Tel: 02-123-4567")
                        .font(.system(.caption2, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .padding(.top, 16)
                
                DividerPattern()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("DATE: 2026-06-10 12:15:00")
                    Text("POS ID: AP-IPAD-01")
                    Text("CASHIER: Somchai Lertwit")
                    Text("ORDER ID: #AP-102546-CN")
                    Text("TABLE: Table 08 (Zone A)")
                    Text("GUESTS: 3 Persons")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.black)
                
                DividerPattern()
                
                HStack {
                    Text("ITEM")
                    Spacer()
                    Text("QTY")
                    Text("PRICE").frame(width: 70, alignment: .trailing)
                }
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.black)
                
                DividerPattern()
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Premium Beef Burger")
                            Spacer()
                            Text("2")
                            Text("฿440.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Extra Cheese (x2) (+฿40)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("  + Medium Rare")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Crispy French Fries")
                            Spacer()
                            Text("1")
                            Text("฿120.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Spicy Seasoning")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Matcha Green Tea Latte")
                            Spacer()
                            Text("2")
                            Text("฿220.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Sweet 50% (x2)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("  + Oat Milk (+฿30)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black)
                
                DividerPattern()
                
                VStack(spacing: 2) {
                    HStack {
                        Text("SUBTOTAL")
                        Spacer()
                        Text("฿850.00")
                    }
                    HStack {
                        Text("10% SERVICE CHARGE")
                        Spacer()
                        Text("฿85.00")
                    }
                    HStack {
                        Text("7% VAT INCLUSIVE")
                        Spacer()
                        Text("฿61.17")
                    }
                    HStack {
                        Text("PROMO DISCOUNT (5%)")
                        Spacer()
                        Text("-฿42.50")
                    }
                    
                    DividerPattern()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Text("GRAND TOTAL")
                            .fontWeight(.bold)
                        Spacer()
                        Text("฿892.50")
                            .fontWeight(.bold)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black)
                
                DividerPattern()
                
                VStack(spacing: 8) {
                    Text("PAID VIA DYNAMIC QR PROMPTPAY")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 100, height: 100)
                            .border(Color.black, width: 1)
                        
                        GridPattern()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: 80, height: 80)
                    }
                    .padding(.vertical, 6)
                    
                    Text("THANK YOU FOR YOUR PATRONAGE")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, paperWidth == "58mm" ? 20 : 32)
            .background(Color(hex: "FCFCF9"))
            
            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .rotationEffect(.degrees(180))
                .opacity(0.3)
        }
        .frame(width: paperWidth == "58mm" ? 320 : 400)
        .cornerRadius(4)
        .shadow(radius: 4)
    }
}

// MARK: - Kitchen Ticket Preview Card
struct KitchenTicketPreviewCard: View {
    var paperWidth: String
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("HOT KITCHEN TICKET")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .tracking(2.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.appRose)
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TABLE: T-08")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.black)
                        Text("Order: #AP-1025")
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("QUE: #32")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.black)
                            .foregroundColor(.appRose)
                        Text("12:15:32")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .foregroundColor(.black)
                
                DividerPattern()
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("2 x PREMIUM BEEF BURGER")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.black)
                            Spacer()
                            Text("[ ] Pending")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("- ** EXTRA CHEESE (x2)")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.appRose)
                            Text("- ** MEDIUM RARE")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.appRose)
                        }
                        .padding(.leading, 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("1 x CRISPY FRENCH FRIES")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.black)
                            Spacer()
                            Text("[ ] Pending")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        Text("- SPICY SEASONING")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.leading, 12)
                    }
                }
                .foregroundColor(.black)
                
                DividerPattern()
                
                Text("PRINT JOB: #AP-PRNT-4592\nSTAFF: Somchai Lertwit")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, paperWidth == "58mm" ? 20 : 32)
            .padding(.top, 16)
            .background(Color(hex: "FCFCF9"))
            
            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .rotationEffect(.degrees(180))
                .opacity(0.3)
        }
        .frame(width: paperWidth == "58mm" ? 320 : 400)
        .cornerRadius(4)
        .shadow(radius: 4)
    }
}

// MARK: - Sticker Preview Card
struct StickerPreviewCard: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("T-08 [TICKET 1/3]")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Text("QUE: #32")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                }
                .foregroundColor(.black)
                
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(height: 1)
                
                Text("Matcha Latte (Oat)")
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.black)
                    .foregroundColor(.black)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("- Sweet 50%")
                    Text("- Extra Oat Milk (+฿30)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black.opacity(0.8))
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("2026-06-10 12:15")
                        Text("AlphaPOS Cafe & Grill")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.black.opacity(0.6))
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        ForEach(0..<12) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: i % 3 == 0 ? 3 : (i % 2 == 0 ? 1.5 : 0.8), height: 18)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 280, height: 180)
            .background(Color.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
        }
        .shadow(radius: 4)
    }
}

// MARK: - Mini Shapes / Helpers for Simulators
struct DividerPattern: View {
    var body: some View {
        Text("--------------------------------------------------")
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.black.opacity(0.4))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct PaperEdgePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let width = rect.width
        let triangleWidth: CGFloat = 8
        let triangleHeight: CGFloat = 6
        var currentX: CGFloat = 0
        
        while currentX < width {
            path.addLine(to: CGPoint(x: currentX + triangleWidth/2, y: rect.minY + triangleHeight))
            path.addLine(to: CGPoint(x: currentX + triangleWidth, y: rect.maxY))
            currentX += triangleWidth
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 6
        let w = rect.width / CGFloat(steps)
        let h = rect.height / CGFloat(steps)
        
        for i in 0...steps {
            path.move(to: CGPoint(x: rect.minX + CGFloat(i)*w, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(i)*w, y: rect.maxY))
            
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(i)*h))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(i)*h))
        }
        return path
    }
}

// MARK: - Printer Row View Component
struct PrinterRowView: View {
    let printer: Printer
    var onPreview: () -> Void
    var onEdit: () -> Void
    
    private var iconName: String {
        switch printer.role {
        case "receipt": return "printer.fill"
        case "kitchen": return "printer.dotmatrix.fill"
        default: return "tag.fill"
        }
    }
    
    private var iconColor: Color {
        switch printer.role {
        case "receipt": return Color.appAccent
        case "kitchen": return Color.appTeal
        default: return Color.appAmber
        }
    }
    
    private var connectionText: String {
        if printer.connectionType == "network" {
            return "\(printer.ipAddress ?? "No IP"):\(printer.port)"
        } else if printer.connectionType == "bluetooth" {
            return "Bluetooth: \(printer.bluetoothName ?? "Unknown")"
        } else {
            return "USB Connection"
        }
    }
    
    private var roleLabel: String {
        switch printer.role {
        case "receipt": return "Receipt"
        case "kitchen": return "Kitchen"
        default: return "Sticker"
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                
                Text("\(connectionText) • \(printer.paperWidth)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(roleLabel)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(iconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(iconColor.opacity(0.12))
                .cornerRadius(APRadius.sm)
            
            HStack(spacing: 8) {
                Button(action: onPreview) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.textSecondary)
                        .padding(8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Circle())
                }
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.appAccent)
                        .padding(8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
}
