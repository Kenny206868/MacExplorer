import SwiftUI
import AppKit

/// Native field-editor and IME integration only. The address surface and
/// completion UI are SwiftUI. Suggestion refreshes never reset text selection.
struct NativePathField: NSViewRepresentable {
    @ObservedObject var model: PathEditorModel
    let label: String
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> PathTextField {
        let field = PathTextField()
        field.delegate = context.coordinator; field.isBezeled = false; field.drawsBackground = false
        field.isEditable = true; field.isSelectable = true; field.focusRingType = .none
        field.font = .systemFont(ofSize: 12); field.textColor = .labelColor
        field.cell?.usesSingleLineMode = true; field.cell?.wraps = false; field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(label); field.identifier = NSUserInterfaceItemIdentifier("explorer.nativePathEditor")
        return field
    }
    func updateNSView(_ field: PathTextField, context: Context) {
        context.coordinator.model = model; field.setAccessibilityLabel(label)
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        if field.stringValue != model.text {
            field.stringValue = model.text
            if let editor = field.currentEditor() as? NSTextView { editor.string = model.text }
        }
        field.wantsFocus = model.editing
        if field.selectionVersion != model.focusVersion {
            field.selectionVersion = model.focusVersion; field.selectAllOnFocus = model.selectAllOnFocus; field.scheduleFocus()
        }
    }
    static func dismantleNSView(_ field: PathTextField, coordinator: Coordinator) { field.wantsFocus = false; field.delegate = nil }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: PathEditorModel
        init(model: PathEditorModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.change(field.stringValue, composing: (field.currentEditor() as? NSTextView)?.hasMarkedText() == true)
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            let version = model.focusVersion
            DispatchQueue.main.async { [weak self] in
                guard let self, version == self.model.focusVersion else { return }
                if self.model.editing { self.model.cancel() }
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            guard !(flags.contains(.control) && flags.contains(.option)) else { return false }
            switch NSStringFromSelector(selector) {
            case "insertNewline:", "insertNewlineIgnoringFieldEditor:": model.submit(newTab: flags.contains(.command)); return true
            case "cancelOperation:": model.cancel(); return true
            case "insertTab:":
                guard NSMaxRange(textView.selectedRange()) == (model.text as NSString).length else { return false }
                model.acceptCompletion(); return true
            case "moveDown:": model.moveHighlight(1); return !model.suggestions.isEmpty
            case "moveUp:": model.moveHighlight(-1); return !model.suggestions.isEmpty
            default: return false
            }
        }
    }
}
@MainActor final class PathTextField: NSTextField {
    var wantsFocus = false
    var selectionVersion = -1
    var selectAllOnFocus = true
    private var scheduled = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleFocus() }
    func scheduleFocus() {
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.scheduled = false
            guard self.wantsFocus, let window = self.window, window.attachedSheet == nil else { return }
            if self.currentEditor() == nil { window.makeFirstResponder(self) }
            guard let editor = self.currentEditor() as? NSTextView, !editor.hasMarkedText() else { return }
            let length = (self.stringValue as NSString).length
            editor.setSelectedRange(self.selectAllOnFocus ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0))
            editor.scrollRangeToVisible(editor.selectedRange())
        }
    }
}
