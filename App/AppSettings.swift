import Foundation
import Observation

enum SearchEngine: String, CaseIterable, Sendable, Identifiable {
    case google, bing, duckduckgo, brave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google"
        case .bing: return "Bing"
        case .duckduckgo: return "DuckDuckGo"
        case .brave: return "Brave"
        }
    }

    private var host: String {
        switch self {
        case .google: return "www.google.com"
        case .bing: return "www.bing.com"
        case .duckduckgo: return "duckduckgo.com"
        case .brave: return "search.brave.com"
        }
    }

    func url(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }

    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: AppSettings.Keys.searchEngine) ?? "")
            ?? .google
    }
}

enum AppTheme: String, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Keys {
        static let searchEngine = "GoatSearchEngine"
        static let homePage = "GoatHomePage"
        static let theme = "GoatTheme"
        static let restoreSession = "GoatRestoreSession"
        static let alwaysShowFullURL = "GoatAlwaysShowFullURL"
        static let downloadsPath = "GoatDownloadsPath"
    }

    private let defaults = UserDefaults.standard

    var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: defaults.string(forKey: Keys.searchEngine) ?? "") ?? .google }
        set { defaults.set(newValue.rawValue, forKey: Keys.searchEngine) }
    }

    var homePage: String {
        get { defaults.string(forKey: Keys.homePage) ?? "goat://newtab" }
        set { defaults.set(newValue, forKey: Keys.homePage) }
    }

    var theme: AppTheme {
        get { AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Keys.theme) }
    }

    var restoreSession: Bool {
        get { defaults.object(forKey: Keys.restoreSession) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.restoreSession) }
    }

    var alwaysShowFullURL: Bool {
        get { defaults.bool(forKey: Keys.alwaysShowFullURL) }
        set { defaults.set(newValue, forKey: Keys.alwaysShowFullURL) }
    }
}
