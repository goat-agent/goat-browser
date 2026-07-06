import SwiftUI
import AppKit

struct DownloadsPopover: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Downloads")
                .font(DS.Fonts.popoverHeader)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
            Divider()
            if model.downloads.items.isEmpty {
                Text("No downloads")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(DS.Space.lg)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.downloads.items) { item in
                            DownloadRow(item: item) { model.downloads.showInFinder(item) }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 320)
    }
}

private struct DownloadRow: View {
    @Bindable var item: DownloadItem
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: item.isComplete ? "doc.fill" : "arrow.down.doc")
                .foregroundStyle(item.isComplete ? DS.Colors.accent : DS.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName.isEmpty ? "Downloading…" : item.fileName)
                    .font(DS.Fonts.caption)
                    .lineLimit(1).truncationMode(.middle)
                if item.isComplete {
                    Text(item.progressText)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.textSecondary)
                } else if let f = item.fraction {
                    ProgressView(value: f).controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Spacer(minLength: 4)
            Button(action: onShow) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(item.fullPath.isEmpty && !item.isComplete)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
    }
}
