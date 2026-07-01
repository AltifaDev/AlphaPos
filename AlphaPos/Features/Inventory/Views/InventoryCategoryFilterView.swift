// InventoryCategoryFilterView.swift
// AlphaPos — Category Filter Components for Inventory
//
// Provides: CategoryChipBar, CategorySidebar, ManageCategoriesSheet,
// BulkAssignCategorySheet for managing 500+ inventory items efficiently.

import SwiftUI
import SwiftData


// MARK: - 1. CategoryChipBar

/// Horizontal scrollable chip/pill selector for filtering inventory by category
struct CategoryChipBar: View {
    let categories: [String]
    @Binding var selectedCategory: String
    var itemCounts: [String: Int]
    
    /// All categories plus "All" at the beginning
    private var allOptions: [String] {
        ["All"] + categories
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: APSpacing.sm) {
                ForEach(allOptions, id: \.self) { category in
                    CategoryChipView(
                        category: category,
                        icon: category == "All" ? "📦" : InventoryCategory.icon(for: category),
                        count: category == "All"
                            ? itemCounts.values.reduce(0, +)
                            : (itemCounts[category] ?? 0),
                        isSelected: selectedCategory == category
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.xs)
        }
    }
}

/// Individual chip/pill view
private struct CategoryChipView: View {
    let category: String
    let icon: String
    let count: Int
    let isSelected: Bool
    
    private var displayName: String {
        category == "All" ? "ทั้งหมด" : category
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 12))
            
            Text(displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : Color.appTeal)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.25) : Color.appTeal.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ? Color.appTeal : Color.clear)
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.clear : Color.appDivider, lineWidth: 1)
        )
        .foregroundColor(isSelected ? .white : .primary)
        .contentShape(Capsule())
    }
}

// MARK: - 2. CategorySidebar (iPad Landscape)

/// Vertical sidebar for category selection on iPad landscape
struct CategorySidebar: View {
    let categories: [String]
    @Binding var selectedCategory: String
    var itemCounts: [String: Int]
    var onManageCategories: () -> Void
    
    private var allOptions: [String] {
        ["All"] + categories
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("หมวดหมู่")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
            
            Divider().background(Color.appDivider)
            
            // Category List
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(allOptions, id: \.self) { category in
                        CategorySidebarRow(
                            category: category,
                            icon: category == "All" ? "📦" : InventoryCategory.icon(for: category),
                            displayName: category == "All" ? "ทั้งหมด" : category,
                            count: category == "All"
                                ? itemCounts.values.reduce(0, +)
                                : (itemCounts[category] ?? 0),
                            isSelected: selectedCategory == category
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedCategory = category
                            }
                        }
                    }
                }
                .padding(.vertical, APSpacing.xs)
            }
            
            Divider().background(Color.appDivider)
            
            // Manage Categories Button
            Button(action: onManageCategories) {
                HStack(spacing: APSpacing.sm) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                    Text("จัดการหมวดหมู่")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.appTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, APSpacing.sm)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.sm)
        }
        .frame(width: 200)
        .background(Color.appSurface)
        .overlay(
            Rectangle().fill(Color.appDivider).frame(width: 1),
            alignment: .trailing
        )
    }
}

/// Individual sidebar row
private struct CategorySidebarRow: View {
    let category: String
    let icon: String
    let displayName: String
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: APSpacing.sm) {
            Text(icon)
                .font(.system(size: 14))
                .frame(width: 22)
            
            Text(displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? Color.appTeal : .primary)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                .fill(isSelected ? Color.appTeal.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                .stroke(isSelected ? Color.appTeal.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, APSpacing.xs)
        .contentShape(Rectangle())
    }
}

// MARK: - 3. ManageCategoriesSheet

