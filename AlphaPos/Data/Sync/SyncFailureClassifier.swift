import Foundation

/// Maps raw sync/network failures into admin-friendly copy + optional technical detail.
/// Pattern: progressive disclosure (summary first, expand for diagnostics).
enum SyncFailureClassifier {

    enum Kind: String, CaseIterable, Identifiable {
        case staffSchedule
        case permission
        case auth
        case conflict
        case network
        case dataIntegrity
        case unknown

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .staffSchedule: return "sync_issue_staff_schedule_title"
            case .permission: return "sync_issue_permission_title"
            case .auth: return "sync_issue_auth_title"
            case .conflict: return "sync_issue_conflict_title"
            case .network: return "sync_issue_network_title"
            case .dataIntegrity: return "sync_issue_data_title"
            case .unknown: return "sync_issue_unknown_title"
            }
        }

        var bodyKey: String {
            switch self {
            case .staffSchedule: return "sync_issue_staff_schedule_body"
            case .permission: return "sync_issue_permission_body"
            case .auth: return "sync_issue_auth_body"
            case .conflict: return "sync_issue_conflict_body"
            case .network: return "sync_issue_network_body"
            case .dataIntegrity: return "sync_issue_data_body"
            case .unknown: return "sync_issue_unknown_body"
            }
        }

        var actionKey: String {
            switch self {
            case .staffSchedule: return "sync_issue_staff_schedule_action"
            case .permission: return "sync_issue_permission_action"
            case .auth: return "sync_issue_auth_action"
            case .conflict: return "sync_issue_conflict_action"
            case .network: return "sync_issue_network_action"
            case .dataIntegrity: return "sync_issue_data_action"
            case .unknown: return "sync_issue_unknown_action"
            }
        }

        var icon: String {
            switch self {
            case .staffSchedule: return "calendar.badge.exclamationmark"
            case .permission: return "lock.shield"
            case .auth: return "person.badge.key"
            case .conflict: return "arrow.triangle.branch"
            case .network: return "wifi.exclamationmark"
            case .dataIntegrity: return "externaldrive.badge.exclamationmark"
            case .unknown: return "exclamationmark.triangle"
            }
        }
    }

    struct Issue: Identifiable, Equatable {
        let id: String
        let kind: Kind
        let technicalLines: [String]

        var title: String { kind.titleKey.t }
        var body: String { kind.bodyKey.t }
        var action: String { kind.actionKey.t }
    }

    struct Presentation: Equatable {
        /// One-line status for cards / banners.
        let headline: String
        /// Short plain-language explanation for store admins.
        let summary: String
        /// Suggested next step.
        let action: String
        /// Grouped issues (friendly) with raw lines nested for expand.
        let issues: [Issue]
        /// Flat technical log for copy / support.
        let technicalLog: [String]
    }

    static func present(rawLines: [String], isCritical: Bool) -> Presentation {
        let cleaned = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var buckets: [Kind: [String]] = [:]
        for line in cleaned {
            let kind = classify(line)
            buckets[kind, default: []].append(line)
        }

        // Prefer actionable order for admins.
        let order: [Kind] = [.auth, .staffSchedule, .permission, .conflict, .dataIntegrity, .network, .unknown]
        var issues: [Issue] = []
        for kind in order {
            guard let lines = buckets[kind], !lines.isEmpty else { continue }
            issues.append(Issue(
                id: kind.rawValue,
                kind: kind,
                technicalLines: Array(lines.prefix(6))
            ))
        }

        if issues.isEmpty {
            let kind: Kind = isCritical ? .unknown : .network
            issues = [Issue(id: kind.rawValue, kind: kind, technicalLines: [])]
        }

        let primary = issues[0]
        let headline = isCritical ? "sync_critical_detail_title".t : "sync_partial_detail_title".t
        let summary: String
        if issues.count == 1 {
            summary = primary.body
        } else {
            summary = String(format: "sync_issue_multi_summary".t, issues.count)
        }

        return Presentation(
            headline: headline,
            summary: summary,
            action: primary.action,
            issues: issues,
            technicalLog: cleaned
        )
    }

    static func classify(_ raw: String) -> Kind {
        let s = raw.lowercased()

        if s.contains("employee_shifts") || s.contains("employee_id_fkey")
            || s.contains("missing employee") || s.contains("shift missing") {
            return .staffSchedule
        }
        if s.contains("42501") || s.contains("permission denied")
            || s.contains("grant select") || s.contains("grant the required") {
            return .permission
        }
        if s.contains("pgrst301") || s.contains("jwt") || s.contains("401")
            || s.contains("auth") && (s.contains("token") || s.contains("login") || s.contains("merchant"))
            || s.contains("sync_auth_required") {
            return .auth
        }
        if s.contains("409") || s.contains("23505") || s.contains("conflict")
            || s.contains("row_version") || s.contains("duplicate") {
            return .conflict
        }
        if s.contains("23503") || s.contains("foreign key") || s.contains("violates") {
            return .dataIntegrity
        }
        if s.contains("offline") || s.contains("timed out") || s.contains("timeout")
            || s.contains("network") || s.contains("not connected") {
            return .network
        }
        return .unknown
    }
}
