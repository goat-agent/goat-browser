import SwiftUI
import AppKit

struct CommandBarOverlay: View {
    @Bindable var model: BrowserViewModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { model.dismissCommandBar() }

            VStack {
                Spacer().frame(height: 96)
                VStack(spacing: 0) {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(DS.Colors.textSecondary)
                        CommandBarField(text: $model.commandBarText,
                                        onSubmit: { model.submitCommandBar() },
                                        onCancel: { model.dismissCommandBar() },
                                        onUp: { model.moveSuggestionSelection(-1) },
                                        onDown: { model.moveSuggestionSelection(1) })
                            .focused($focused)
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.md)

                    if !model.commandSuggestions.isEmpty {
                        Divider().opacity(0.5)
                        SuggestionList(model: model)
                    }
                }
                .frame(maxWidth: 640)
                .raisedGlass(cornerRadius: DS.Radius.panel + 4)
                Spacer()
            }
            .padding(.horizontal, DS.Space.xl)
        }
        .onAppear { focused = true }
        .onChange(of: model.commandBarText) { _, _ in model.refreshSuggestions() }
    }
}

private struct SuggestionList: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(model.commandSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionRow(suggestion: suggestion,
                              selected: index == model.selectedSuggestionIndex)
                    .contentShape(Rectangle())
                    .onTapGesture { model.activate(suggestion) }
                    .onHover { if $0 { model.selectedSuggestionIndex = index } }
            }
        }
        .padding(DS.Space.xs)
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let selected: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: suggestion.icon)
                .font(.system(size: 13))
                .foregroundStyle(selected ? DS.Colors.accent : DS.Colors.textSecondary)
                .frame(width: 18)
            Text(suggestion.title)
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.md)
            Text(suggestion.subtitle)
                .font(DS.Fonts.caption)
                .foregroundStyle(DS.Colors.textFaded)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(selected ? DS.Colors.fillActive : .clear)
        )
    }
}

struct CommandBarField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = "Search or enter address"
        field.font = .systemFont(ofSize: 16)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
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
        var parent: CommandBarField
        init(_ parent: CommandBarField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if let field = control as? NSTextField { parent.text = field.stringValue }
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onDown()
                return true
            default:
                return false
            }
        }
    }
}
