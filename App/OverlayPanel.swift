import SwiftUI
import AppKit

// OverlayPanel — a borderless child NSPanel that hosts SwiftUI floating UI ABOVE
// the windowed-rendering CEF NSView.
//
// WHY THIS EXISTS
// ---------------
// The CEF browser uses windowed rendering: a heavyweight native NSView is added
// as a child of the content container (CefWindowInfo::SetAsChild). A native
// NSView composites ABOVE SwiftUI's layer-backed content, so any SwiftUI
// `.overlay` drawn over the web area renders BEHIND the CEF view and is never
// visible. (Confirmed: Cmd+L flips `commandBarVisible = true` but nothing shows.)
//
// A sibling layer can't win against a native subview, but a *separate window*
// can: a child NSWindow is composited by the window server ABOVE its parent's
// content (including the CEF NSView). So we route all floating UI (command bar,
// hover nav controls, future permission prompts/panels) through this panel.
//
// The panel is attached as a CHILD WINDOW of the content window via
// `addChildWindow(_:ordered: .above)`, so AppKit moves it with the parent and
// keeps it ordered above. We additionally keep its frame in sync with the
// parent's CONTENT area (observing didResize/didMove) so it exactly covers the
// web view region.
//
// HIT TESTING
// -----------
// The panel covers the whole content area, but most of it is transparent and
// must let clicks reach the CEF view underneath. `PassthroughHostingView`
// returns nil from hitTest for points not over actual SwiftUI controls, so the
// CEF page stays fully interactive. When the command bar is shown we want the
// dimmed backdrop to BE interactive (to catch the dismiss tap and to become
// key), so the SwiftUI content there is opaque-to-hit-testing.
@MainActor
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        // Float above normal content; as a child window it tracks the parent.
        level = .floating
        // Don't show in window cycling / Exposé as a separate entity.
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        // We toggle this per-state: pass-through when only hover controls show,
        // interactive when the command bar is up. Default to interactive; the
        // PassthroughHostingView does fine-grained per-point hit testing.
        ignoresMouseEvents = false
    }
}

// Hosting view that lets clicks fall through to the window/view BEHIND the panel
// wherever there is no actual SwiftUI control. This keeps the CEF page fully
// interactive while still allowing the command bar and hover controls to receive
// events. SwiftUI's hosting view returns self for any in-bounds point, so we
// override hitTest to consult the underlying view tree and reject hits on purely
// transparent regions.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    // When true, the whole surface is interactive (used for the command bar's
    // dimmed backdrop, which must catch the dismiss tap and hold key focus).
    var capturesAllEvents = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if capturesAllEvents {
            return super.hitTest(point)
        }
        let hit = super.hitTest(point)
        // If the deepest hit is the hosting view itself (i.e. empty/transparent
        // SwiftUI space), let the event pass through to the CEF view behind us.
        if hit === self {
            return nil
        }
        return hit
    }
}

// OverlayWindowController — owns the panel, hosts SwiftUI content, attaches the
// panel to a parent window, and keeps the panel's frame synced to the parent's
// content area. The container view creates and drives this.
@MainActor
final class OverlayWindowController: NSObject {
    private let panel: OverlayPanel
    private let hostingView: PassthroughHostingView<OverlayRoot>
    private weak var parentWindow: NSWindow?
    private let model: BrowserViewModel

    // Whether the command bar is currently presented (drives key/focus + hit).
    private var commandBarShown = false

    init(model: BrowserViewModel) {
        self.model = model
        let root = OverlayRoot(model: model)
        let host = PassthroughHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        self.hostingView = host
        self.panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
        super.init()
        panel.contentView = host
        host.frame = panel.contentView?.bounds ?? .zero
    }

    // Attach the panel to `window` as a child and start tracking its frame.
    func attach(to window: NSWindow) {
        guard parentWindow !== window else {
            syncFrame()
            return
        }
        parentWindow = window
        window.addChildWindow(panel, ordered: .above)
        syncFrame()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(parentFrameChanged),
                       name: NSWindow.didResizeNotification, object: window)
        nc.addObserver(self, selector: #selector(parentFrameChanged),
                       name: NSWindow.didMoveNotification, object: window)

