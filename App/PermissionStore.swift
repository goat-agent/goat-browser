import Foundation

// PermissionStore — persists per-(origin, kind) permission decisions in
// UserDefaults so repeat visits don't re-prompt. NEVER auto-grants: a missing
// entry means "ask the user". We only store explicit allow/deny decisions.
enum PermissionDecision: String {
    case allow
    case deny
}

@MainActor
struct PermissionStore {
    private static let key = "GoatPermissionDecisions"

    // Normalize origin to a scheme+host key (CEF passes a full origin URL).
    private static func originKey(_ origin: String) -> String {
        if let url = URL(string: origin), let host = url.host {
            return host
        }
        return origin
    }

    private static func compositeKey(origin: String, kind: String) -> String {
        "\(originKey(origin))|\(kind)"
    }

    static func decision(origin: String, kind: String) -> PermissionDecision? {
        let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        guard let raw = dict[compositeKey(origin: origin, kind: kind)] else { return nil }
        return PermissionDecision(rawValue: raw)
    }

    static func store(origin: String, kind: String, decision: PermissionDecision) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        dict[compositeKey(origin: origin, kind: kind)] = decision.rawValue
        UserDefaults.standard.set(dict, forKey: key)
    }
}

// A single pending permission request awaiting the user's decision in the
// overlay panel.
@MainActor
struct PermissionRequest: Identifiable {
    let id: Int          // bridge reqId
    let tabId: Int
    let kind: String     // "microphone", "camera", "location", ...
    let origin: String   // full origin URL from CEF

    // Human host for the prompt, e.g. "example.com".
    var displayHost: String {
        if let url = URL(string: origin), let host = url.host { return host }
        return origin
    }
}
