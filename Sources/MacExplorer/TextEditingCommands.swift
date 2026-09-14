import AppKit

/// Text editing and filesystem editing have independent command/undo domains.
@MainActor enum TextEditingCommands {
    static var editor: NSTextView? { NSApp.keyWindow?.firstResponder as? NSTextView }
    static var isEditing: Bool { editor != nil }
    @discardableResult static func send(_ action: String) -> Bool {
        guard let editor else { return false }
        // Even unsupported/read-only text commands belong to the editor. Never
        // fall through into a filesystem mutation because sendAction is false.
        _ = NSApp.sendAction(NSSelectorFromString(action), to: editor, from: nil)
        return true
    }
    static func undo(redo: Bool = false) -> Bool {
        guard let editor else { return false }
        if redo { editor.undoManager?.redo() } else { editor.undoManager?.undo() }
        return true
    }
}