/// Sheet for managing categories — CRUD, auto-assign, ABC classification
struct ManageCategoriesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var customCategories: [InventoryCategory] = InventoryCategory.predefined
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "📋"
    @State private var newCategoryLocation = ""
    @State private var isAutoAssigning = false
    @State private var isClassifying = false
    @State private var autoAssignResult: String = ""
    @State private var showingAutoAssignResult = false
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: Predefined Categories Section
                Section {
                    ForEach(customCategories) { category in
                        HStack(spacing: APSpacing.md) {
                            Text(category.icon)
                                .font(.system(size: 20))
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text(category.defaultStorageLocation)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        customCategories.remove(atOffsets: indexSet)
                    }
                } header: {
                    HStack {
                        Text("หมวดหมู่ที่มี")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text("\(customCategories.count) หมวด")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                // MARK: Add New Category
                Section {
                    Button(action: { showingAddCategory = true }) {
                        HStack(spacing: APSpacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color.appTeal)
                            Text("เพิ่มหมวดหมู่ใหม่")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.appTeal)
                        }
                    }
                }
                
                // MARK: Auto Actions Section
                Section {
                    // Auto-Assign Button
                    Button(action: performAutoAssign) {
                        HStack(spacing: APSpacing.md) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("จัดหมวดหมู่อัตโนมัติ")
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text("วิเคราะห์จาก SKU และชื่อวัตถุดิบ แล้วกำหนดหมวดหมู่+ตำแหน่งจัดเก็บ")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isAutoAssigning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isAutoAssigning)
                    
                    // ABC Classification Button
                    Button(action: performABCClassification) {
                        HStack(spacing: APSpacing.md) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 16))
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ABC Classification")
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text("จัดลำดับความสำคัญ A/B/C ตามมูลค่าสต๊อก (Pareto 80/20)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if isClassifying {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isClassifying)
                } header: {
                    Text("เครื่องมืออัตโนมัติ")
                        .font(.system(size: 12, weight: .bold))
                } footer: {
                    Text("Auto-Assign: วิเคราะห์ SKU prefix (ING-BEEF → เนื้อสัตว์) และชื่อ keyword matching\nABC: จัดกลุ่ม A (มูลค่าสูงสุด 80%) / B (กลาง 15%) / C (ต่ำ 5%)")
                        .font(.system(size: 10))
                }
                
                // MARK: Storage Locations Reference
                Section {
                    ForEach(storageLocations, id: \.self) { location in
                        HStack(spacing: APSpacing.sm) {
                            Text(storageLocationIcon(location))
                                .font(.system(size: 14))
                            Text(location)
                                .font(.system(size: 13))
                            Spacer()
                        }
                    }
                } header: {
                    Text("ตำแหน่งจัดเก็บมาตรฐาน")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("จัดการหมวดหมู่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
            .alert("ผลการจัดหมวดหมู่", isPresented: $showingAutoAssignResult) {
                Button("ตกลง", role: .cancel) {}
            } message: {
                Text(autoAssignResult)
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCategorySheet(
                    name: $newCategoryName,
                    icon: $newCategoryIcon,
                    location: $newCategoryLocation,
                    onSave: {
                        if !newCategoryName.isEmpty {
                            let newCat = InventoryCategory(
                                name: newCategoryName,
                                icon: newCategoryIcon.isEmpty ? "📋" : newCategoryIcon,
                                defaultStorageLocation: newCategoryLocation.isEmpty ? "ไม่ระบุ" : newCategoryLocation
                            )
                            customCategories.append(newCat)
                            newCategoryName = ""
                            newCategoryIcon = "📋"
                            newCategoryLocation = ""
                        }
                        showingAddCategory = false
                    }
                )
            }
        }
    }
    
    // MARK: - Auto-Assign Logic
    
    private func performAutoAssign() {
        isAutoAssigning = true
        
        Task {
            let descriptor = FetchDescriptor<InventoryItem>(
                predicate: #Predicate<InventoryItem> { $0.isDeleted == false }
            )
            guard let items = try? modelContext.fetch(descriptor) else {
                isAutoAssigning = false
                return
            }
            
            var assignedCount = 0
            
            for item in items {
                let (category, location) = categorizeItem(item)
                if item.category != category || item.storageLocation != location {
                    item.category = category
                    item.storageLocation = location
                    item.isSynced = false
                    item.updatedAt = Date()
                    assignedCount += 1
                }
            }
            
            modelContext.saveWithLogging(label: #function)
            
            if assignedCount > 0 {
                Task {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                }
            }
            
            autoAssignResult = "จัดหมวดหมู่สำเร็จ \(assignedCount) รายการ จากทั้งหมด \(items.count) รายการ"
            isAutoAssigning = false
            showingAutoAssignResult = true
        }
    }
    
    /// Categorize an item based on SKU prefix and name keywords
    private func categorizeItem(_ item: InventoryItem) -> (category: String, location: String) {
        let sku = (item.sku ?? "").uppercased()
        let name = item.name.lowercased()
        
        // 1. SKU prefix matching
        let skuRules: [(prefixes: [String], category: String)] = [
            (["ING-BEEF", "ING-PORK", "ING-CHICKEN", "ING-DUCK", "ING-LAMB"], "เนื้อสัตว์"),
            (["ING-PRAWN", "ING-FISH", "ING-SQUID", "ING-CRAB", "ING-SHRIMP", "ING-CLAM", "ING-MUSSEL"], "อาหารทะเล"),
            (["ING-VEG", "ING-FRUIT", "ING-HERB", "ING-MANGO", "ING-LIME", "ING-LEMON", "ING-TOMATO", "ING-ONION", "ING-GARLIC"], "ผักและผลไม้"),
            (["ING-MILK", "ING-CHEESE", "ING-BUTTER", "ING-CREAM", "ING-YOGURT"], "นมและผลิตภัณฑ์นม"),
            (["ING-RICE", "ING-FLOUR", "ING-NOODLE", "ING-PASTA", "ING-BREAD", "ING-SWEETRICE", "ING-WHEAT"], "แป้งและธัญพืช"),
            (["ING-SAUCE", "ING-SOY", "ING-FISH-SAUCE", "ING-OYSTER", "ING-VINEGAR", "ING-KETCHUP"], "เครื่องปรุงรส"),
            (["ING-OIL", "ING-LARD", "ING-COCONUT-OIL", "ING-SESAME"], "น้ำมันและไขมัน"),
            (["ING-SPICE", "ING-PEPPER", "ING-CHILI", "ING-CURRY", "ING-CUMIN", "ING-CINNAMON"], "เครื่องเทศและสมุนไพร"),
            (["ING-CAN", "ING-DRY", "ING-BEAN", "ING-COCONUT"], "อาหารแห้ง/กระป๋อง"),
            (["ING-DRINK", "ING-SODA", "ING-JUICE", "ING-WATER", "ING-TEA", "ING-COFFEE"], "เครื่องดื่ม"),
            (["ING-FROZEN", "ING-ICE"], "แช่แข็ง"),
            (["PKG-", "ING-BOX", "ING-BAG", "ING-CUP", "ING-WRAP"], "บรรจุภัณฑ์"),
            (["SUP-", "ING-CLEAN", "ING-SOAP", "ING-GLOVE"], "สิ้นเปลือง"),
        ]
        
        for rule in skuRules {
            for prefix in rule.prefixes {
                if sku.hasPrefix(prefix) {
                    let loc = InventoryCategory.storageLocation(for: rule.category)
                    return (rule.category, loc)
                }
            }
        }
        
        // 2. Name keyword matching (fallback)
        let nameRules: [([String], String)] = [
            (["beef", "pork", "chicken", "duck", "lamb", "meat", "shank", "tenderloin", "thigh", "breast", "เนื้อ", "หมู", "ไก่", "เป็ด"], "เนื้อสัตว์"),
            (["prawn", "shrimp", "fish", "squid", "crab", "clam", "river prawn", "กุ้ง", "ปลา", "หมึก", "ปู"], "อาหารทะเล"),
            (["vegetable", "fruit", "lettuce", "tomato", "onion", "mango", "lime", "honey mango", "ผัก", "ผลไม้", "มะม่วง", "มะนาว"], "ผักและผลไม้"),
            (["milk", "cheese", "butter", "cream", "yogurt", "นม", "เนย", "ชีส", "ครีม"], "นมและผลิตภัณฑ์นม"),
            (["rice", "flour", "noodle", "bread", "pasta", "glutinous", "ข้าว", "แป้ง", "เส้น", "ขนมปัง"], "แป้งและธัญพืช"),
            (["sauce", "soy", "vinegar", "ketchup", "ซอส", "น้ำปลา", "ซีอิ๊ว", "น้ำส้มสายชู"], "เครื่องปรุงรส"),
            (["oil", "lard", "ghee", "น้ำมัน"], "น้ำมันและไขมัน"),
            (["pepper", "chili", "curry", "cumin", "spice", "herb", "basil", "lemongrass", "galangal", "green curry", "พริก", "กะเพรา", "ตะไคร้", "ข่า", "เครื่องเทศ"], "เครื่องเทศและสมุนไพร"),
            (["coconut milk", "canned", "dried", "bean", "กะทิ", "กระป๋อง", "ถั่ว", "แห้ง"], "อาหารแห้ง/กระป๋อง"),
            (["drink", "soda", "juice", "water", "tea", "coffee", "น้ำ", "ชา", "กาแฟ", "น้ำอัดลม"], "เครื่องดื่ม"),
            (["frozen", "ice", "แช่แข็ง", "น้ำแข็ง"], "แช่แข็ง"),
            (["box", "bag", "cup", "lid", "straw", "wrap", "กล่อง", "ถุง", "แก้ว", "หลอด"], "บรรจุภัณฑ์"),
            (["soap", "clean", "glove", "tissue", "สบู่", "ทำความสะอาด", "ถุงมือ", "กระดาษ"], "สิ้นเปลือง"),
        ]
        
        for (keywords, category) in nameRules {
            for keyword in keywords {
                if name.contains(keyword) {
                    let loc = InventoryCategory.storageLocation(for: category)
                    return (category, loc)
                }
            }
        }
        
        // Default — keep existing or mark as uncategorized
        let existingCategory = item.category ?? "ไม่ระบุหมวดหมู่"
        let existingLocation = item.storageLocation ?? "ไม่ระบุตำแหน่ง"
        return (existingCategory, existingLocation)
    }
    
    // MARK: - ABC Classification Logic
    
    private func performABCClassification() {
        isClassifying = true
        
        Task {
            let descriptor = FetchDescriptor<InventoryItem>(
                predicate: #Predicate<InventoryItem> { $0.isDeleted == false }
            )
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else {
                isClassifying = false
                return
            }
            
            // Calculate total value per item: costPrice × currentQuantity
            var itemValues: [(item: InventoryItem, value: Double)] = items.map { item in
                (item: item, value: item.costPrice * max(item.currentQuantity, 0))
            }
            
            // Sort by value descending
            itemValues.sort { $0.value > $1.value }
            
            let totalValue = itemValues.reduce(0.0) { $0 + $1.value }
            guard totalValue > 0 else {
                isClassifying = false
                return
            }
            
            // Assign ABC:
            // A = items accounting for top 80% cumulative value
            // B = next 15% cumulative value
            // C = remaining 5%
            var cumulativeValue = 0.0
            var classACount = 0
            var classBCount = 0
            var classCCount = 0
            
            var abcDict: [String: String] = [:]
            
            for (item, value) in itemValues {
                cumulativeValue += value
                let percentage = cumulativeValue / totalValue
                
                let classification: String
                if percentage <= 0.80 {
                    classification = "A"
                    classACount += 1
                } else if percentage <= 0.95 {
                    classification = "B"
                    classBCount += 1
                } else {
                    classification = "C"
                    classCCount += 1
                }
                
                abcDict[item.id.uuidString] = classification
                item.updatedAt = Date()
                item.isSynced = false
            }
            
            // Store ABC classification in UserDefaults (lightweight, accessible everywhere)
            if let data = try? JSONEncoder().encode(abcDict) {
                UserDefaults.standard.set(data, forKey: "inventory_abc_classification")
            }
            
            modelContext.saveWithLogging(label: #function)
            
            autoAssignResult = "ABC Classification สำเร็จ:\n• Class A (มูลค่าสูง): \(classACount) รายการ\n• Class B (ปานกลาง): \(classBCount) รายการ\n• Class C (มูลค่าต่ำ): \(classCCount) รายการ"
            isClassifying = false
            showingAutoAssignResult = true
            
            // Post notification so InventoryView can refresh
            NotificationCenter.default.post(name: .inventoryABCUpdated, object: nil)
        }
    }
    
    // MARK: - Helpers
    
    private var storageLocations: [String] {
        ["ห้องเย็น", "ตู้แช่แข็ง", "ห้องเก็บแห้ง", "ชั้นวางเครื่องปรุง", "ชั้นวางเครื่องดื่ม", "ห้องเก็บของ"]
    }
    
    private func storageLocationIcon(_ location: String) -> String {
        switch location {
        case "ห้องเย็น": return "❄️"
        case "ตู้แช่แข็ง": return "🧊"
        case "ห้องเก็บแห้ง": return "📦"
        case "ชั้นวางเครื่องปรุง": return "🧂"
        case "ชั้นวางเครื่องดื่ม": return "🥤"
        case "ห้องเก็บของ": return "🧹"
        default: return "📋"
        }
    }
}

// MARK: - Add Category Sheet (sub-sheet)

private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String
    @Binding var icon: String
    @Binding var location: String
    var onSave: () -> Void
    
    private let commonIcons = ["🥩", "🦐", "🥬", "🥛", "🍚", "🧂", "🫒", "🌿", "🥫", "🥤", "🧊", "📦", "🧹", "🍕", "🍜", "🥚", "🧈", "🍞"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("ข้อมูลหมวดหมู่") {
                    TextField("ชื่อหมวดหมู่", text: $name)
                    
                    // Icon picker
                    VStack(alignment: .leading, spacing: APSpacing.sm) {
                        Text("ไอคอน: \(icon)")
                            .font(.system(size: 13))
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9), spacing: 8) {
                            ForEach(commonIcons, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(icon == emoji ? Color.appTeal.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(icon == emoji ? Color.appTeal : Color.clear, lineWidth: 1.5)
                                    )
                                    .onTapGesture { icon = emoji }
                            }
                        }
                    }
                    
                    TextField("ตำแหน่งจัดเก็บเริ่มต้น", text: $location)
                }
                
                Section {
                    Text("หมวดหมู่ใหม่จะปรากฏในตัวกรองและสามารถใช้ Auto-Assign ได้")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("เพิ่มหมวดหมู่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { onSave() }
                        .disabled(name.isEmpty)
                        .foregroundColor(Color.appTeal)
                }
            }
        }
    }
}

