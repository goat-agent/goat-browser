import Foundation
import AppKit
import Observation

// DownloadItem — observable state for a single download. Keyed by the CEF
// download id. Files always land in ~/Downloads (fixed location, no settings).
@MainActor
@Observable
final class DownloadItem: Identifiable {
    let id: Int
    var fileName: String
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = -1
    var isComplete: Bool = false
    var fullPath: String = ""

    init(id: Int, fileName: String) {
        self.id = id
        self.fileName = fileName
    }

    // 0...1 fraction, or nil when total is unknown.
    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1.0, Double(receivedBytes) / Double(totalBytes))
    }

    var progressText: String {
        let r = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        if totalBytes > 0 {
            let t = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(r) of \(t)"
        }
        return r
    }
}

// DownloadsModel — tracks active and recent downloads. Owned by the
// BrowserViewModel and updated from the bridge's download delegate callback.
@MainActor
@Observable
final class DownloadsModel {
    // Most-recent-first.
    private(set) var items: [DownloadItem] = []

    // True when there is at least one in-progress download (drives a subtle
    // indicator on the sidebar downloads button).
    var hasActive: Bool { items.contains { !$0.isComplete } }

    func update(id: Int, fileName: String, received: Int64, total: Int64,
                complete: Bool, path: String) {
        if let item = items.first(where: { $0.id == id }) {
            if !fileName.isEmpty { item.fileName = fileName }
            item.receivedBytes = received
            item.totalBytes = total
            item.isComplete = complete
            if !path.isEmpty { item.fullPath = path }
        } else {
            let item = DownloadItem(id: id, fileName: fileName)
            item.receivedBytes = received
            item.totalBytes = total
            item.isComplete = complete
            item.fullPath = path
            items.insert(item, at: 0)
        }
    }

    func showInFinder(_ item: DownloadItem) {
        let path = item.fullPath.isEmpty
            ? (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first.map {
                ($0 as NSString).appendingPathComponent(item.fileName)
              } ?? "")
            : item.fullPath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
