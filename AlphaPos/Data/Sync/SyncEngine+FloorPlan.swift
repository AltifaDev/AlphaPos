import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Floor Plan, Orders, Sessions Sync
extension SyncEngine {
    func syncDiningAreas(_ modelContext: ModelContext) async {
        let areas = (try? modelContext.fetch(FetchDescriptor<FloorData>(predicate: #Predicate { !$0.isSynced }))) ?? []
        for area in areas {
            do {
                if try await NetworkManager.shared.uploadDiningArea(area) {
                    area.isSynced = true
                }
            } catch { encounteredSyncError = true; print("SyncEngine [Dining Area Sync]: \(error)") }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullDiningAreas(_ modelContext: ModelContext) async {
        do {
            let remote = try await NetworkManager.shared.fetchDiningAreas()
            let local = (try? modelContext.fetch(FetchDescriptor<FloorData>())) ?? []
            let activeBranchId = BranchContext.shared.activeBranchIDString.lowercased()
            // Floor numbers are only unique inside a branch.
            let byId = Dictionary(
                local.filter { $0.branchId.lowercased() == activeBranchId }
                    .map { ($0.uuid, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var byFloor = Dictionary(
                local.filter { $0.branchId.lowercased() == activeBranchId }
                    .map { ($0.floorNumber, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for row in remote {
                guard let rawId = row["id"] as? String, let id = UUID(uuidString: rawId),
                      let branchId = row["branch_id"] as? String else { continue }
                let floorNumber = row["floor_number"] as? Int ?? 1
                let updatedAt = remoteDate(row["updated_at"], fallback: Date())
                if let area = byId[id] {
                    guard area.isSynced else { continue }
                    area.floorNumber = floorNumber
                    area.name = row["name"] as? String ?? area.name
                    area.sortOrder = row["sort_order"] as? Int ?? area.sortOrder
                    area.isActive = row["is_active"] as? Bool ?? true
                    area.isDeleted = row["is_deleted"] as? Bool ?? false
                    area.updatedAt = updatedAt
                } else if let localFloor = byFloor[floorNumber] {
                    localFloor.branchId = branchId
                    localFloor.uuid = id
                    localFloor.name = row["name"] as? String ?? localFloor.name
                    localFloor.sortOrder = row["sort_order"] as? Int ?? localFloor.sortOrder
                    localFloor.isActive = row["is_active"] as? Bool ?? true
                    localFloor.isDeleted = row["is_deleted"] as? Bool ?? false
                    localFloor.isSynced = true
                    localFloor.updatedAt = updatedAt
                } else {
                    let newArea = FloorData(uuid: id,
                        floorNumber: floorNumber,
                        name: row["name"] as? String ?? "Main Area", branchId: branchId,
                        sortOrder: row["sort_order"] as? Int ?? 0,
                        isActive: row["is_active"] as? Bool ?? true, isSynced: true,
                        isDeleted: row["is_deleted"] as? Bool ?? false, updatedAt: updatedAt)
                    modelContext.insert(newArea)
                    byFloor[floorNumber] = newArea
                }
            }
            modelContext.saveWithLogging(label: #function)
            PersistentStoreMigrationRepair.backfillTableLayoutPresetDiningAreas(in: modelContext)
        } catch {
            reportSyncFailure("dining_areas pull: \(error.localizedDescription)", soft: true)
            print("SyncEngine [Dining Area Pull]: \(error)")
        }
    }

    func canonicalTableNumber(_ tableNumber: String) -> String {
        let trimmedNumber = tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedNumber = trimmedNumber.lowercased()
        if lowercasedNumber.hasPrefix("t") {
            let suffix = String(trimmedNumber.dropFirst())
            if !suffix.isEmpty && suffix.allSatisfy({ $0.isNumber }) {
                return suffix
            }
        }
        return lowercasedNumber
    }

    // MARK: - Floor Plan Image Sync
    func syncFloorPlanImages(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<FloorPlanImage>(
            predicate: #Predicate<FloorPlanImage> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            do {
                let success = try await NetworkManager.shared.uploadFloorPlanImage(floorPlan: item)
                if success {
                    if item.isDeleted {
                        if let path = item.resolvedImagePath, FileManager.default.fileExists(atPath: path) {
                            try? FileManager.default.removeItem(atPath: path)
                        }
                        modelContext.delete(item)
                    } else {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                    modelContext.saveWithLogging(label: #function)
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [FloorPlanImage Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func pullFloorPlanImagesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchFloorPlanImages()
            let locals = (try? modelContext.fetch(FetchDescriptor<FloorPlanImage>())) ?? []
            let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
            let branchId = BranchContext.shared.activeBranchIDString

            for remote in remoteItems {
                guard let idString = remote["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let diningAreaIdString = remote["dining_area_id"] as? String,
                      let diningAreaId = UUID(uuidString: diningAreaIdString),
                      let filename = remote["image_filename"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let local = locals.first {
                    $0.id == id || ($0.diningAreaId == diningAreaId && ($0.branchId == branchId || $0.branchId.isEmpty))
                }

                if let local {
                    guard shouldApplyRemoteUpdate(
                        localIsSynced: local.isSynced,
                        localUpdatedAt: local.updatedAt,
                        remoteUpdatedAt: updatedAt
                    ) == .applyRemote else { continue }
                    local.branchId = branchId
                    local.diningAreaId = diningAreaId
                    local.imageFilename = filename
                    local.scale = remoteDouble(remote["scale"], fallback: 1.0)
                    local.offsetX = remoteDouble(remote["offset_x"])
                    local.offsetY = remoteDouble(remote["offset_y"])
                    local.updatedAt = updatedAt
                    local.isSynced = true
                    local.isDeleted = false
                } else {
                    modelContext.insert(FloorPlanImage(
                        id: id,
                        merchantId: merchantId,
                        branchId: branchId,
                        diningAreaId: diningAreaId,
                        imageFilename: filename,
                        scale: remoteDouble(remote["scale"], fallback: 1.0),
                        offsetX: remoteDouble(remote["offset_x"]),
                        offsetY: remoteDouble(remote["offset_y"]),
                        updatedAt: updatedAt,
                        isSynced: true
                    ))
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            reportSyncFailure("floor_plan_images pull: \(error.localizedDescription)", soft: true)
        }
    }

    func syncEmployees(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate<Employee> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let employees = try? modelContext.fetch(descriptor), !employees.isEmpty else { return }

        for employee in employees {
            do {
                if let user = employee.user, !user.isSynced {
                    continue // Defer employee sync until user is synced to server
                }

                let success = try await NetworkManager.shared.uploadEmployee(employee: employee)
                if success {
                    if employee.isDeleted {
                        modelContext.delete(employee)
                    } else {
                        employee.faceEmbeddingNeedsRemoteClear = false
                        employee.isSynced = true
                        employee.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Employee Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncEmployeeShifts(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<EmployeeShift>(
            predicate: #Predicate<EmployeeShift> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let shifts = try? modelContext.fetch(descriptor), !shifts.isEmpty else { return }

        for shift in shifts {
            guard let employee = shift.employee else {
                // Orphan local row — stop retrying forever.
                shift.isSynced = true
                shift.isDeleted = true
                modelContext.saveWithLogging(label: #function)
                print("SyncEngine [EmployeeShift]: quarantined shift \(shift.id) — missing employee relation")
                continue
            }

            // Employees deferred until their User syncs must not push shifts yet
            // (would hit employee_shifts_employee_id_fkey and spam sync alerts).
            guard employee.isSynced, !employee.isDeleted else { continue }

            do {
                let success = try await NetworkManager.shared.uploadEmployeeShift(shift: shift)
                if success {
                    if shift.isDeleted {
                        modelContext.delete(shift)
                    } else {
                        shift.isSynced = true
                        shift.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                let msg = error.localizedDescription
                let isOrphanFK = msg.contains("23503")
                    || msg.lowercased().contains("foreign key")
                    || msg.lowercased().contains("employee_shifts_employee_id")
                if isOrphanFK {
                    // Employee missing on server — quarantine so sync stays green.
                    shift.isSynced = true
                    shift.isDeleted = true
                    modelContext.saveWithLogging(label: #function)
                    reportSyncFailure("EmployeeShift orphan quarantined", soft: true)
                    print("SyncEngine [EmployeeShift]: quarantined shift \(shift.id) — \(msg)")
                } else {
                    reportSyncFailure("EmployeeShift: \(msg)", soft: false)
                    print("SyncEngine [EmployeeShift Sync Error]: \(msg)")
                }
            }
        }
    }

    @discardableResult
    func syncMerchant() async -> Bool {
        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return false }

        let name = UserDefaults.standard.string(forKey: "store_name") ?? UserDefaults.standard.string(forKey: "logged_in_name") ?? "My New POS Shop"
        let email = UserDefaults.standard.string(forKey: "store_email")
            ?? UserDefaults.standard.string(forKey: "logged_in_email")
            ?? "owner@alphapos.com"
        let kitchenWorkflowRequired = UserDefaults.standard.object(forKey: "kitchen_workflow_required") as? Bool ?? true
        let isTableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
        let isWebOrderingEnabled = UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true

        let phone = UserDefaults.standard.string(forKey: "store_phone")
        let website = UserDefaults.standard.string(forKey: "store_website")
        let address = UserDefaults.standard.string(forKey: "store_address")
        let taxId = UserDefaults.standard.string(forKey: "store_tax_id")
        let branchCode = UserDefaults.standard.string(forKey: "store_branch_code")
        let taxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double
        let taxType = UserDefaults.standard.string(forKey: "store_tax_type")
        let serviceChargeRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double
        let receiptHeader = UserDefaults.standard.string(forKey: "store_receipt_header")
        let receiptFooter = UserDefaults.standard.string(forKey: "store_receipt_footer")
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number")
        let logoUrl = UserDefaults.standard.string(forKey: "store_logo_url")

        do {
            _ = try await NetworkManager.shared.uploadMerchant(
                id: merchantId,
                name: name,
                email: email,
                kitchenWorkflowRequired: kitchenWorkflowRequired,
                isTableSystemEnabled: isTableSystemEnabled,
                isWebOrderingEnabled: isWebOrderingEnabled,
                phone: phone,
                website: website,
                address: address,
                taxId: taxId,
                branchCode: branchCode,
                taxRate: taxRate,
                taxType: taxType,
                serviceChargeRate: serviceChargeRate,
                receiptHeader: receiptHeader,
                receiptFooter: receiptFooter,
                promptPayNumber: promptPayNumber,
                logoUrl: logoUrl ?? ""
            )
            return true
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Merchant Sync Error]: \(error.localizedDescription)")
            return false
        }
    }

    func pullRestaurantTables(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        // 0. Normalize existing local table numbers (e.g. "T1" -> "1")
        let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
        if let localTables = try? modelContext.fetch(localTablesDescriptor) {
            var needsSave = false
            for table in localTables {
                let trimmed = table.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("t") {
                    let suffix = String(trimmed.dropFirst())
                    if suffix.allSatisfy({ $0.isNumber }) {
                        table.tableNumber = suffix
                        table.isSynced = false
                        table.updatedAt = Date()
                        needsSave = true
                    }
                }
            }
            if needsSave {
                modelContext.saveWithLogging(label: #function)
            }
        }

        do {
            let remoteTables = try await NetworkManager.shared.fetchRestaurantTables()
            let activeBranchId = BranchContext.shared.activeBranchIDString

            // Active tables are the operational source of truth. Recover a
            // missing/soft-deleted dining area so the iPad can render its floor.
            repairMissingDiningAreas(from: remoteTables, branchId: activeBranchId, modelContext: modelContext)

            var remoteIds = Set<UUID>()

            // Empty remote must NOT force re-upload of every local row — on shared
            // devices that would re-tag a previous merchant's floor plan onto the
            // newly authenticated merchant_id. New/empty stores stay empty until
            // the owner creates tables (or seed runs for a truly blank workspace).
            if remoteTables.isEmpty {
                #if DEBUG
                print("SyncEngine: Server has 0 tables — skipping local force re-push (tenant isolation).")
                #endif
            }

            for remoteTable in remoteTables {
                guard let idStr = remoteTable["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }

                remoteIds.insert(id)

                let tableNumber = remoteTable["table_number"] as? String ?? ""
                let capacity = remoteTable["capacity"] as? Int ?? 2
                let status = remoteTable["status"] as? String ?? "vacant"
                let qrCodeIdentifier = remoteTable["qr_code_identifier"] as? String
                let positionX = remoteTable["position_x"] as? Double ?? 0.0
                let positionY = remoteTable["position_y"] as? Double ?? 0.0
                let layoutScale = (remoteTable["layout_scale"] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 1.0
                let floor = remoteTable["floor"] as? Int ?? 1
                let floorId = (remoteTable["dining_area_id"] as? String).flatMap(UUID.init(uuidString:))
                let tableBranchId = remoteTable["branch_id"] as? String ?? activeBranchId
                let zone = remoteTable["zone"] as? String ?? "Indoor"
                let isDeleted = remoteTable["is_deleted"] as? Bool ?? false
                let remoteIsRound = remoteTable["is_round"] as? Bool ?? false
                let remoteShapeRaw = (remoteTable["table_shape"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let tableShape: String = {
                    if !remoteShapeRaw.isEmpty { return remoteShapeRaw }
                    return remoteIsRound ? "circle" : "rectangle"
                }()
                let isRound = tableShape == "circle" || tableShape == "oval"

                let updatedAtStr = remoteTable["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                var existingTable: RestaurantTable? = nil
                let idDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.id == id }
                )

                if let matches = try? modelContext.fetch(idDescriptor), let first = matches.first {
                    existingTable = first
                } else {
                    let numDescriptor = FetchDescriptor<RestaurantTable>(
                        predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                    )
                    if let matches = try? modelContext.fetch(numDescriptor), !matches.isEmpty {
                        // Prioritize preserving the table that has active sessions or unsynced edits
                        let scopedMatches = matches.filter {
                            $0.floorId == floorId && ($0.branchId == tableBranchId || $0.branchId.isEmpty)
                        }
                        let sortedMatches = scopedMatches.sorted { t1, t2 in
                            let t1HasActive = t1.sessions.contains(where: { $0.isActive })
                            let t2HasActive = t2.sessions.contains(where: { $0.isActive })
                            if t1HasActive != t2HasActive {
                                return t1HasActive && !t2HasActive
                            }
                            return !t1.isSynced && t2.isSynced
                        }

                        existingTable = sortedMatches.first
                        existingTable?.id = id

                        if sortedMatches.count > 1 {
                            for i in 1..<sortedMatches.count {
                                modelContext.delete(sortedMatches[i])
                            }
                        }
                    }
                }

                if let table = existingTable {
                    if isDeleted {
                        // Tombstone instead of hard-delete so an open TableDetailView
                        // (sheet) keeps a valid model reference and doesn't crash.
                        table.isDeleted = true
                        table.isSynced = true
                        table.updatedAt = Date()
                    } else {
                        // A just-deleted local tombstone wins over a stale
                        // remote row (eventual-consistency window). Only a
                        // genuinely newer remote edit may resurrect it.
                        if table.isDeleted && table.updatedAt >= updatedAt {
                            continue
                        }
                        // Only overwrite table properties from the server if local changes are already synced
                        if table.isSynced {
                            if table.tableNumber != tableNumber { table.tableNumber = tableNumber }
                            if table.capacity != capacity { table.capacity = capacity }
                            if table.qrCodeIdentifier != qrCodeIdentifier { table.qrCodeIdentifier = qrCodeIdentifier }
                            if table.positionX != positionX { table.positionX = positionX }
                            if table.positionY != positionY { table.positionY = positionY }
                            if table.layoutScale != layoutScale { table.layoutScale = layoutScale }
                            if table.floor != floor { table.floor = floor }
                            if table.floorId != floorId { table.floorId = floorId }
                            if table.branchId != tableBranchId { table.branchId = tableBranchId }
                            if table.zone != zone { table.zone = zone }
                            if table.updatedAt != updatedAt { table.updatedAt = updatedAt }

                            // Shape: apply remote when present; otherwise keep local
                            // custom shape and mark dirty so the next push heals the DB.
                            if !remoteShapeRaw.isEmpty {
                                if table.tableShape != tableShape { table.tableShape = tableShape }
                                if table.isRound != isRound { table.isRound = isRound }
                            } else if table.tableShape != "rectangle" || table.isRound {
                                table.isSynced = false
                                table.updatedAt = Date()
                            } else if table.isRound != remoteIsRound {
                                table.isRound = remoteIsRound
                                table.tableShape = remoteIsRound ? "circle" : "rectangle"
                            }

                            // Sync cleaning and reserved statuses from the server.
                            // vacant/occupied are reconciled from active sessions below.
                            if status == "cleaning" || status == "reserved" {
                                if table.status != status {
                                    table.status = status
                                }
                            } else if status == "vacant" && (table.status == "cleaning" || table.status == "reserved") {
                                table.status = "vacant"
                            }

                            // occupied is reconciled from active sessions in
                            // pullActiveSessions — do not force it from the
                            // table row alone (was resurrecting ghost occupied).
                        }
                    }
                } else if !isDeleted {
                    let newTable = RestaurantTable(
                        id: id,
                        tableNumber: tableNumber,
                        capacity: capacity,
                        tableShape: tableShape,
                        isRound: isRound,
                        status: status,
                        qrCodeIdentifier: qrCodeIdentifier,
                        positionX: positionX,
                        positionY: positionY,
                        layoutScale: layoutScale,
                        floor: floor,
                        floorId: floorId,
                        branchId: tableBranchId,
                        zone: zone,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newTable)
                }
            }

            // Treat an empty response as non-authoritative. It can mean that the
            // tenant/branch context has not finished binding yet, or that the
            // request was answered before server data became visible. Pruning in
            // that state used to erase every synced table on the device.
            if !remoteTables.isEmpty {
                let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
                if let localTables = try? modelContext.fetch(localTablesDescriptor) {
                    for table in localTables {
                        let isInPulledBranch = table.branchId.caseInsensitiveCompare(activeBranchId) == .orderedSame
                            || (table.branchId.isEmpty && table.floorId != nil)
                        if isInPulledBranch && table.isSynced && !remoteIds.contains(table.id) {
                            // Tombstone instead of hard-delete (keeps open sheets valid).
                            table.isDeleted = true
                            table.isSynced = true
                            table.updatedAt = Date()
                        }
                    }
                }
            }

            // Second pass: wire joinedParent after all rows exist.
            // Skip dirty local rows so pending join/split is not overwritten.
            reconcileJoinedParents(
                remoteTables: remoteTables,
                modelContext: modelContext
            )

            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Table Pull Error]: \(error.localizedDescription)")
        }
    }

    private func repairMissingDiningAreas(
        from remoteTables: [[String: Any]],
        branchId: String,
        modelContext: ModelContext
    ) {
        guard !branchId.isEmpty else { return }
        let localAreas = (try? modelContext.fetch(FetchDescriptor<FloorData>())) ?? []
        var byId = Dictionary(uniqueKeysWithValues: localAreas.map { ($0.uuid, $0) })
        var byFloor = Dictionary(
            localAreas.filter { $0.branchId.caseInsensitiveCompare(branchId) == .orderedSame }
                .map { ($0.floorNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for row in remoteTables {
            guard (row["is_deleted"] as? Bool ?? false) == false,
                  let floor = row["floor"] as? Int else { continue }
            let areaID = (row["dining_area_id"] as? String).flatMap(UUID.init(uuidString:))
            if let area = areaID.flatMap({ byId[$0] }) ?? byFloor[floor] {
                guard area.branchId.caseInsensitiveCompare(branchId) == .orderedSame else { continue }
                // The table's FK wins when an old local Floor 1 UUID differs
                // from the server's dining-area UUID.
                if let areaID, area.uuid != areaID {
                    area.uuid = areaID
                    byId[areaID] = area
                }
                if area.isDeleted || !area.isActive {
                    area.isDeleted = false
                    area.isActive = true
                    area.isSynced = false
                    area.updatedAt = Date()
                }
                byFloor[floor] = area
            } else {
                let area = FloorData(
                    uuid: areaID ?? UUID(), floorNumber: floor,
                    name: floor == 1 ? "Main Area" : "Floor \(floor)",
                    branchId: branchId, sortOrder: floor - 1,
                    isActive: true, isSynced: false, isDeleted: false
                )
                modelContext.insert(area)
                byFloor[floor] = area
                byId[area.uuid] = area
            }
        }
    }

    /// Apply `joined_parent_table_id` links once every merchant table is present locally.
    private func reconcileJoinedParents(
        remoteTables: [[String: Any]],
        modelContext: ModelContext
    ) {
        let localTables = (try? modelContext.fetch(FetchDescriptor<RestaurantTable>())) ?? []
        var tablesById: [UUID: RestaurantTable] = [:]
        for table in localTables {
            tablesById[table.id] = table
        }

        for remoteTable in remoteTables {
            guard let idStr = remoteTable["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let local = tablesById[id],
                  !local.isDeleted,
                  local.isSynced else { continue }

            let parentId: UUID? = {
                guard let parentStr = remoteTable["joined_parent_table_id"] as? String,
                      let parsed = UUID(uuidString: parentStr),
                      parsed != id else { return nil }
                return parsed
            }()

            let desiredParent: RestaurantTable? = {
                guard let parentId,
                      let parent = tablesById[parentId],
                      !parent.isDeleted else { return nil }
                return parent
            }()

            if local.joinedParent?.id != desiredParent?.id {
                local.joinedParent = desiredParent
            }
        }

        // Soft-deleted leaders must not keep live children attached.
        // Mark dirty so the next upload clears joined_parent_table_id remotely.
        for table in localTables where !table.isDeleted {
            if let parent = table.joinedParent, parent.isDeleted {
                table.joinedParent = nil
                table.isSynced = false
                table.updatedAt = Date()
            }
        }
    }

    // Pull active orders from customer mobile app and insert into local SwiftData store
    func pullCustomerOrders(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let operationalBranch = try BranchContext.shared.requireActiveBranch(in: modelContext)
            let remoteOrders = try await NetworkManager.shared.fetchCustomerOrders()
            let activeBranchId = (BranchContext.shared.activeBranchIDString).lowercased()

            // Track all remote order IDs to identify deleted orders later
            var remoteOrderIds = Set<UUID>()

            for remoteOrder in remoteOrders {
                guard let idString = remoteOrder["id"] as? String,
                      let orderId = UUID(uuidString: idString) else { continue }

                remoteOrderIds.insert(orderId)

                // Check if this order already exists locally
                var descriptor = FetchDescriptor<Order>(
                    predicate: #Predicate<Order> { $0.id == orderId }
                )
                descriptor.fetchLimit = 500  // Prevent OOM on large datasets

                let orderNumber = remoteOrder["orderNumber"] as? String ?? "ORD-UNKNOWN"
                let total = remoteOrder["total"] as? Double ?? 0.0
                // Order amount breakdown. Orders created by staff phones / web
                // may send only "total" (subtotal/tax/service left at 0), which
                // makes the POS show "Subtotal 0 / Total 90". Read whatever the
                // server provides; a fallback below derives a consistent
                // breakdown when only the total is present.
                let remoteSubtotal = (remoteOrder["subtotal"] as? Double) ?? 0.0
                let remoteTax = (remoteOrder["tax"] as? Double) ?? 0.0
                let remoteServiceCharge = (remoteOrder["service_charge"] as? Double) ?? (remoteOrder["serviceCharge"] as? Double) ?? 0.0
                let remoteDiscount = (remoteOrder["discount"] as? Double) ?? 0.0

                // Derive a consistent breakdown when the server sent only a total.
                // Prefer server-provided values; otherwise sum item line subtotals,
                // and as a last resort treat the whole total as subtotal so the POS
                // never displays an inconsistent "Subtotal 0 / Total N".
                let itemsSubtotal: Double = {
                    let items = remoteOrder["items"] as? [[String: Any]] ?? []
                    return items.reduce(0.0) { acc, it in
                        let q = (it["quantity"] as? Int) ?? 1
                        let pr = (it["price"] as? Double) ?? 0.0
                        return acc + Double(q) * pr
                    }
                }()
                let effectiveSubtotal = remoteSubtotal > 0 ? remoteSubtotal
                    : (itemsSubtotal > 0 ? itemsSubtotal : total)
                let effectiveTax = remoteTax
                let effectiveServiceCharge = remoteServiceCharge
                let effectiveDiscount = remoteDiscount
                let remoteStatus = remoteOrder["status"] as? String ?? "preparing"
                let createdAtStr = remoteOrder["createdAt"] as? String ?? ""
                let remoteUpdatedAt = remoteDate(
                    remoteOrder["updated_at"] ?? remoteOrder["updatedAt"],
                    fallback: parseISO8601Date(createdAtStr)
                )
                let remoteRowVersion = remoteInt(
                    remoteOrder["rowVersion"] ?? remoteOrder["row_version"],
                    fallback: 0
                )
                let readyAt = parseISO8601DateOptional(remoteOrder["readyAt"])
                let tableNumber = remoteOrder["tableNumber"] as? String ?? ""
                let businessDateKey = remoteOrder["business_date"] as? String ?? remoteOrder["businessDate"] as? String ?? ""
                let registerSessionId = ((remoteOrder["register_session_id"] ?? remoteOrder["registerSessionId"]) as? String).flatMap(UUID.init(uuidString:))

                // Origin channel of the order. Web-ordering orders carry
                // order_source == "web" and must be confirmed by staff before
                // their kitchen/bar/sticker tickets are printed. POS/staff
                // orders default to confirmed. Older rows without the column
                // fall back to "pos" + confirmed to preserve prior behaviour.
                let orderSource = (remoteOrder["orderSource"] as? String)
                    ?? (remoteOrder["order_source"] as? String) ?? "pos"
                let isStaffConfirmed = (remoteOrder["isStaffConfirmed"] as? Bool)
                    ?? (remoteOrder["is_staff_confirmed"] as? Bool)
                    ?? (orderSource != "web")
                // Legacy/remote POS rows can retain an order-level `pending`
                // status after their confirmed items have already advanced to
                // cooking. Keep the order visible on KDS by normalizing the
                // aggregate state alongside the item-level normalization.
                let status = (remoteStatus == "pending" && isStaffConfirmed)
                    ? OrderStatus.preparing
                    : remoteStatus

                let createdAt = parseISO8601Date(createdAtStr)
                let orderType = (remoteOrder["order_type"] as? String) ?? (remoteOrder["orderType"] as? String) ?? "dine_in"
                let queueNumber: String? = {
                    if let s = remoteOrder["queue_number"] as? String, !s.isEmpty { return s }
                    if let s = remoteOrder["queueNumber"] as? String, !s.isEmpty { return s }
                    if let i = remoteOrder["queue_number"] as? Int { return NetworkManager.formatQueueNumber(i) }
                    if let i = remoteOrder["queueNumber"] as? Int { return NetworkManager.formatQueueNumber(i) }
                    return nil
                }()
                let receiptNumber = (remoteOrder["receipt_number"] as? String) ?? (remoteOrder["receiptNumber"] as? String)
                let deliveryBrand = (remoteOrder["delivery_brand"] as? String) ?? (remoteOrder["deliveryBrand"] as? String)
                let platformOrderNumber = (remoteOrder["platform_order_number"] as? String) ?? (remoteOrder["platformOrderNumber"] as? String)
                let cashierName = (remoteOrder["cashier_name"] as? String) ?? (remoteOrder["cashierName"] as? String)

                // Find or match Table Session for this order
                let sessionToken = remoteOrder["sessionToken"] as? String ?? remoteOrder["session_token"] as? String
                let rawTableSessionId = (remoteOrder["table_session_id"] as? String)
                    ?? (remoteOrder["tableSessionId"] as? String)
                var targetTableSession: TableSession? = nil

                // 1. Direct match by table_session_id UUID (primary canonical contract)
                if let rawTableSessionId, let sessionUUID = UUID(uuidString: rawTableSessionId) {
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.id == sessionUUID }
                    )
                    if let sessions = try? modelContext.fetch(sessionDesc), let matchedSession = sessions.first {
                        targetTableSession = matchedSession
                    }
                }

                // 2. Match by session_token
                if targetTableSession == nil, let token = sessionToken, !token.isEmpty {
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.sessionToken == token }
                    )
                    if let sessions = try? modelContext.fetch(sessionDesc), let matchedSession = sessions.first {
                        targetTableSession = matchedSession
                    }
                }

                // 3. Match by table number (canonical match, e.g. T02 == 02 == 2)
                if targetTableSession == nil, !tableNumber.isEmpty, tableNumber != "QUICK" {
                    let targetCanonical = canonicalTableNumber(tableNumber)
                    let allTablesDesc = FetchDescriptor<RestaurantTable>(
                        predicate: #Predicate<RestaurantTable> { !$0.isDeleted }
                    )
                    if let allTables = try? modelContext.fetch(allTablesDesc),
                       let table = allTables.first(where: { canonicalTableNumber($0.tableNumber) == targetCanonical }),
                       let activeSession = table.sessions
                        .filter({ session in
                            session.isOperationallyActive(for: table)
                                // Never migrate a historical order into a newly
                                // opened table session just because the table
                                // number happens to match. Allow a small clock
                                // tolerance for independently timestamped clients.
                                && session.acceptsOrder(createdAt: createdAt)
                        })
                        .max(by: { $0.startedAt < $1.startedAt }) {
                        targetTableSession = activeSession
                    }
                }

                if let existingOrders = try? modelContext.fetch(descriptor), let existingOrder = existingOrders.first {
                    // Reconcile before touching any fields. Pulls can arrive
                    // after an offline edit; applying the remote snapshot
                    // unconditionally would silently erase the local change.
                    // A tombstone is also authoritative locally until its
                    // delete operation is accepted by the server.
                    if existingOrder.isDeleted { continue }
                    let decision = shouldApplyRemoteOrderUpdate(
                        localIsSynced: existingOrder.isSynced,
                        localUpdatedAt: existingOrder.updatedAt,
                        localRowVersion: existingOrder.rowVersion,
                        remoteUpdatedAt: remoteUpdatedAt,
                        remoteRowVersion: remoteRowVersion,
                        source: "SyncEngine.pullCustomerOrders.order"
                    )
                    guard decision == .applyRemote else {
                        // Keep local unsynced/newer data intact. The conflict
                        // journal records the decision for later review.
                        continue
                    }

                    // Order already exists. Update its status, total, and ensure it links to the active session.
                    existingOrder.status = status
                    existingOrder.readyAt = status == OrderStatus.ready ? readyAt : nil
                    existingOrder.isSynced = true // Self-healing sync status
                    // Keep origin channel + confirmation state in sync. Never
                    // downgrade a locally-confirmed web order back to unconfirmed
                    // once staff has approved it on this device.
                    existingOrder.orderSource = orderSource
                    // Never downgrade a local confirm; always adopt remote confirm
                    // so iPhone approve clears iPad "รอยืนยันออเดอร์เว็บ" alerts.
                    if isStaffConfirmed {
                        existingOrder.isStaffConfirmed = true
                    }
                    existingOrder.total = total
                    existingOrder.subtotal = effectiveSubtotal
                    existingOrder.tax = effectiveTax
                    existingOrder.serviceCharge = effectiveServiceCharge
                    existingOrder.discount = effectiveDiscount
                    existingOrder.businessDateKey = businessDateKey
                    existingOrder.registerSessionId = registerSessionId
                    existingOrder.orderType = orderType
                    if let queueNumber { existingOrder.queueNumber = queueNumber }
                    if let receiptNumber, !receiptNumber.isEmpty { existingOrder.receiptNumber = receiptNumber }
                    if let deliveryBrand, !deliveryBrand.isEmpty { existingOrder.deliveryBrand = deliveryBrand }
                    if let platformOrderNumber, !platformOrderNumber.isEmpty { existingOrder.platformOrderNumber = platformOrderNumber }
                    if let cashierName, !cashierName.isEmpty { existingOrder.cashierName = cashierName }
                    existingOrder.rowVersion = remoteRowVersion > 0 ? remoteRowVersion : existingOrder.rowVersion
                    existingOrder.updatedAt = remoteUpdatedAt
                    if let targetTableSession,
                       existingOrder.tableSession?.id != targetTableSession.id {
                        // Preserve historical ownership instead of contaminating
                        // a live cart with an order outside this session window.
                        if targetTableSession.acceptsOrder(createdAt: existingOrder.createdAt) {
                            existingOrder.tableSession = targetTableSession
                        } else {
                            reportSyncFailure(
                                "Rejected stale order/session relationship: \(existingOrder.orderNumber)",
                                soft: true
                            )
                        }
                    }
                    if !tableNumber.isEmpty && tableNumber != "QUICK" {
                        existingOrder.floorTableNumber = tableNumber
                    } else if existingOrder.floorTableNumber == nil,
                              let tableNum = existingOrder.tableSession?.table?.tableNumber,
                              !tableNum.isEmpty {
                        existingOrder.floorTableNumber = tableNum
                    }

                    // Update order items. Do not treat an empty remote item payload as
                    // authoritative for an existing order with local items: Supabase
                    // realtime can deliver the orders event before the order_items batch
                    // is visible, and deleting here makes the iPad appear to lose the order.
                    // An order event can arrive before its order_items event.
                    // If this order was already created locally with no items,
                    // re-fetch the joined order before deciding that the cart
                    // is genuinely empty. Without this recovery path, the
                    // initial empty snapshot was retained forever and Quick
                    // Order showed a zero balance until the app restarted.
                    var remoteItems = remoteOrder["items"] as? [[String: Any]] ?? []
                    if remoteItems.isEmpty && existingOrder.items.isEmpty && total > 0 {
                        if let freshOrders = try? await NetworkManager.shared.fetchCustomerOrders(),
                           let freshOrder = freshOrders.first(where: { ($0["id"] as? String) == idString }),
                           let freshItems = freshOrder["items"] as? [[String: Any]],
                           !freshItems.isEmpty {
                            remoteItems = freshItems
                        }
                    }
                    if !remoteItems.isEmpty || !(remoteItems.isEmpty && !existingOrder.items.isEmpty && total > 0) {
                        let remoteItemIds = Set(remoteItems.compactMap { remoteItem -> UUID? in
                            if let idStr = remoteItem["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // 1. Delete local items that are no longer present on the server
                        for localItem in existingOrder.items {
                            // A locally edited item may be temporarily absent
                            // from a partial/realtime payload. Never delete an
                            // unsynced local item from that incomplete snapshot.
                            if localItem.isSynced && !remoteItemIds.contains(localItem.id) {
                                modelContext.delete(localItem)
                            }
                        }

                        // 2. Add or update remote items
                        for remoteItem in remoteItems {
                            let itemIdStr = remoteItem["id"] as? String ?? ""
                            if let itemId = UUID(uuidString: itemIdStr) {
                                let name = remoteItem["name"] as? String ?? "Unknown Item"
                                let qty = remoteItem["quantity"] as? Int ?? 1
                                let price = remoteItem["price"] as? Double ?? 0.0
                                let lineType = OrderItemLineType(
                                    rawValue: remoteItem["line_type"] as? String
                                        ?? remoteItem["lineType"] as? String
                                        ?? OrderItemLineType.main.rawValue
                                ) ?? .main
                                let itemStatus = remoteItem["status"] as? String ?? "cooking"

                                if let localItem = existingOrder.items.first(where: { $0.id == itemId }) {
                                    let itemUpdatedAt = remoteDate(
                                        remoteItem["updated_at"] ?? remoteItem["updatedAt"],
                                        fallback: existingOrder.updatedAt
                                    )
                                    let itemRowVersion = remoteInt(
                                        remoteItem["rowVersion"] ?? remoteItem["row_version"],
                                        fallback: 0
                                    )
                                    let itemDecision = shouldApplyRemoteOrderUpdate(
                                        localIsSynced: localItem.isSynced,
                                        localUpdatedAt: localItem.updatedAt,
                                        localRowVersion: localItem.rowVersion,
                                        remoteUpdatedAt: itemUpdatedAt,
                                        remoteRowVersion: itemRowVersion,
                                        source: "SyncEngine.pullCustomerOrders.item"
                                    )
                                    guard itemDecision == .applyRemote else { continue }
                                    localItem.quantity = qty
                                    localItem.unitPrice = price
                                    localItem.subtotal = Double(qty) * price
                                    localItem.lineType = lineType.rawValue
                                    localItem.lineTypeVersion = 1
                                    localItem.status = (itemStatus == "pending" && isStaffConfirmed) ? "cooking" : itemStatus
                                    localItem.isSynced = true // Self-healing sync status
                                    let servedBy = remoteItem["served_by"] as? String
                                    localItem.servedBy = servedBy
                                    localItem.rowVersion = remoteInt(remoteItem["rowVersion"] ?? remoteItem["row_version"], fallback: localItem.rowVersion)
                                    localItem.updatedAt = itemUpdatedAt
                                    // Always update itemName from remote data
                                    if !name.isEmpty && name != "Unknown Item" {
                                        localItem.itemName = name
                                    }
                                    // Re-resolve menuItem if it was nil (fix persistent Unknown Item)
                                    if localItem.menuItem == nil {
                                        let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                                        if let menuItemIdStr = menuItemIdStr {
                                            var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                                            idDescriptor.fetchLimit = 1
                                            localItem.menuItem = (try? modelContext.fetch(idDescriptor))?.first
                                        }
                                        if localItem.menuItem == nil && !name.isEmpty && name != "Unknown Item" {
                                            let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                                            localItem.menuItem = (try? modelContext.fetch(nameDescriptor))?.first
                                        }
                                    }
                                    upsertOrderItemModifiers(
                                        for: localItem,
                                        remoteMods: remoteItem["modifiers"] as? [[String: Any]]
                                            ?? remoteItem["order_item_modifiers"] as? [[String: Any]]
                                            ?? [],
                                        modelContext: modelContext
                                    )
                                } else {
                                    // Item was added remotely — look up MenuItem by ID first, then name
                                    let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                                    let menuItem: MenuItem?
                                    if let menuItemIdStr = menuItemIdStr {
                                        var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                                        idDescriptor.fetchLimit = 1  // N3: point lookup
                                        menuItem = (try? modelContext.fetch(idDescriptor))?.first
                                    } else {
                                        let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                                        menuItem = (try? modelContext.fetch(nameDescriptor))?.first
                                    }

                                    let servedBy = remoteItem["served_by"] as? String
                                    let orderItem = OrderItem(
                                        id: itemId,
                                        order: existingOrder,
                                        menuItem: menuItem,
                                        itemName: name,
                                        quantity: qty,
                                        unitPrice: price,
                                        lineType: lineType,
                                        notes: nil,
                                        status: itemStatus,
                                        servedBy: servedBy,
                                        isSynced: true,
                                        rowVersion: remoteInt(remoteItem["rowVersion"] ?? remoteItem["row_version"])
                                    )
                                    modelContext.insert(orderItem)
                                    orderItem.order = existingOrder
                                    orderItem.isSynced = true
                                    existingOrder.items.append(orderItem)
                                    upsertOrderItemModifiers(
                                        for: orderItem,
                                        remoteMods: remoteItem["modifiers"] as? [[String: Any]]
                                            ?? remoteItem["order_item_modifiers"] as? [[String: Any]]
                                            ?? [],
                                        modelContext: modelContext
                                    )
                                }
                            }
                        }
                    }

                    // Update order payments
                    if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                        let remotePaymentIds = Set(remotePayments.compactMap { remotePayment -> UUID? in
                            if let idStr = remotePayment["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // Never discard a locally-created payment before syncPayments uploads it.
                        for localPayment in existingOrder.payments {
                            if localPayment.isSynced && !remotePaymentIds.contains(localPayment.id) {
                                modelContext.delete(localPayment)
                            }
                        }

                        // 2. Add or update remote payments
                        for remotePayment in remotePayments {
                            let paymentIdStr = remotePayment["id"] as? String ?? ""
                            if let paymentId = UUID(uuidString: paymentIdStr) {
                                let amount = remotePayment["amount"] as? Double ?? 0.0
                                let method = remotePayment["paymentMethod"] as? String ?? "cash"
                                let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                                let pCreatedAt = parseISO8601Date(pCreatedAtStr)
                                let pBusinessDate = remotePayment["business_date"] as? String ?? remotePayment["businessDate"] as? String ?? ""
                                let pRegisterSessionId = ((remotePayment["register_session_id"] ?? remotePayment["registerSessionId"]) as? String).flatMap(UUID.init(uuidString:))

                                let ledgerPayment: Payment
                                if let localPayment = existingOrder.payments.first(where: { $0.id == paymentId }) {
                                    localPayment.amount = amount
                                    localPayment.paymentMethod = method
                                    localPayment.paidAt = pCreatedAt
                                    localPayment.businessDateKey = pBusinessDate
                                    localPayment.registerSessionId = pRegisterSessionId
                                    ledgerPayment = localPayment
                                } else {
                                    // Payment was added remotely, create it locally
                                    let newPayment = Payment(
                                        id: paymentId,
                                        order: existingOrder,
                                        paymentMethod: method,
                                        amount: amount,
                                        status: "completed",
                                        paidAt: pCreatedAt,
                                        businessDateKey: pBusinessDate,
                                        registerSessionId: pRegisterSessionId,
                                        isSynced: true // Already synced on server
                                    )
                                    modelContext.insert(newPayment)
                                    existingOrder.payments.append(newPayment)
                                    ledgerPayment = newPayment
                                }
                                AccountingLedgerService.recordCapturedPayment(ledgerPayment, order: existingOrder, in: modelContext)
                            }
                        }
                    }
                    modelContext.saveWithLogging(label: #function)
                    continue
                }

                // FIX: retry inline ก่อนสร้าง Order — ถ้ายังไม่มี items หลัง retry ก็ยังสร้าง Order
                // เพื่อป้องกัน order หายไปจาก SwiftData (เดิม: continue ทิ้ง order ทันที)
                var effectiveItems = remoteOrder["items"] as? [[String: Any]] ?? []
                if effectiveItems.isEmpty && total > 0 {
                    #if DEBUG
                    print("SyncEngine [Pull]: Order \(orderNumber) has no items yet — retrying fetch inline.")
                    #endif
                    // Retry up to 3 รอบ (0.8s, 1.5s, 2.0s) ก่อน fall through สร้าง Order
                    for retryWait: UInt64 in [800_000_000, 1_500_000_000, 2_000_000_000] {
                        try? await Task.sleep(nanoseconds: retryWait)
                        if let freshOrders = try? await NetworkManager.shared.fetchCustomerOrders(),
                           let match = freshOrders.first(where: { ($0["id"] as? String) == idString }),
                           let freshItems = match["items"] as? [[String: Any]], !freshItems.isEmpty {
                            effectiveItems = freshItems
                            break
                        }
                    }
                    // ไม่ continue — fall through เสมอเพื่อสร้าง Order ใน SwiftData
                    // ถ้า items ยังว่าง iPhone self-healing polling จะ patch items ทีหลัง
                }

                let resolvedFloorTable: String? = {
                    guard !tableNumber.isEmpty, tableNumber != "QUICK" else { return nil }
                    return tableNumber
                }()

                // Create new Order
                let newOrder = Order(
                    id: orderId,
                    orderNumber: orderNumber,
                    tableSession: targetTableSession,
                    orderType: orderType,
                    status: status,
                    subtotal: effectiveSubtotal,
                    tax: effectiveTax,
                    serviceCharge: effectiveServiceCharge,
                    orderSource: orderSource,
                    isStaffConfirmed: isStaffConfirmed,
                    discount: effectiveDiscount,
                    total: total,
                    createdAt: createdAt,
                    businessDateKey: businessDateKey,
                    registerSessionId: registerSessionId,
                    readyAt: readyAt,
                    branch: operationalBranch,
                    receiptNumber: receiptNumber,
                    cashierName: cashierName ?? "Staff",
                    queueNumber: queueNumber,
                    deliveryBrand: deliveryBrand,
                    floorTableNumber: resolvedFloorTable,
                    isSynced: true, // Already synced on server
                    rowVersion: remoteInt(remoteOrder["rowVersion"] ?? remoteOrder["row_version"])
                )
                if let platformOrderNumber, !platformOrderNumber.isEmpty {
                    newOrder.platformOrderNumber = platformOrderNumber
                }

                modelContext.insert(newOrder)

                // Map items
                if !effectiveItems.isEmpty {
                    let remoteItems = effectiveItems
                    for remoteItem in remoteItems {
                        let name = remoteItem["name"] as? String ?? "Unknown Item"
                        let qty = remoteItem["quantity"] as? Int ?? 1
                        let price = remoteItem["price"] as? Double ?? 0.0
                        let lineType = OrderItemLineType(
                            rawValue: remoteItem["line_type"] as? String
                                ?? remoteItem["lineType"] as? String
                                ?? OrderItemLineType.main.rawValue
                        ) ?? .main
                        let itemStatus = remoteItem["status"] as? String ?? "cooking"
                        let itemIdStr = remoteItem["id"] as? String ?? ""
                        let itemId = UUID(uuidString: itemIdStr) ?? UUID()

                        // Find local MenuItem by ID first, then fall back to name match
                        let menuItemIdStr = remoteItem["item_id"] as? String ?? remoteItem["itemId"] as? String ?? remoteItem["menu_item_id"] as? String ?? remoteItem["menuItemId"] as? String
                        let localItem: MenuItem?
                        if let menuItemIdStr = menuItemIdStr {
                            var idDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemIdStr })
                            idDescriptor.fetchLimit = 1  // N3: point lookup
                            localItem = (try? modelContext.fetch(idDescriptor))?.first
                        } else {
                            let nameDescriptor = FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.name == name })
                            localItem = (try? modelContext.fetch(nameDescriptor))?.first
                        }

                        let servedBy = remoteItem["served_by"] as? String
                        let resolvedItemStatus = (itemStatus == "pending" && isStaffConfirmed) ? "cooking" : itemStatus
                        let orderItem = OrderItem(
                            id: itemId,
                            order: newOrder,
                            menuItem: localItem,
                            itemName: name,
                            quantity: qty,
                            unitPrice: price,
                            lineType: lineType,
                            notes: nil,
                            status: resolvedItemStatus,
                            servedBy: servedBy,
                            isSynced: true,
                            rowVersion: remoteInt(remoteItem["rowVersion"] ?? remoteItem["row_version"])
                        )
                        modelContext.insert(orderItem)
                        orderItem.order = newOrder
                        orderItem.isSynced = true
                        newOrder.items.append(orderItem)
                        upsertOrderItemModifiers(
                            for: orderItem,
                            remoteMods: remoteItem["modifiers"] as? [[String: Any]]
                                ?? remoteItem["order_item_modifiers"] as? [[String: Any]]
                                ?? [],
                            modelContext: modelContext
                        )
                    }
                }

                // Map payments
                if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                    for remotePayment in remotePayments {
                        let paymentIdStr = remotePayment["id"] as? String ?? ""
                        let paymentId = UUID(uuidString: paymentIdStr) ?? UUID()
                        let amount = remotePayment["amount"] as? Double ?? 0.0
                        let method = remotePayment["paymentMethod"] as? String ?? "cash"
                        let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                        let pCreatedAt = parseISO8601Date(pCreatedAtStr)
                        let pBusinessDate = remotePayment["business_date"] as? String ?? remotePayment["businessDate"] as? String ?? ""
                        let pRegisterSessionId = ((remotePayment["register_session_id"] ?? remotePayment["registerSessionId"]) as? String).flatMap(UUID.init(uuidString:))

                        let newPayment = Payment(
                            id: paymentId,
                            order: newOrder,
                            paymentMethod: method,
                            amount: amount,
                            status: "completed",
                            paidAt: pCreatedAt,
                            businessDateKey: pBusinessDate,
                            registerSessionId: pRegisterSessionId,
                            isSynced: true // Already synced on server
                        )
                        modelContext.insert(newPayment)
                        newOrder.payments.append(newPayment)
                        AccountingLedgerService.recordCapturedPayment(newPayment, order: newOrder, in: modelContext)
                    }
                }

                try modelContext.save()

                if NotificationDeliveryPolicy.shouldDeliverPulledEvent(
                    isFirstSync: self.isFirstSync,
                    createdAt: createdAt
                ) {
                    // 1. In-app banner (foreground) — ทุก order รวม Quick
                    self.triggerLocalNotification(
                        orderNumber: orderNumber,
                        tableNumber: tableNumber,
                        queueNumber: queueNumber,
                        orderType: orderType
                    )
                    // 2. NotificationStore (Notification Center iPad) — ทุก order รวม Quick
                    self.alertNewCustomerOrder(
                        orderNumber: orderNumber,
                        tableNumber: tableNumber,
                        itemCount: (remoteOrder["items"] as? [[String: Any]])?.count ?? 0,
                        queueNumber: queueNumber
                    )
                }

                #if DEBUG
                print("SyncEngine [Pull]: Inserted customer order \(orderNumber) for Table \(tableNumber) successfully.")
                #endif
            }

            // Delete local synced orders belonging to active table sessions that are confirmed removed on server
            // Guard: never delete recently synced orders (within 5 mins) to prevent race conditions
            let orderDescriptor = FetchDescriptor<Order>()
            if !remoteOrderIds.isEmpty, let localOrders = try? modelContext.fetch(orderDescriptor) {
                let now = Date()
                for localOrder in localOrders {
                    let branchMatches = localOrder.branch.id.uuidString.lowercased() == activeBranchId
                    if localOrder.isSynced
                        && !localOrder.isDeleted
                        && branchMatches
                        && localOrder.tableSession?.isActive == true {
                        if !remoteOrderIds.contains(localOrder.id) {
                            let age = now.timeIntervalSince(localOrder.updatedAt)
                            if age > 300 {
                                modelContext.delete(localOrder)
                                #if DEBUG
                                print("SyncEngine [Pull]: Deleted local order \(localOrder.orderNumber) because it was removed from the server (age: \(Int(age))s).")
                                #endif
                            }
                        }
                    }
                }
                modelContext.saveWithLogging(label: #function)
            }

            // Keep sidebar badge / Notification Center live queue in sync even when
            // the user is on Tables (NC is not mounted to rebuild on its own).
            refreshLiveOperationalAlerts(modelContext: modelContext)

        } catch {
            encounteredSyncError = true
            print("SyncEngine [Pull Customer Orders Error]: \(error.localizedDescription)")
        }
    }

    func pullActiveSessions(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteSessions = try await NetworkManager.shared.fetchActiveSessions()
            let activeBranchId = BranchContext.shared.activeBranchIDString

            // ─────────────────────────────────────────────────────────────────
            // FIX: Merge deactivate + activate into a single pass per table.
            // Previously this was 2 separate passes which caused SwiftUI @Query
            // to see intermediate states:
            //   Pass 1 → table.status = "vacant"  (re-render #1 — FLICKER)
            //   Pass 2 → table.status = "occupied" (re-render #2)
            // Now we calculate the desired status first, then write ONCE only
            // if the value actually changed (guard before assign).
            // ─────────────────────────────────────────────────────────────────

            let remoteSessionByTable: [String: [String: Any]] = Dictionary(
                remoteSessions.compactMap { s -> (String, [String: Any])? in
                    guard let tn = s["tableNumber"] as? String else { return nil }
                    return (canonicalTableNumber(tn), s)
                },
                uniquingKeysWith: { first, second in
                    let firstCreatedAt = first["created_at"] as? String ?? ""
                    let secondCreatedAt = second["created_at"] as? String ?? ""
                    return firstCreatedAt >= secondCreatedAt ? first : second
                }
            )
            let remoteSessionByTableID: [UUID: [String: Any]] = Dictionary(
                remoteSessions.compactMap { session -> (UUID, [String: Any])? in
                    guard let rawID = session["tableId"] as? String,
                          let tableID = UUID(uuidString: rawID) else { return nil }
                    return (tableID, session)
                },
                uniquingKeysWith: { first, second in
                    let firstCreatedAt = first["created_at"] as? String ?? ""
                    let secondCreatedAt = second["created_at"] as? String ?? ""
                    return firstCreatedAt >= secondCreatedAt ? first : second
                }
            )

            // Single pass over all local tables
            let allTablesDescriptor = FetchDescriptor<RestaurantTable>()
            if let allTables = try? modelContext.fetch(allTablesDescriptor) {
                for table in allTables {
                    // A server tombstone is authoritative. Never let an old
                    // local session turn a deleted table back to occupied.
                    if table.isDeleted || (!table.branchId.isEmpty && table.branchId.caseInsensitiveCompare(activeBranchId) != .orderedSame) {
                        for activeSession in table.sessions where activeSession.isActive {
                            activeSession.isActive = false
                            activeSession.endedAt = Date()
                            activeSession.isSynced = true
                        }
                        continue
                    }
                    let localTableNumber = table.tableNumber
                    let tableKey = canonicalTableNumber(localTableNumber)
                    let remoteSession = remoteSessionByTableID[table.id] ?? remoteSessionByTable[tableKey]
                    let hasRemoteSession = remoteSession != nil

                    // --- Fetch local active sessions for this table ---
                    // Scope by relationship/UUID, not table number. Number-only
                    // matching can attach a session to a duplicate table from
                    // another area and produce a ghost occupied table.
                    let localActiveSessions = table.sessions.filter { $0.isActive }
                    // A just-opened local session is authoritative while its
                    // insert propagates through PostgREST/realtime. Without a
                    // short grace window, an immediately-following pull can
                    // observe the previous remote snapshot and bounce the user
                    // back to POS's "select a table" empty state.
                    let recentLocalOpen = localActiveSessions
                        .filter { $0.isActive && !$0.isDeleted }
                        .max(by: { $0.startedAt < $1.startedAt })
                        .flatMap { session -> TableSession? in
                            Date().timeIntervalSince(session.startedAt) < 30 ? session : nil
                        }

                    // Local cashier cleared this table (vacant/cleaning/reserved)
                    // but push may still be in flight. Do not resurrect a remote
                    // ghost active session — that caused status to "bounce back"
                    // after reopen / next syncAll.
                    let localPendingClear = !table.isSynced
                        && table.status.lowercased() != "occupied"
                        && recentLocalOpen == nil

                    if hasRemoteSession, let rs = remoteSession, !localPendingClear {
                        // ── Table HAS an active remote session ──────────────
                        let sessionToken    = rs["sessionToken"] as? String ?? ""
                        let startedAtStr    = rs["started_at"] as? String ?? rs["created_at"] as? String ?? ""
                        let startedAt       = parseISO8601Date(startedAtStr)
                        let remoteGuestCount = (rs["guest_count"] as? Int) ?? (rs["guestCount"] as? Int) ?? 2
                        let remoteCashierName = rs["cashier_name"] as? String ?? rs["cashierName"] as? String ?? ""
                        let idStr           = rs["id"] as? String ?? ""
                        let sessionId       = UUID(uuidString: idStr) ?? UUID()

                        // Reject orphaned active rows before they can repaint a
                        // vacant table or reattach old orders. A valid session
                        // needs a real timestamp, must be within the bounded
                        // service window, and cannot predate a later clear.
                        let sessionAge = Date().timeIntervalSince(startedAt)
                        let timestampMissing = startedAtStr.isEmpty
                        let invalidAge = sessionAge < -(5 * 60)
                            || sessionAge > TableSession.maximumOperationalAge
                        let tableWasClearedLater = table.status.lowercased() != "occupied"
                            && table.updatedAt > startedAt
                        let expiredVacantMismatch = table.status.lowercased() == "vacant"
                            && sessionAge > (5 * 60)
                        if timestampMissing || invalidAge || tableWasClearedLater || expiredVacantMismatch {
                            for activeSession in localActiveSessions where activeSession.isActive {
                                activeSession.isActive = false
                                activeSession.endedAt = Date()
                                activeSession.isSynced = false
                                activeSession.updatedAt = Date()
                            }
                            table.status = table.status.lowercased() == "occupied" ? "vacant" : table.status
                            table.isSynced = false
                            table.updatedAt = Date()
                            modelContext.saveWithLogging(label: "SyncEngine.rejectStaleTableSession")
                            Task {
                                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: localTableNumber)
                            }
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Rejected stale/inconsistent session for Table \(localTableNumber)")
                            #endif
                            continue
                        }

                        // A payment can commit locally/atomically while a
                        // realtime snapshot still reports the previous active
                        // table session. If every local order for this table is
                        // already settled and the remote session predates the
                        // latest settlement, this is an orphan session—not a
                        // new guest. Recreating it makes the table appear
                        // occupied with a badge while POS correctly shows no
                        // products. Keep the local post-checkout state and ask
                        // the server to close the stale row asynchronously.
                        let latestSettledPaymentAt = table.sessions
                            .flatMap(\.orders)
                            .filter { !$0.isDeleted && $0.isSettled }
                            .flatMap { $0.payments }
                            .filter { !$0.isDeleted && $0.isCaptured }
                            .map(\.paidAt)
                            .max()
                        let hasLocalUnpaidOrder = table.sessions
                            .flatMap(\.orders)
                            .contains { !$0.isDeleted && !$0.isSettled && $0.status != "cancelled" }
                        if !hasLocalUnpaidOrder,
                           let latestSettledPaymentAt,
                           startedAt <= latestSettledPaymentAt {
                            for activeSession in localActiveSessions where activeSession.isActive {
                                activeSession.isActive = false
                                activeSession.endedAt = Date()
                                activeSession.isSynced = false
                                activeSession.updatedAt = Date()
                            }
                            let postCheckoutStatus = UserDefaults.standard.object(forKey: "enable_table_cleaning_after_checkout") as? Bool ?? true
                                ? "cleaning" : "vacant"
                            table.status = postCheckoutStatus
                            table.isSynced = false
                            table.updatedAt = Date()
                            modelContext.saveWithLogging(label: "SyncEngine.staleTableSessionReconcile")
                            Task {
                                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: localTableNumber)
                            }
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Ignored orphan remote session for Table \(localTableNumber); latest payment=\(latestSettledPaymentAt)")
                            #endif
                            continue
                        }

                        // Realtime can briefly return the prior session for the
                        // same table after a new local open. Prefer the newer
                        // local token during the propagation grace period.
                        if let recentLocalOpen,
                           recentLocalOpen.sessionToken != sessionToken,
                           recentLocalOpen.startedAt >= startedAt {
                            if table.status != "occupied" {
                                table.status = "occupied"
                                table.isSynced = false
                                table.updatedAt = Date()
                            }
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Keeping newer local open for Table \(localTableNumber)")
                            #endif
                            continue
                        }

                        // An active Cloud session is authoritative even when it
                        // crosses midnight. Restaurants commonly operate past
                        // midnight, so calendar-day age must never auto-close a
                        // table or mutate the server from a read/reconcile pass.
                        // Stale sessions are surfaced by operational checks and
                        // require an explicit close/clear action.

                        var foundMatch = false
                        for activeSession in localActiveSessions {
                            if activeSession.sessionToken == sessionToken {
                                // Update existing matching session (no status change needed)
                                if activeSession.startedAt != startedAt { activeSession.startedAt = startedAt }
                                if activeSession.guestCount != remoteGuestCount { activeSession.guestCount = remoteGuestCount }
                                if !remoteCashierName.isEmpty && activeSession.cashierName != remoteCashierName {
                                    activeSession.cashierName = remoteCashierName
                                }
                                activeSession.isSynced = true
                                activeSession.rowVersion = remoteInt(rs["row_version"])
                                foundMatch = true
                            } else {
                                // Stale local session — close it (no status change yet)
                                if activeSession.isActive {
                                    activeSession.isActive = false
                                    activeSession.endedAt  = Date()
                                    #if DEBUG
                                    print("SyncEngine [Session Pull]: Closed stale session \(activeSession.sessionToken) for Table \(localTableNumber)")
                                    #endif
                                }
                            }
                        }
                        if !foundMatch {
                            // No local active session matches → create one
                            let newSession = TableSession(
                                id: sessionId,
                                sessionToken: sessionToken,
                                startedAt: startedAt,
                                isActive: true,
                                table: table,
                                guestCount: remoteGuestCount,
                                cashierName: remoteCashierName,
                                isSynced: true,
                                rowVersion: remoteInt(rs["row_version"])
                            )
                            modelContext.insert(newSession)
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Created session for Table \(localTableNumber) (\(remoteGuestCount) guests)")
                            #endif
                        }

                        // ── Write status ONCE, only if actually changed ─────
                        if table.status != "occupied" {
                            table.status    = "occupied"
                            table.updatedAt = Date()
                        }

                    } else if hasRemoteSession && localPendingClear {
                        // Keep local clear; ensure no leftover local actives.
                        for activeSession in localActiveSessions where activeSession.isActive {
                            activeSession.isActive = false
                            activeSession.endedAt = Date()
                            activeSession.isSynced = false
                            activeSession.updatedAt = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Skipped remote session for Table \(localTableNumber) — local pending clear (\(table.status))")
                            #endif
                        }
                    } else {
                        // ── Table has NO active remote session ───────────────
                        // Protect unsynced local opens/transfers that have not
                        // pushed yet — otherwise realtime pull kills them.
                        let pendingLocalOpen = localActiveSessions.contains { $0.isActive && !$0.isSynced }
                            || recentLocalOpen != nil
                        if pendingLocalOpen {
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Keeping pending local open for Table \(localTableNumber)")
                            #endif
                            if table.status != "occupied" {
                                table.status = "occupied"
                                table.updatedAt = Date()
                            }
                            continue
                        }

                        let hadSyncedActiveSession = localActiveSessions.contains { $0.isSynced }
                        for activeSession in localActiveSessions {
                            activeSession.isActive = false
                            activeSession.endedAt  = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Closed session for Table \(localTableNumber) — no remote session")
                            #endif
                        }

                        // ── Write status ONCE, only if actually changed ─────
                        // Preserve cleaning/reserved — only clear occupied→vacant.
                        let expectedStatus = "vacant"
                        if table.status != expectedStatus
                            && table.status == "occupied"
                            && (table.isSynced || hadSyncedActiveSession) {
                            table.status    = expectedStatus
                            table.isSynced  = false
                            table.updatedAt = Date()
                        }
                    }
                }
            }

            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Sessions Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncServiceRequests() async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteRequests = try await NetworkManager.shared.fetchServiceRequests()
            var newRequests: [ServiceRequest] = []
            for req in remoteRequests {
                if let id = req["id"] as? String,
                   let tableNum = req["tableNumber"] as? String,
                   let type = req["requestType"] as? String,
                   let status = req["status"] as? String,
                   let createdAt = req["createdAt"] as? String {
                    let request = ServiceRequest(
                        id: id,
                        tableNumber: tableNum,
                        requestType: type,
                        status: status,
                        createdAt: createdAt,
                        restaurantTableId: req["restaurantTableId"] as? String,
                        diningAreaId: req["diningAreaId"] as? String,
                        expiresAt: req["expiresAt"] as? String
                    )
                    newRequests.append(request)

                    if status == "pending" {
                        let alreadyNotified = self.notifiedRequestIds.contains(id)
                        if !alreadyNotified {
                            self.notifiedRequestIds.insert(id)
                            let created = self.parseISO8601DateOptional(createdAt)
                            // Seed dedupe state on cold start without replaying
                            // old pending requests as newly arrived events.
                            if NotificationDeliveryPolicy.shouldDeliverPulledEvent(
                                isFirstSync: self.isFirstSync,
                                createdAt: created
                            ) {
                                self.triggerServiceRequestNotification(tableNumber: tableNum, requestType: type)
                            }
                        }
                    }
                }
            }

            await MainActor.run {
                self.activeRequests = newRequests
                // Prune IDs for requests no longer active to prevent unbounded growth
                self.notifiedRequestIds = self.notifiedRequestIds.intersection(Set(newRequests.map { $0.id }))
                // Service-request rows are part of the live NC queue + sidebar badge.
                self.refreshLiveOperationalAlerts()
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Service Requests Sync Error]: \(error.localizedDescription)")
        }
    }

    func pullEmployees(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let remoteEmployees = try await NetworkManager.shared.fetchEmployees()
            let activeBranchId = (BranchContext.shared.activeBranchIDString).lowercased()
            let remoteEmployeeIds = Set(remoteEmployees.compactMap { row -> UUID? in
                guard let value = row["id"] as? String else { return nil }
                return UUID(uuidString: value)
            })
            var localUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []

            func canonicalUser(id: UUID?, username: String) -> User? {
                // A server-issued foreign key is authoritative. Never replace an
                // ID match with a username match: usernames are mutable and are
                // not safe identity keys.
                if let id {
                    return localUsers.first(where: { $0.id == id && !$0.isDeleted })
                }
                guard !username.isEmpty else { return nil }
                return localUsers
                    .filter {
                    !$0.isDeleted &&
                    $0.username.caseInsensitiveCompare(username) == .orderedSame
                    }
                    .max(by: { $0.updatedAt < $1.updatedAt })
            }

            for remoteEmp in remoteEmployees {
                guard let idStr = remoteEmp["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }

                let firstName = remoteEmp["first_name"] as? String ?? ""
                let lastName = remoteEmp["last_name"] as? String ?? ""
                let phone = remoteEmp["phone"] as? String
                let nationalId = remoteEmp["national_id"] as? String
                let bankAccountNumber = remoteEmp["bank_account_number"] as? String
                let bankName = remoteEmp["bank_name"] as? String
                let employmentType = remoteEmp["employment_type"] as? String ?? "hourly"
                let payRate = remoteDouble(remoteEmp["pay_rate"], fallback: 0.0)
                let email = remoteEmp["email"] as? String
                let address = remoteEmp["address"] as? String
                let emergencyContactName = remoteEmp["emergency_contact_name"] as? String
                let emergencyContactPhone = remoteEmp["emergency_contact_phone"] as? String
                let isDeleted = remoteBool(remoteEmp["is_deleted"], fallback: false)
                let employeeBranchId = (remoteEmp["branch_id"] as? String ?? "").lowercased()
                let staffAppEnabled = remoteBool(remoteEmp["staff_app_enabled"], fallback: false)

                let joinedAtStr = remoteEmp["joined_at"] as? String ?? ""
                let joinedAt = parseISO8601Date(joinedAtStr)

                let updatedAtStr = remoteEmp["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                // Extra auth fields stored in Supabase employees table
                let username = remoteEmp["username"] as? String ?? ""
                let pinCode = remoteEmp["pin_code"] as? String ?? ""
                // users.role_id is canonical. employees.role is retained only
                // as a legacy mirror for older clients and must not override
                // an already-resolved User role during reconciliation.
                let legacyRoleName = remoteEmp["role"] as? String ?? "Staff"
                let remoteUserId = (remoteEmp["user_id"] as? String).flatMap(UUID.init(uuidString:))

                // Resolve matching Role
                let roleDescriptor = FetchDescriptor<Role>(
                    predicate: #Predicate<Role> { $0.name == legacyRoleName }
                )
                let matchedRoles = try? modelContext.fetch(roleDescriptor)
                let legacyRole = matchedRoles?.first ?? {
                    let newRole = Role(name: legacyRoleName, roleDescription: "\(legacyRoleName) Privileges", permissionKeys: "")
                    modelContext.insert(newRole)
                    return newRole
                }()

                // Try to find existing employee by exact ID
                let idDescriptor = FetchDescriptor<Employee>(
                    predicate: #Predicate<Employee> { $0.id == id }
                )

                // Preserve HR history while preventing a stale duplicate login
                // profile. Supabase is canonical, but hard-deleting an Employee
                // here can cascade into shifts/timecards and makes Staff Lock
                // visibly flicker during reconciliation.
                if let allLocalEmps = try? modelContext.fetch(FetchDescriptor<Employee>()) {
                    for localEmp in allLocalEmps {
                        if localEmp.id != id {
                            let isNameMatch = (localEmp.firstName == firstName && localEmp.lastName == lastName)
                            let isUsernameMatch = (!username.isEmpty && localEmp.user?.username == username)

                            if isNameMatch || isUsernameMatch {
                                localEmp.isDeleted = true
                                localEmp.isSynced = true
                                localEmp.updatedAt = max(localEmp.updatedAt, updatedAt)
                                localEmp.user?.isActive = false
                                localEmp.user?.isDeleted = true
                            }
                        }
                    }
                }

                if let matches = try? modelContext.fetch(idDescriptor), let existing = matches.first {
                    // Relationship integrity is independent from scalar LWW.
                    // Even when the local Employee is newer, the server-issued
                    // employees.user_id remains the canonical foreign key and
                    // must be repaired. Previously this lived inside
                    // `.applyRemote`, leaving employee.user nil after User
                    // de-duplication and hiding an otherwise valid profile from
                    // the iPad staff lock screen.
                    if let remoteUserId, existing.user?.id != remoteUserId {
                        if let canonical = canonicalUser(id: remoteUserId, username: username) {
                            existing.user = canonical
                        } else {
                            let canonical = User(
                                id: remoteUserId,
                                username: username,
                                email: email,
                                passwordHash: "",
                                pinCodeHash: pinCode,
                                role: legacyRole,
                                isActive: true,
                                isSynced: true,
                                isDeleted: false,
                                updatedAt: updatedAt
                            )
                            modelContext.insert(canonical)
                            localUsers.append(canonical)
                            existing.user = canonical
                        }
                    } else if existing.user == nil,
                              let canonical = canonicalUser(id: nil, username: username) {
                        // Legacy rows without employees.user_id may use the
                        // merchant-scoped username only as a migration fallback.
                        existing.user = canonical
                    }

                    // Prefer the role already loaded from users.role_id. The
                    // legacy employee role is only a recovery fallback for old
                    // rows whose User role is genuinely unavailable.
                    let canonicalRole = existing.user?.role ?? legacyRole

                    // Never overwrite an unsynced local edit after its push has
                    // failed. The shared conflict policy keeps the local value
                    // queued for the next retry instead of restoring stale cloud data.
                    let decision = shouldApplyRemoteUpdate(
                        localIsSynced: existing.isSynced,
                        localUpdatedAt: existing.updatedAt,
                        remoteUpdatedAt: updatedAt
                    )
                    if case .applyRemote = decision {
                        existing.firstName = firstName
                        existing.lastName = lastName
                        existing.phone = phone
                        existing.nationalId = nationalId
                        existing.bankAccountNumber = bankAccountNumber
                        existing.bankName = bankName
                        existing.employmentType = employmentType
                        existing.payRate = payRate
                        existing.email = email
                        existing.address = address
                        existing.emergencyContactName = emergencyContactName
                        existing.emergencyContactPhone = emergencyContactPhone
                        existing.joinedAt = joinedAt
                        existing.isDeleted = isDeleted
                        existing.branchId = employeeBranchId
                        existing.staffAppEnabled = staffAppEnabled
                        existing.faceEmbeddingNeedsRemoteClear = false
                        existing.isSynced = true
                        existing.updatedAt = updatedAt

                        // Sync associated User details
                        if let user = existing.user {
                            user.username = username
                            // users.pin_code_hash is canonical. Only use the
                            // legacy employee value as a non-destructive fallback.
                            if (user.pinCodeHash == nil || user.pinCodeHash?.isEmpty == true),
                               !pinCode.isEmpty {
                                user.pinCodeHash = pinCode
                            }
                            if user.role == nil { user.role = canonicalRole }
                        } else {
                            if let user = canonicalUser(id: remoteUserId, username: username) {
                                if user.pinCodeHash == nil || user.pinCodeHash?.isEmpty == true {
                                    user.pinCodeHash = pinCode
                                }
                                if user.role == nil { user.role = canonicalRole }
                                existing.user = user
                            } else {
                                let newUser = User(
                                    // Preserve the canonical server identity when
                                    // employees.user_id is available.
                                    id: remoteUserId ?? UUID(),
                                    username: username,
                                    email: email,
                                    passwordHash: SecurityHelper.sha256("password"),
                                    pinCodeHash: pinCode,
                                    role: canonicalRole,
                                    isActive: true,
                                    isSynced: true,
                                    isDeleted: false,
                                    updatedAt: Date()
                                )
                                modelContext.insert(newUser)
                                localUsers.append(newUser)
                                existing.user = newUser
                            }
                        }
                    }
                } else if !isDeleted {
                    // Insert new employee
                    let employeeUser: User
                    if let user = canonicalUser(id: remoteUserId, username: username) {
                        if user.pinCodeHash == nil || user.pinCodeHash?.isEmpty == true {
                            user.pinCodeHash = pinCode
                        }
                        if user.role == nil { user.role = legacyRole }
                        employeeUser = user
                    } else {
                        let newUser = User(
                            // Preserve the canonical server identity when
                            // employees.user_id is available.
                            id: remoteUserId ?? UUID(),
                            username: username,
                            email: email,
                            passwordHash: SecurityHelper.sha256("password"),
                            pinCodeHash: pinCode,
                            role: legacyRole,
                            isActive: true,
                            isSynced: true,
                            isDeleted: false,
                            updatedAt: Date()
                        )
                        modelContext.insert(newUser)
                        localUsers.append(newUser)
                        employeeUser = newUser
                    }

                    let newEmp = Employee(
                        id: id,
                        user: employeeUser,
                        firstName: firstName,
                        lastName: lastName,
                        phone: phone,
                        nationalId: nationalId,
                        bankAccountNumber: bankAccountNumber,
                        bankName: bankName,
                        employmentType: employmentType,
                        payRate: payRate,
                        joinedAt: joinedAt,
                        branchId: employeeBranchId,
                        staffAppEnabled: staffAppEnabled,
                        email: email,
                        address: address,
                        emergencyContactName: emergencyContactName,
                        emergencyContactPhone: emergencyContactPhone,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newEmp)
                }
            }

            // A valid, merchant-scoped response is authoritative for login
            // availability. Retain missing synced employees as soft-deleted
            // history rather than allowing stale iPad cache profiles to remain.
            if let localEmployees = try? modelContext.fetch(FetchDescriptor<Employee>()) {
                for localEmployee in localEmployees
                where localEmployee.isSynced
                    && localEmployee.branchId.lowercased() == activeBranchId
                    && !remoteEmployeeIds.contains(localEmployee.id) {
                    localEmployee.isDeleted = true
                    localEmployee.updatedAt = Date()
                    localEmployee.user?.isActive = false
                    localEmployee.user?.isDeleted = true
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Employee Pull Error]: \(error.localizedDescription)")
        }
    }

    func pullEmployeeShifts(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let remoteShifts = try await NetworkManager.shared.fetchEmployeeShifts()

            for remoteShift in remoteShifts {
                guard let idStr = remoteShift["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let employeeIdStr = remoteShift["employee_id"] as? String,
                      let employeeId = UUID(uuidString: employeeIdStr) else { continue }

                let scheduledStartStr = remoteShift["scheduled_start"] as? String ?? ""
                let scheduledEndStr = remoteShift["scheduled_end"] as? String ?? ""
                let scheduledStart = parseISO8601Date(scheduledStartStr)
                let scheduledEnd = parseISO8601Date(scheduledEndStr)

                let role = remoteShift["role"] as? String
                let notes = remoteShift["notes"] as? String
                let isDeleted = remoteBool(remoteShift["is_deleted"], fallback: false)

                let updatedAtStr = remoteShift["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                // Get employee relation
                let empDescriptor = FetchDescriptor<Employee>(
                    predicate: #Predicate<Employee> { $0.id == employeeId }
                )
                guard let employees = try? modelContext.fetch(empDescriptor), let employee = employees.first else {
                    print("SyncEngine [EmployeeShift Pull Warning]: Referenced employee \(employeeId) not found locally.")
                    continue
                }

                // Check for existing shift
                let idDescriptor = FetchDescriptor<EmployeeShift>(
                    predicate: #Predicate<EmployeeShift> { $0.id == id }
                )

                if let matches = try? modelContext.fetch(idDescriptor), let existing = matches.first {
                    if updatedAt > existing.updatedAt || !existing.isSynced {
                        existing.employee = employee
                        existing.scheduledStart = scheduledStart
                        existing.scheduledEnd = scheduledEnd
                        existing.role = role
                        existing.notes = notes
                        existing.isDeleted = isDeleted
                        existing.isSynced = true
                        existing.updatedAt = updatedAt

                        if isDeleted {
                            modelContext.delete(existing)
                        }
                    }
                } else if !isDeleted {
                    let newShift = EmployeeShift(
                        id: id,
                        employee: employee,
                        scheduledStart: scheduledStart,
                        scheduledEnd: scheduledEnd,
                        role: role,
                        notes: notes,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newShift)
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [EmployeeShift Pull Error]: \(error.localizedDescription)")
        }
    }

    /// Upsert nested `order_item_modifiers` from a customer-order pull join.
    func upsertOrderItemModifiers(
        for orderItem: OrderItem,
        remoteMods: [[String: Any]],
        modelContext: ModelContext
    ) {
        guard !remoteMods.isEmpty else { return }

        let remoteIds = Set(remoteMods.compactMap { ($0["id"] as? String)?.lowercased() })

        for local in orderItem.modifiers where !remoteIds.contains(local.id.uuidString.lowercased()) {
            // Soft-remove modifiers that disappeared on the server.
            if local.isSynced {
                modelContext.delete(local)
            }
        }

        for remote in remoteMods {
            guard let idStr = remote["id"] as? String,
                  let id = UUID(uuidString: idStr) else { continue }
            if let deleted = remote["is_deleted"] as? Bool, deleted { continue }

            let price = (remote["price"] as? Double) ?? remoteDouble(remote["price"])
            var modifier: Modifier?
            if let mid = remote["modifier_id"] as? String, let mUUID = UUID(uuidString: mid) {
                modifier = (try? modelContext.fetch(
                    FetchDescriptor<Modifier>(predicate: #Predicate<Modifier> { $0.id == mUUID })
                ))?.first
            }

            if let local = orderItem.modifiers.first(where: { $0.id == id }) {
                local.price = price
                if let modifier { local.modifier = modifier }
                local.isSynced = true
                local.updatedAt = remoteDate(remote["updated_at"], fallback: Date())
            } else {
                let oim = OrderItemModifier(
                    id: id,
                    orderItem: orderItem,
                    modifier: modifier,
                    price: price,
                    isSynced: true,
                    isDeleted: false,
                    updatedAt: remoteDate(remote["updated_at"], fallback: Date())
                )
                modelContext.insert(oim)
                orderItem.modifiers.append(oim)
            }
        }
    }
}