// MARK: - 4. BulkAssignCategorySheet

/// Sheet for bulk-assigning a category to multiple selected items
struct BulkAssignCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let selectedItemIds: Set<UUID>
    var onComplete: () -> Void
    
    @State private var selectedCategoryForAssign: String = ""
    @State private var assignStorageLocation = true
    
    private var categories: [InventoryCategory] {
        InventoryCategory.predefined
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Info
                HStack(spacing: APSpacing.md) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(Color.appTeal)
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("กำหนดหมวดหมู่")
                            .font(.system(size: 15, weight: .semibold))
                        Text("เลือก \(selectedItemIds.count) รายการ")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                
                Divider().background(Color.appDivider)
                
                // Category List
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(categories) { category in
                            Button(action: { selectedCategoryForAssign = category.name }) {
                                HStack(spacing: APSpacing.md) {
                                    Text(category.icon)
                                        .font(.system(size: 20))
                                        .frame(width: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Text(category.defaultStorageLocation)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedCategoryForAssign == category.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color.appTeal)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.horizontal, APSpacing.md)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                        .fill(selectedCategoryForAssign == category.name
                                              ? Color.appTeal.opacity(0.06)
                                              : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, APSpacing.sm)
                }
                
                Divider().background(Color.appDivider)
                
                // Options + Confirm
                VStack(spacing: APSpacing.md) {
                    Toggle(isOn: $assignStorageLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("กำหนดตำแหน่งจัดเก็บด้วย")
                                .font(.system(size: 13, weight: .medium))
                            if !selectedCategoryForAssign.isEmpty {
                                Text("→ \(InventoryCategory.storageLocation(for: selectedCategoryForAssign))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(Color.appTeal)
                    
                    Button(action: applyBulkCategory) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("กำหนดให้ \(selectedItemIds.count) รายการ")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                .fill(selectedCategoryForAssign.isEmpty
                                      ? Color.gray.opacity(0.4)
                                      : Color.appTeal)
                        )
                    }
                    .disabled(selectedCategoryForAssign.isEmpty)
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
            }
            .background(Color.appBackground)
            .navigationTitle("กำหนดหมวดหมู่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
            }
        }
    }
    
    private func applyBulkCategory() {
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == false }
        )
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        let targetItems = items.filter { selectedItemIds.contains($0.id) }
        let storageLocation = InventoryCategory.storageLocation(for: selectedCategoryForAssign)
        
        for item in targetItems {
            item.category = selectedCategoryForAssign
            if assignStorageLocation {
                item.storageLocation = storageLocation
            }
            item.isSynced = false
            item.updatedAt = Date()
        }
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        
        onComplete()
        dismiss()
    }
}

// MARK: - ABC Badge View

/// Small colored badge showing ABC classification for an inventory item
struct ABCBadge: View {
    let itemId: UUID
    
    private var abcClass: String {
        guard let data = UserDefaults.standard.data(forKey: "inventory_abc_classification"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ""
        }
        return dict[itemId.uuidString] ?? ""
    }
    
    var body: some View {
        if !abcClass.isEmpty {
            Text(abcClass)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(abcColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(abcColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(abcColor.opacity(0.3), lineWidth: 0.5)
                )
        }
    }
    
    private var abcColor: Color {
        switch abcClass {
        case "A": return .red
        case "B": return .orange
        case "C": return .green
        default: return .gray
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let inventoryABCUpdated = Notification.Name("inventoryABCUpdated")
}
