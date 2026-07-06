import SwiftUI
import AppKit

struct HeaderView: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            NavButton(symbol: "chevron.left",
                      enabled: model.activeTab?.canGoBack ?? false) { model.goBack() }
            NavButton(symbol: "chevron.right",
                      enabled: model.activeTab?.canGoForward ?? false) { model.goForward() }
            NavButton(symbol: model.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                      enabled: model.activeTab != nil) {
                if model.activeTab?.isLoading == true { model.stop() } else { model.reload() }
            }

            QuietURLView(model: model)
                .frame(maxWidth: DS.Metrics.urlMaxWidth)
                .frame(maxWidth: .infinity)

            if !model.downloads.items.isEmpty {
                DownloadsPill(model: model)
            }

            Menu {
                Button("Find…") { model.openFind() }
                Divider()
                Button("Zoom In") { model.zoomIn() }
                Button("Zoom Out") { model.zoomOut() }
                Button("Actual Size") { model.zoomReset() }
                Divider()
                Button("Toggle Sidebar") { model.toggleSidebar() }
                Button("Developer Tools") { model.showDevTools() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: DS.Metrics.controlSize, height: DS.Metrics.controlSize)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, DS.Space.xs)
        .padding(.trailing, DS.Space.md)
    }
}

private struct NavButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: DS.Metrics.controlSize, height: DS.Metrics.controlSize)
                .foregroundStyle(DS.Colors.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(hovering && enabled ? DS.Colors.fillHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { hovering = $0 }
    }
}

private struct QuietURLView: View {
    @Bindable var model: BrowserViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            model.openCommandBarForActiveTab()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Colors.textFaded)
                urlText
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(hovering ? DS.Colors.fillSubtle : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var urlText: some View {
        let parts = URLDisplay.split(model.activeTab?.urlString ?? "")
        if parts.host.isEmpty {
            Text("Search or enter address")
                .font(DS.Fonts.urlQuiet)
                .foregroundStyle(DS.Colors.textFaded)
        } else if hovering {
            (Text(parts.scheme).foregroundStyle(DS.Colors.textFaded)
             + Text(parts.host).foregroundStyle(DS.Colors.textPrimary)
             + Text(parts.path).foregroundStyle(DS.Colors.textFaded))
                .font(DS.Fonts.urlExpanded)
                .lineLimit(1).truncationMode(.tail)
        } else {
            Text(parts.host)
                .font(DS.Fonts.urlQuiet)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(1).truncationMode(.tail)
        }
    }
}

private struct DownloadsPill: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        Button {
            model.toggleDownloadsPopover()
        } label: {
            Image(systemName: model.downloads.hasActive ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .frame(width: DS.Metrics.controlSize, height: DS.Metrics.controlSize)
                .foregroundStyle(model.downloads.hasActive ? DS.Colors.accent : DS.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $model.downloadsPopoverVisible, arrowEdge: .bottom) {
            DownloadsPopover(model: model)
        }
    }
}

enum URLDisplay {
    static func split(_ urlString: String) -> (scheme: String, host: String, path: String) {
        guard let url = URL(string: urlString), let host = url.host,
              url.scheme != "goat" else {
            return ("", "", "")
        }
        let scheme = url.scheme.map { "\($0)://" } ?? ""
        var path = url.path
        if let query = url.query { path += "?\(query)" }
        return (scheme, host, path)
    }
}
