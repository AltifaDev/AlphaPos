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

    /// Verifies if the transaction notes contain a matching cryptographic signature.
    static func verifyTransaction(_ transaction: InventoryTransaction) -> Bool {
        let clean = cleanNotes(transaction.notes)
        let expectedSig = generateSignature(
            id: transaction.id,
            type: transaction.transactionType,
            quantity: transaction.quantity,
            costPrice: transaction.costPrice,
            referenceId: transaction.referenceId,
            notes: clean,
            branchId: transaction.branch?.id
        )
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
