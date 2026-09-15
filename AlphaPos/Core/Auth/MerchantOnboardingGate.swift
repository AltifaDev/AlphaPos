import Foundation

/// Mandatory first-time merchant onboarding sequence (banking / SaaS best practice).
/// Progress is stored per `merchant_id` so shared devices cannot leak another store's gates.
enum MerchantOnboardingGate {
    enum Step: String, CaseIterable, Codable, Comparable {
        case account
        case emailVerified
        case shopProfile
        case planAndTerms
        case tenantActivated
        case ownerPin
        case mfaSoftPrompt
        case dashboardReady

        private var rank: Int {
            switch self {
            case .account: return 0
            case .emailVerified: return 1
            case .shopProfile: return 2
            case .planAndTerms: return 3
            case .tenantActivated: return 4
            case .ownerPin: return 5
            case .mfaSoftPrompt: return 6
            case .dashboardReady: return 7
            }
        }

        static func < (lhs: Step, rhs: Step) -> Bool {
            lhs.rank < rhs.rank
        }

        /// Steps that must be completed before entering the dashboard.
        /// Owner PIN is deferred (Phase 3): required before open shift / store-account unlock.
        static let requiredBeforeDashboard: [Step] = [
            .account, .emailVerified, .shopProfile, .planAndTerms, .tenantActivated,
        ]
    }

    private static let storagePrefix = "merchant_onboarding_gate_"
    private static let legacyGlobalKey = "merchant_onboarding_gate_v1"

    // MARK: - Public API

    static func progress(for merchantId: String) -> Set<Step> {
        let id = normalize(merchantId)
        guard !id.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKey(for: id)),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(raw.compactMap(Step.init(rawValue:)))
    }

    static func markCompleted(_ step: Step, for merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        var steps = progress(for: id)
        steps.insert(step)
        // Completing a later step implies prior wizard steps for returning owners
        // who already have an activated merchant (e.g. login on wiped device).
        if step >= .tenantActivated {
            steps.formUnion([.account, .emailVerified, .shopProfile, .planAndTerms, .tenantActivated])
        }
        if step >= .ownerPin || KeychainManager.shared.isOwnerPinConfigured() {
            steps.insert(.ownerPin)
        }
        persist(steps, for: id)
    }

    static func markCompleted(_ steps: [Step], for merchantId: String) {
        for step in steps {
            markCompleted(step, for: merchantId)
        }
    }

    /// Live evaluation: owner PIN is always checked against Keychain (source of truth).
    static func isCompleted(_ step: Step, for merchantId: String) -> Bool {
        if step == .ownerPin {
            return KeychainManager.shared.isOwnerPinConfigured()
        }
        if step == .mfaSoftPrompt {
            let steps = progress(for: merchantId)
            return steps.contains(.mfaSoftPrompt) || steps.contains(.dashboardReady)
        }
        if step == .dashboardReady {
            return canEnterDashboard(for: merchantId)
        }
        return progress(for: merchantId).contains(step)
    }

    /// Next blocking step, or `nil` when dashboard is allowed.
    static func nextRequiredStep(for merchantId: String) -> Step? {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return .account }

        for step in Step.requiredBeforeDashboard {
            if !isCompleted(step, for: id) {
                return step
            }
        }
        // Soft MFA: not blocking, but surface once if never recorded.
        if !isCompleted(.mfaSoftPrompt, for: id) {
            return .mfaSoftPrompt
        }
        return nil
    }

    static func canEnterDashboard(for merchantId: String) -> Bool {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return false }
        return Step.requiredBeforeDashboard.allSatisfy { isCompleted($0, for: id) }
    }

    /// Returning owner on a wiped device: merchant JWT exists → mark pre-PIN steps done.
    /// PIN remains optional for Dashboard; Staff Lock / shift still enforce it.
    static func bootstrapReturningOwner(merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        markCompleted(
            [.account, .emailVerified, .shopProfile, .planAndTerms, .tenantActivated, .dashboardReady],
            for: id
        )
        if KeychainManager.shared.isOwnerPinConfigured() {
            markCompleted(.ownerPin, for: id)
        }
        // Soft MFA already skippable once; don't re-block returning owners.
        markCompleted(.mfaSoftPrompt, for: id)
    }

    static func clear(for merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: storageKey(for: id))
    }

    /// Clear all per-merchant gate records (tenant wipe / logout).
    static func clearAll() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(storagePrefix) || $0 == legacyGlobalKey
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private

    private static func storageKey(for merchantId: String) -> String {
        storagePrefix + normalize(merchantId)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func persist(_ steps: Set<Step>, for merchantId: String) {
        let raw = steps.map(\.rawValue).sorted()
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: storageKey(for: merchantId))
        }
    }
}
