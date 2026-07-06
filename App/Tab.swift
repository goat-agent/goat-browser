import Foundation
import Observation

@MainActor
@Observable
final class Tab: Identifiable {
    let id: Int
    var title: String
    var urlString: String
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var faviconPNG: Data?
    var groupId: UUID?
    var loadProgress: Double = 0
    var hasError: Bool = false
    var errorCode: Int = 0
    var isRestored: Bool = false

    init(id: Int, urlString: String, title: String = "New Tab") {
        self.id = id
        self.urlString = urlString
        self.title = title
    }

    var displayLabel: String {
        if !title.isEmpty && title != "about:blank" {
            return title
        }
        if let host = URL(string: urlString)?.host {
            return host
        }
        return urlString.isEmpty ? "New Tab" : urlString
    }
}
