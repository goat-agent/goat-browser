import Foundation
import Observation

// FindModel — state for the find-in-page bar (Cmd+F). Owned by BrowserViewModel.
// The bar itself lives in the OVERLAY PANEL so it composites above the CEF view.
@MainActor
@Observable
final class FindModel {
    var visible = false
    var query = ""
    var currentMatch = 0   // 1-based active match ordinal
    var totalMatches = 0

    var matchLabel: String {
        if query.isEmpty { return "" }
        return "\(currentMatch)/\(totalMatches)"
    }

    func reset() {
        currentMatch = 0
        totalMatches = 0
    }
}
