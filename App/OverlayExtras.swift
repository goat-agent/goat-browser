import SwiftUI
import AppKit

// FindBarOverlay — the Cmd+F find-in-page bar. Rendered in the OVERLAY PANEL
// (top-right of the content) so it composites above the windowed CEF NSView.
// Enter = next, Shift+Enter = prev, Esc = close + StopFinding.
struct FindBarOverlay: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            FindBarField(text: model.find.query,
                         onChange: { model.updateFindQuery($0) },
                         onNext: { model.findNext() },
                         onPrev: { model.findPrev() },
                         onCancel: { model.closeFind() })
                .frame(width: 200)

            Text(model.find.matchLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 38, alignment: .trailing)

            Divider().frame(height: 16)

            iconButton("chevron.up") { model.findPrev() }
            iconButton("chevron.down") { model.findNext() }
            iconButton("xmark") { model.closeFind() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }
}

// An NSTextField wrapper for the find bar so we can intercept Enter / Shift+Enter
// / Esc reliably, and report changes live as the user types.
struct FindBarField: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void
    let onNext: () -> Void
    let onPrev: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = "Find in page"
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindBarField
        init(_ parent: FindBarField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.onChange(field.stringValue)
            }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Shift+Enter = previous, Enter = next.
                let shift = NSEvent.modifierFlags.contains(.shift)
                if shift { parent.onPrev() } else { parent.onNext() }
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onPrev()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// PermissionPromptOverlay — per-origin Allow/Deny prompt rendered in the overlay
// panel. e.g. "example.com wants to use your microphone".
struct PermissionPromptOverlay: View {
    @Bindable var model: BrowserViewModel
    let request: PermissionRequest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayHost)
                    .font(.system(size: 13, weight: .semibold))
                Text("wants to use your \(request.kind)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Deny") { model.resolvePermission(request, granted: false) }
                .keyboardShortcut(.cancelAction)
            Button("Allow") { model.resolvePermission(request, granted: true) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 14)
    }

    private var icon: String {
        switch request.kind {
        case let k where k.contains("microphone"): return "mic"
        case let k where k.contains("camera"): return "camera"
        case let k where k.contains("location"): return "location"
        case let k where k.contains("notification"): return "bell"
        case let k where k.contains("clipboard"): return "doc.on.clipboard"
        default: return "hand.raised"
        }
    }
}
