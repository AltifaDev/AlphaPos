import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Layout & Config Sync (RestaurantWall, TableLayoutPreset, ReceiptTemplate)
// These models define the physical layout of the restaurant and receipt configurations.
// Syncing ensures consistent floor plan and print settings across all devices.
extension SyncEngine {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - RestaurantWall
    // ──────────────────────────────────────────────────────────────────────

    func syncRestaurantWalls(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<RestaurantWall>(
            predicate: #Predicate<RestaurantWall> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let walls = try? modelContext.fetch(descriptor), !walls.isEmpty else { return }

        for wall in walls {
            do {
                if wall.isDeleted {
                    if try await NetworkManager.shared.deleteRestaurantWallOnServer(id: wall.id) {
                        modelContext.delete(wall)
                    }
                } else if try await NetworkManager.shared.uploadRestaurantWall(wall) {
                    wall.isSynced = true
                    wall.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [RestaurantWall Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullRestaurantWallsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteWalls = try await NetworkManager.shared.fetchRestaurantWallsFromSupabase()
            guard !remoteWalls.isEmpty else { return }

            var __desclocals = FetchDescriptor<RestaurantWall>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteWalls {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeletedRemote {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    if local.isDeleted { continue }
                    local.floor = remoteInt(remote["floor"])
                    local.typeString = remote["type"] as? String ?? local.typeString
                    local.startX = remoteDouble(remote["start_x"])
                    local.startY = remoteDouble(remote["start_y"])
                    local.endX = remoteDouble(remote["end_x"])
                    local.endY = remoteDouble(remote["end_y"])
                    local.controlX = remote["control_x"].flatMap { $0 as? Double }
                    local.controlY = remote["control_y"].flatMap { $0 as? Double }
                    local.strokeWidth = remoteDouble(remote["stroke_width"], fallback: 10.0)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeletedRemote { continue }
                    let wall = RestaurantWall(
                        id: id,
                        floor: remoteInt(remote["floor"]),
                        type: WallType(rawValue: remote["type"] as? String ?? "straight") ?? .straight,
                        startX: remoteDouble(remote["start_x"]),
                        startY: remoteDouble(remote["start_y"]),
                        endX: remoteDouble(remote["end_x"]),
                        endY: remoteDouble(remote["end_y"]),
                        controlX: remote["control_x"].flatMap { $0 as? Double },
                        controlY: remote["control_y"].flatMap { $0 as? Double },
                        strokeWidth: remoteDouble(remote["stroke_width"], fallback: 10.0),
                        isSynced: true,
                        isDeleted: false
                    )
                    wall.updatedAt = updatedAt == .distantPast ? Date() : updatedAt
                    modelContext.insert(wall)
                    localById[idStr.lowercased()] = wall
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [RestaurantWall Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - TableLayoutPreset
    // ──────────────────────────────────────────────────────────────────────

    func syncTableLayoutPresets(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<TableLayoutPreset>(
            predicate: #Predicate<TableLayoutPreset> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let presets = try? modelContext.fetch(descriptor), !presets.isEmpty else { return }

        for preset in presets {
            do {
                if preset.isDeleted {
                    if try await NetworkManager.shared.deleteTableLayoutPresetOnServer(id: preset.id) {
                        modelContext.delete(preset)
                    }
                } else if try await NetworkManager.shared.uploadTableLayoutPreset(preset) {
                    preset.isSynced = true
                    preset.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [TableLayoutPreset Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullTableLayoutPresetsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remotePresets = try await NetworkManager.shared.fetchTableLayoutPresetsFromSupabase()
            guard !remotePresets.isEmpty else { return }

            var __desclocals = FetchDescriptor<TableLayoutPreset>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

            for remote in remotePresets {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if isDeletedRemote {
                        modelContext.delete(local)
                        localById.removeValue(forKey: idStr.lowercased())
                        continue
                    }
                    if local.isDeleted { continue }
                    local.name = name
                    local.floor = remoteInt(remote["floor"])
                    local.branchId = remote["branch_id"] as? String ?? local.branchId
                    local.bgImageFilename = remote["bg_image_filename"] as? String
                    local.bgImageScale = remoteDouble(remote["bg_image_scale"], fallback: 1.0)
                    local.bgImageOffsetX = remoteDouble(remote["bg_image_offset_x"])
                    local.bgImageOffsetY = remoteDouble(remote["bg_image_offset_y"])
                    local.tableLayoutJson = remote["table_layout_json"] as? String ?? local.tableLayoutJson
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    if isDeletedRemote { continue }
                    let preset = TableLayoutPreset(
                        id: id,
                        merchantId: remote["merchant_id"] as? String ?? merchantId,
                        branchId: remote["branch_id"] as? String ?? "",
                        floor: remoteInt(remote["floor"]),
                        name: name,
                        bgImageFilename: remote["bg_image_filename"] as? String,
                        bgImageScale: remoteDouble(remote["bg_image_scale"], fallback: 1.0),
                        bgImageOffsetX: remoteDouble(remote["bg_image_offset_x"]),
                        bgImageOffsetY: remoteDouble(remote["bg_image_offset_y"]),
                        tableLayoutJson: remote["table_layout_json"] as? String ?? "[]",
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        isSynced: true,
                        isDeleted: false
                    )
                    modelContext.insert(preset)
                    localById[idStr.lowercased()] = preset
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [TableLayoutPreset Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - ReceiptTemplate
    // ──────────────────────────────────────────────────────────────────────

    func syncReceiptTemplates(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<ReceiptTemplate>(
            predicate: #Predicate<ReceiptTemplate> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let templates = try? modelContext.fetch(descriptor), !templates.isEmpty else { return }

        for template in templates {
            do {
                if template.isDeleted {
                    if try await NetworkManager.shared.deleteReceiptTemplateOnServer(id: template.id) {
                        modelContext.delete(template)
                    }
                } else if try await NetworkManager.shared.uploadReceiptTemplate(template) {
                    template.isSynced = true
                    template.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [ReceiptTemplate Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullReceiptTemplatesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteTemplates = try await NetworkManager.shared.fetchReceiptTemplatesFromSupabase()
            guard !remoteTemplates.isEmpty else { return }

            var __desclocals = FetchDescriptor<ReceiptTemplate>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteTemplates {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.templateType = remote["template_type"] as? String ?? local.templateType
                    local.headerText = remote["header_text"] as? String
                    local.footerText = remote["footer_text"] as? String
                    local.logoUrl = remote["logo_url"] as? String
                    local.showTaxId = remoteBool(remote["show_tax_id"], fallback: true)
                    local.showCustomerInfo = remoteBool(remote["show_customer_info"], fallback: true)
                    local.isDefault = remoteBool(remote["is_default"])
                    local.paperWidth = remote["paper_width"] as? String ?? local.paperWidth
                    local.showServiceCharge = remoteBool(remote["show_service_charge"], fallback: true)
                    local.showLogo = remoteBool(remote["show_logo"], fallback: true)
                    local.showTableInfo = remoteBool(remote["show_table_info"], fallback: true)
                    local.showQRCode = remoteBool(remote["show_qr_code"], fallback: true)
                    local.showItemModifiers = remoteBool(remote["show_item_modifiers"], fallback: true)
                    local.showOrderType = remoteBool(remote["show_order_type"], fallback: true)
                    local.stickerSize = remote["sticker_size"] as? String ?? local.stickerSize
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let template = ReceiptTemplate(
                        id: id,
                        name: name,
                        templateType: remote["template_type"] as? String ?? "receipt",
                        headerText: remote["header_text"] as? String,
                        footerText: remote["footer_text"] as? String,
                        logoUrl: remote["logo_url"] as? String,
                        showTaxId: remoteBool(remote["show_tax_id"], fallback: true),
                        showCustomerInfo: remoteBool(remote["show_customer_info"], fallback: true),
                        isDefault: remoteBool(remote["is_default"]),
                        paperWidth: remote["paper_width"] as? String ?? "80mm",
                        showServiceCharge: remoteBool(remote["show_service_charge"], fallback: true),
                        showLogo: remoteBool(remote["show_logo"], fallback: true),
                        showTableInfo: remoteBool(remote["show_table_info"], fallback: true),
                        showQRCode: remoteBool(remote["show_qr_code"], fallback: true),
                        showItemModifiers: remoteBool(remote["show_item_modifiers"], fallback: true),
                        showOrderType: remoteBool(remote["show_order_type"], fallback: true),
                        stickerSize: remote["sticker_size"] as? String ?? "40x30",
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(template)
                    localById[idStr.lowercased()] = template
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [ReceiptTemplate Pull Error]: \(error.localizedDescription)")
        }
    }
}
