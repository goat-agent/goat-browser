import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: BrowserViewModel
    private let initialURL = "goat://newtab"

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .frame(width: DS.Metrics.sidebarWidth)
                    .transition(.move(edge: .leading))
            }
            ContentColumn(model: model, initialURL: initialURL)
        }
        .animation(DS.Motion.slide, value: model.sidebarVisible)
        .canvasBackground()
        .background(WindowConfigurator())
    }
}

struct ContentColumn: View {
    @Bindable var model: BrowserViewModel
    let initialURL: String

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
                .frame(height: DS.Metrics.headerHeight)
            LoadingBar(model: model)
            GoatBrowserContainer(model: model, initialURL: initialURL)
                .background(DS.Colors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .webCardShadow()
                .padding(.leading, model.sidebarVisible ? 0 : DS.Metrics.cardMargin)
                .padding(.trailing, DS.Metrics.cardMargin)
                .padding(.bottom, DS.Metrics.cardMargin)
        }
    }
}

struct LoadingBar: View {
    @Bindable var model: BrowserViewModel

    private var isLoading: Bool { model.activeTab?.isLoading ?? false }
    private var progress: Double { model.activeTab?.loadProgress ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(DS.Colors.accent)
                .frame(width: geometry.size.width * progress)
                .animation(DS.Motion.snap, value: progress)
        }
        .frame(height: isLoading && progress < 1 ? 2 : 0)
        .opacity(isLoading && progress < 1 ? 1 : 0)
        .allowsHitTesting(false)
    }
}

struct GoatBrowserContainer: NSViewRepresentable {
    let model: BrowserViewModel
    let initialURL: String

    func makeNSView(context: Context) -> GoatBrowserContainerView {
        let view = GoatBrowserContainerView()
        let overlay = OverlayWindowController(model: model)
        view.overlayController = overlay
        view.onLayout = { container in
            MainActor.assumeIsolated {
                model.attachEngine(container: container)
                model.openInitialTabIfNeeded(url: initialURL)
                model.engine?.resizeActiveToContainer()
                if let window = container.window {
                    overlay.attach(to: window)
                    overlay.update()
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: GoatBrowserContainerView, context: Context) {
        MainActor.assumeIsolated {
            if let window = nsView.window {
                nsView.overlayController?.attach(to: window)
            }
            nsView.overlayController?.update()
        }
    }
}

final class GoatBrowserContainerView: NSView {
    var onLayout: ((GoatBrowserContainerView) -> Void)?
    var overlayController: OverlayWindowController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        autoresizesSubviews = true
        layer?.cornerRadius = DS.Radius.card
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?(self)
    }
}
