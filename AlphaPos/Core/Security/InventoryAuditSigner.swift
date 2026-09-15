import Foundation
import CryptoKit

/// Cryptographic utility to generate and verify signatures for inventory transactions to prevent tampering and internal fraud.
enum InventoryAuditSigner {
    private static let salt = "AlphaPosSecureAuditSalt2026"

    /// Generates a SHA256 signature for the given transaction parameters.
    static func generateSignature(
        id: UUID,
        type: String,
        quantity: Double,
        costPrice: Double?,
        referenceId: UUID?,
        notes: String?,
        branchId: UUID?
    ) -> String {
        let clean = cleanNotes(notes) ?? ""
        let dataStr = "\(id.uuidString)-\(type)-\(quantity)-\(costPrice ?? 0.0)-\(referenceId?.uuidString ?? "")-\(clean)-\(branchId?.uuidString ?? "")-\(salt)"
        guard let data = dataStr.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Verifies a transaction's integrity.
    /// Prefers the dedicated `auditSignature` column; falls back to the legacy
    /// signature embedded in `notes` for rows created before the column existed.
    static func verifyTransaction(_ transaction: InventoryTransaction) -> Bool {
        let expectedSig = generateSignature(
            id: transaction.id,
            type: transaction.transactionType,
            quantity: transaction.quantity,
            costPrice: transaction.costPrice,
            referenceId: transaction.referenceId,
            notes: cleanNotes(transaction.notes),
            branchId: transaction.branch.id
        )

        // 1. Modern path — dedicated column.
        if let sig = transaction.auditSignature, !sig.isEmpty {
            return sig == expectedSig
        }

        // 2. Legacy path — signature embedded in notes.
        guard let notes = transaction.notes else { return false }
        return notes.contains("[sig: \(expectedSig)]")
    }

    /// Appends the cryptographic signature tag to the notes field.
    static func appendSignatureToNotes(notes: String?, signature: String) -> String {
        let clean = cleanNotes(notes) ?? ""
        if signature.isEmpty { return clean }
        return "\(clean) [sig: \(signature)]".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleans the signature tag from the notes string for display in the UI.
    static func cleanNotes(_ notes: String?) -> String? {
        guard let notes = notes else { return nil }
        if let range = notes.range(of: " [sig: ") {
            let cleaned = String(notes[..<range.lowerBound])
            return cleaned.isEmpty ? nil : cleaned
        }
        return notes.isEmpty ? nil : notes
    }
}
