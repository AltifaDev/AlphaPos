import Foundation
import SwiftData

/// Maintains one canonical role per restaurant position and repairs legacy
/// duplicates created by UUID-only synchronization.
@MainActor
enum RoleBootstrap {
    static func ensureDefaultRoles(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<Role>()
        descriptor.fetchLimit = 500
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        var activeByKey = Dictionary(grouping: existing.filter { !$0.isDeleted }) {
            RestaurantRoleCatalog.deduplicationKey(for: $0.name)
        }

        for definition in RestaurantRoleCatalog.definitions {
            if activeByKey[definition.id]?.isEmpty == false { continue }
            let role = Role(
                name: definition.name,
                roleDescription: definition.description,
                permissionKeys: PermissionService.permissionCSV(
                    for: PermissionService.permissions(forRoleName: definition.permissionRole)
                )
            )
            modelContext.insert(role)
            activeByKey[definition.id, default: []].append(role)
        }

        reconcileDuplicates(in: existing)
        modelContext.saveWithLogging(label: #function)
    }

    private static func reconcileDuplicates(in roles: [Role]) {
        let groups = Dictionary(grouping: roles.filter { !$0.isDeleted }) {
            RestaurantRoleCatalog.deduplicationKey(for: $0.name)
        }

        for (_, matches) in groups where !matches.isEmpty {
            let definition = RestaurantRoleCatalog.definition(for: matches[0].name)
            let keeper = matches.max { lhs, rhs in
                let lhsUsers = lhs.users?.count ?? 0
                let rhsUsers = rhs.users?.count ?? 0
                if lhsUsers != rhsUsers { return lhsUsers < rhsUsers }
                return lhs.updatedAt < rhs.updatedAt
            }!

            if let definition {
                var changed = false
                if keeper.name != definition.name {
                    keeper.name = definition.name
                    changed = true
                }
                if keeper.roleDescription?.isEmpty != false {
                    keeper.roleDescription = definition.description
                    changed = true
                }
                if keeper.permissionKeys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keeper.permissionKeys = PermissionService.permissionCSV(
                        for: PermissionService.permissions(forRoleName: definition.permissionRole)
                    )
                    changed = true
                }
                if changed {
                    keeper.isSynced = false
                    keeper.updatedAt = Date()
                }
            }

            for duplicate in matches where duplicate.id != keeper.id {
                for user in duplicate.users ?? [] {
                    user.role = keeper
                    user.isSynced = false
                    user.updatedAt = Date()
                }
                duplicate.isDeleted = true
                duplicate.isSynced = false
                duplicate.updatedAt = Date()
            }
        }
    }
}
