// WaitlistEntry.swift
// AlphaPos — L-1: Waitlist / Queue System Model

import Foundation
import SwiftData

@Model
final class WaitlistEntry {
    @Attribute(.unique) var id: UUID
    var guestName: String
    var partySize: Int
    var phone: String?
    var notes: String?
    var status: String          // "waiting", "seated", "cancelled", "no_show"
    var queueNumber: Int        // display order (1, 2, 3…)
    var estimatedWaitMinutes: Int
    var arrivedAt: Date
    var seatedAt: Date?
    var cancelledAt: Date?
    var notifiedAt: Date?       // last time staff called/notified guest

    // Optional — linked to a table when seated
    var seatedTableNumber: String?

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        guestName: String,
        partySize: Int = 2,
        phone: String? = nil,
        notes: String? = nil,
        status: String = "waiting",
        queueNumber: Int = 1,
        estimatedWaitMinutes: Int = 15,
        arrivedAt: Date = Date(),
        seatedAt: Date? = nil,
        cancelledAt: Date? = nil,
        notifiedAt: Date? = nil,
        seatedTableNumber: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.guestName = guestName
        self.partySize = partySize
        self.phone = phone
        self.notes = notes
        self.status = status
        self.queueNumber = queueNumber
        self.estimatedWaitMinutes = estimatedWaitMinutes
        self.arrivedAt = arrivedAt
        self.seatedAt = seatedAt
        self.cancelledAt = cancelledAt
        self.notifiedAt = notifiedAt
        self.seatedTableNumber = seatedTableNumber
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    // MARK: - Helpers

    var waitMinutesElapsed: Int {
        Int(Date().timeIntervalSince(arrivedAt) / 60)
    }

    var isOverdue: Bool { waitMinutesElapsed > estimatedWaitMinutes }

    var statusColor: String {
        switch status {
        case "seated":    return "appTeal"
        case "cancelled", "no_show": return "appRose"
        default: return isOverdue ? "appAmber" : "textSecondary"
        }
    }
}