        // React to @Observable model changes directly (updateNSView is not
        // guaranteed to fire when only commandBarVisible flips).
        startObserving()
    }

    @objc private func parentFrameChanged() {
        syncFrame()
    }

    // Size/position the panel to exactly cover the parent window's content area.
    private func syncFrame() {
        guard let parent = parentWindow else { return }
        let contentRect = parent.contentRect(forFrameRect: parent.frame)
        panel.setFrame(contentRect, display: true)
        hostingView.frame = panel.contentView?.bounds ?? .zero
    }

    // Update presentation when model state changes. Driven both by SwiftUI's
    // updateNSView pass AND by our own @Observable tracking (see startObserving),
    // because the representable's inputs don't change when commandBarVisible
    // flips, so updateNSView is not guaranteed to fire for that state change.
    func update() {
        guard parentWindow != nil else { return }
        syncFrame()

        // The panel must become key/interactive whenever ANY of its modal-ish
        // surfaces is up: the command bar, the find bar, or a permission prompt.
        let wantKey = model.commandBarVisible || model.find.visible
            || model.pendingPermission != nil
        // The command bar AND the permission prompt want a full-surface
        // interactive layer: the command bar for its dimmed dismiss backdrop,
        // and the permission prompt because it is modal (a decision is required
        // before the page proceeds) and its buttons must reliably receive clicks
        // even though the panel is a non-activating child window. The find bar is
        // a non-modal floating control, so it keeps per-point passthrough.
        let wantCapture = model.commandBarVisible || model.pendingPermission != nil
        let wantBar = model.commandBarVisible
        if wantKey != commandBarShown {
            commandBarShown = wantKey
            hostingView.capturesAllEvents = wantCapture
            if wantKey {
                // Bring the panel up and make it key so an NSTextField inside
                // the hosting view can become first responder and accept typing.
                if let parent = parentWindow {
                    parent.removeChildWindow(panel)
                    parent.addChildWindow(panel, ordered: .above)
                }
                panel.orderFront(nil)
                panel.makeKey()
                focusCommandField()
            } else {
                // Relinquish key back to the parent so the page regains focus.
                parentWindow?.makeKey()
            }
        } else if wantKey {
            // Keep capture state in sync if surfaces toggle while the panel
            // stays key (e.g. permission prompt resolves while find stays open).
            hostingView.capturesAllEvents = wantCapture
        }
        // Ensure the panel is visible/ordered above whenever the parent is.
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    // Walk the hosting view tree to find the command bar's NSTextField and make
    // it first responder. Retried a couple of times because SwiftUI may not have
    // instantiated the field yet on the first run-loop turn after presenting.
    private func focusCommandField() {
        func findTextField(_ view: NSView) -> NSTextField? {
            if let tf = view as? NSTextField, tf.isEditable { return tf }
            for sub in view.subviews {
                if let found = findTextField(sub) { return found }
            }
            return nil
        }
        var attempts = 0
        func attempt() {
            guard model.commandBarVisible else { return }
            if let field = findTextField(hostingView) {
                panel.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
                return
            }
            attempts += 1
            if attempts < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: attempt)
            }
        }
        attempt()
    }

    // Self-driven observation so the panel reacts to @Observable model changes
    // (commandBarVisible) even when SwiftUI doesn't re-run updateNSView. Each
    // callback re-registers tracking (one-shot semantics of withObservationTracking).
    private func startObserving() {
        withObservationTracking {
            _ = model.commandBarVisible
            _ = model.find.visible
            _ = model.pendingPermission?.id
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.update()
                    self.startObserving()
                }
            }
        }
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        if let parent = parentWindow {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        parentWindow = nil
    }
}

// OverlayRoot — the SwiftUI content rendered inside the panel. It composes the
// always-available hover nav controls and the conditional command bar, exactly
// the views that used to live in `.overlay`/the content ZStack. Empty regions
// are transparent so PassthroughHostingView lets clicks reach the CEF page.
struct OverlayRoot: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Command bar fills the area when visible (dimmed backdrop + field).
            if model.commandBarVisible {
                CommandBarOverlay(model: model)
            }

            // Find bar: small floating control at the top-right of the content.
            if model.find.visible {
                FindBarOverlay(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 16)
            }

            // Permission prompt: small floating card at the top-center.
            if let request = model.pendingPermission {
                PermissionPromptOverlay(model: model, request: request)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
