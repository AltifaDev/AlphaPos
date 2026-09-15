import Foundation
import Combine
import SwiftData
import SwiftUI

enum BranchContextError: LocalizedError {
    case noBranch
    case selectionRequired
    case staleSelection

    var errorDescription: String? {
        switch self {
        case .noBranch: return "ยังไม่มีสาขาสำหรับร้านนี้"
        case .selectionRequired: return "กรุณาเลือกสาขาก่อนทำรายการ"
        case .staleSelection: return "สาขาที่เลือกไว้ไม่มีอยู่หรือถูกปิดใช้งาน กรุณาเลือกสาขาใหม่"
        }
    }
}

/// The only authority for the device's operational branch. Feature code must
/// not read or write `active_branch_id` directly.
@MainActor
final class BranchContext: ObservableObject {
    static let shared = BranchContext()
    static let storageKey = "active_branch_id"

    @Published private(set) var activeBranchID: UUID?
    @Published private(set) var requiresSelection = false
    @Published private(set) var lastError: String?

    private var cachedActiveBranch: Branch? = nil

    var activeBranchIDString: String { activeBranchID?.uuidString.lowercased() ?? "" }

    private init() {
        activeBranchID = UserDefaults.standard.string(forKey: Self.storageKey)
            .flatMap(UUID.init(uuidString:))
    }

    @discardableResult
    func bootstrap(in context: ModelContext, createDefaultIfEmpty: Bool = true) throws -> Branch? {
        var branches = try context.fetch(FetchDescriptor<Branch>()).filter { !$0.isDeleted }
        if branches.isEmpty, createDefaultIfEmpty {
            let branch = Branch(name: "Main Branch", location: "Headquarters")
            context.insert(branch)
            try context.save()
            branches = [branch]
        }
        guard !branches.isEmpty else {
            clear(error: BranchContextError.noBranch.localizedDescription)
            throw BranchContextError.noBranch
        }

        if let id = activeBranchID, let branch = branches.first(where: { $0.id == id }) {
            requiresSelection = false
            lastError = nil
            persist(branch.id)
            cachedActiveBranch = branch
            return branch
        }

        if branches.count == 1, let only = branches.first {
            select(only)
            return only
        }

        // Multiple branches are ambiguous. Never choose alphabetically/first.
        clear(error: BranchContextError.selectionRequired.localizedDescription)
        requiresSelection = true
        throw BranchContextError.selectionRequired
    }

    func requireActiveBranch(in context: ModelContext) throws -> Branch {
        guard let id = activeBranchID else {
            requiresSelection = true
            throw BranchContextError.selectionRequired
        }
        if let cached = cachedActiveBranch, cached.id == id, !cached.isDeleted {
            return cached
        }
        let branches = try context.fetch(FetchDescriptor<Branch>())
        guard let branch = branches.first(where: { $0.id == id && !$0.isDeleted }) else {
            clear(error: BranchContextError.staleSelection.localizedDescription)
            requiresSelection = true
            throw BranchContextError.staleSelection
        }
        cachedActiveBranch = branch
        return branch
    }

    func select(_ branch: Branch) {
        precondition(!branch.isDeleted, "Cannot select a deleted branch")
        cachedActiveBranch = branch
        persist(branch.id)
        requiresSelection = false
        lastError = nil
    }

    func invalidateIfSelected(_ branch: Branch) {
        guard activeBranchID == branch.id else { return }
        cachedActiveBranch = nil
        clear(error: BranchContextError.staleSelection.localizedDescription)
        requiresSelection = true
    }

    private func persist(_ id: UUID) {
        activeBranchID = id
        UserDefaults.standard.set(id.uuidString.lowercased(), forKey: Self.storageKey)
    }

    private func clear(error: String?) {
        activeBranchID = nil
        cachedActiveBranch = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        lastError = error
    }
}

struct RequiredBranchSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Branch> { !$0.isDeleted }, sort: \Branch.name) private var branches: [Branch]
    @ObservedObject private var branchContext = BranchContext.shared

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.appAccent)
                Text("กรุณาเลือกสาขา")
                    .font(.title2.bold())
                Text("อุปกรณ์นี้มีหลายสาขาและไม่สามารถระบุสาขาที่ถูกต้องได้ ระบบจะไม่สร้างรายการจนกว่าจะเลือกสาขา")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.textSecondary)
                ForEach(branches) { branch in
                    Button {
                        BranchContext.shared.select(branch)
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Image(systemName: "storefront")
                            Text(branch.name).fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 480)
            .padding(28)
        }
    }
}
