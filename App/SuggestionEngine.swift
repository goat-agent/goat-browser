import Foundation

struct Suggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case openTab(tabId: Int)
        case history
        case bookmark
        case search
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let target: String

    var icon: String {
        switch kind {
        case .openTab: return "square.on.square"
        case .history: return "clock"
        case .bookmark: return "star"
        case .search: return "magnifyingglass"
        }
    }
}

enum SuggestionEngine {
    @MainActor
    static func suggestions(query: String, profileId: UUID, openTabs: [Tab]) -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [Suggestion] = []
        let lowered = trimmed.lowercased()

        for tab in openTabs where tab.groupId != nil || tab.groupId == nil {
            if tab.displayLabel.lowercased().contains(lowered)
                || tab.urlString.lowercased().contains(lowered) {
                results.append(Suggestion(
                    id: "tab-\(tab.id)",
                    kind: .openTab(tabId: tab.id),
                    title: tab.displayLabel,
                    subtitle: "Switch to Tab",
                    target: tab.urlString))
            }
            if results.count >= 3 { break }
        }

        for entry in BookmarkStore.search(profileId: profileId, query: trimmed, limit: 3) {
            guard let url = entry.url else { continue }
            results.append(Suggestion(
                id: "bm-\(entry.id ?? 0)",
                kind: .bookmark,
                title: entry.title,
                subtitle: url,
                target: url))
        }

        let seen = Set(results.map { $0.target })
        for entry in HistoryStore.search(profileId: profileId, query: trimmed, limit: 6) where !seen.contains(entry.url) {
            results.append(Suggestion(
                id: "hist-\(entry.id ?? 0)",
                kind: .history,
                title: entry.displayTitle,
                subtitle: entry.url,
                target: entry.url))
        }

        if URLInputResolver.treatAsURL(trimmed) {
            results.insert(Suggestion(
                id: "url-\(trimmed)",
                kind: .search,
                title: trimmed,
                subtitle: "Open site",
                target: trimmed), at: 0)
        } else {
            results.append(Suggestion(
                id: "search-\(trimmed)",
                kind: .search,
                title: trimmed,
                subtitle: "\(SearchEngine.current.title) search",
                target: trimmed))
        }

        return Array(results.prefix(8))
    }
}
