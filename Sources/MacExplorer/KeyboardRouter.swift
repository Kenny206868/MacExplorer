import AppKit
import ExplorerCore

extension Notification.Name { static let explorerNewWindow = Notification.Name("MacExplorer.newWindow") }
@MainActor enum KeyboardRouter {
    static func handle(_ event: NSEvent, terminalLauncher: TerminalLauncher? = nil) -> NSEvent? {
        guard let workspace = WorkspaceCommandScope.target(AppRouter.shared.active), event.window === workspace.window else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let control = flags.contains(.control), command = flags.contains(.command), shift = flags.contains(.shift), option = flags.contains(.option)
        // VoiceOver owns Control-Option. Never repurpose its chords.
        guard !(control && option) else { return event }
        let text = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Composition owns Escape, Return and navigation until committed. The
        // app must not switch panes or steal path focus from an input method.
        if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
        let editing = event.window?.firstResponder is NSTextView || event.window?.firstResponder is NSTextField
        let commanderKeys = CommanderPreferences.shared.classicFunctionKeys && workspace.fileSurfaceFocused
            && !editing && !workspace.current.location.isArchive
        let locationShortcut = !option && ((command != control && !shift && text == "l")
            || (command && !control && shift && text == "g")
            || (!command && !control && !shift && event.keyCode == 118 && !commanderKeys))
        if locationShortcut {
            if !event.isARepeat { workspace.editLocation() }
            return nil
        }
        if command && option && [36, 76].contains(event.keyCode) {
            if !event.isARepeat { (terminalLauncher ?? .shared).open(from: workspace, scope: shift ? .both : .active) }
            return nil
        }
        if control && !command && event.keyCode == 48 { workspace.cycleTab(shift ? -1 : 1); return nil }
        if control && !command && (event.keyCode == 116 || event.keyCode == 121) { workspace.cycleTab(event.keyCode == 116 ? -1 : 1); return nil }
        if event.keyCode == 97 && !command && !control && !option && (!commanderKeys || shift) { workspace.cycleFocus(backwards: shift); return nil }
        if (command || control) && shift && !option && text == "p" {
            workspace.sheet = .commandPalette; return nil
        }
        if editing {
            if event.keyCode == 53 && (workspace.addressFocused || workspace.searchFocused) {
                if workspace.searchFocused && !workspace.current.query.isEmpty { workspace.current.query = "" }
                else { workspace.focusFileSurface() }; return nil
            }
            if control && !command {
                let editor = event.window?.firstResponder
                let selectors = ["c": "copy:", "x": "cut:", "v": "paste:", "a": "selectAll:"]
                if let action = selectors[text] { _ = NSApp.sendAction(NSSelectorFromString(action), to: editor, from: nil); return nil }
                if text == "z" || text == "y" { if text == "y" || shift { editor?.undoManager?.redo() } else { editor?.undoManager?.undo() }; return nil }
            }
            return event
        }
        if commanderKeys && !command && !control && !option && !shift,
           let action = CommanderAction.functionKey(event.keyCode) {
            if !event.isARepeat { action.perform(in: workspace) }
            return nil
        }
        if command && !control && !option && ["+", "=", "-"].contains(text) { workspace.zoomFileView(text == "-" ? -1 : 1); return nil }
        if (command || control) && shift && text == "d" && !option { workspace.toggleDualPane(); return nil }
        if command && option && (text == "c" || text == "m") { workspace.paneController?.requestTransfer(from: workspace, move: text == "m"); return nil }
        if (command || control), let number = Int(text), (1...9).contains(number), !option { workspace.selectTab(number: number); return nil }
        if option && !command {
            switch event.keyCode {
            case 123: workspace.current.back(); return nil
            case 124: workspace.current.forward(); return nil
            case 126: workspace.current.up(); return nil
            case 36, 76: if !workspace.selected.isEmpty { workspace.sheet = .properties }; return nil
            default: if text == "d" { workspace.editLocation(); return nil }; return event
            }
        }
        if workspace.current.location.isArchive {
            if event.keyCode == 120 && !command && !control && !option { NotificationCenter.default.post(name: .archiveRenameRequested, object: workspace.current.id); return nil }
            if event.keyCode == 96 && !command && !control && !option { workspace.current.refresh(); return nil }
            if event.keyCode == 51 && !command && !control && !option { workspace.current.up(); return nil }
            if control && !command {
                switch text {
                case "f": workspace.searchFocused = true; return nil
                case "l": workspace.editLocation(); return nil
                case "t": if shift { workspace.reopenClosedTab() } else { workspace.newTab() }; return nil
                case "w": workspace.closeTab(workspace.activeID); return nil
                case "z": workspace.operations.undo(redo: shift); return nil
                case "y": workspace.operations.undo(redo: true); return nil
                default: break
                }
            }
            return event // Native archive Table owns its virtual member input.
        }
        if control && !command {
            if [123, 124, 125, 126, 115, 119].contains(event.keyCode) {
                guard workspace.fileSurfaceFocused else { return event }; workspace.keyboardMove(event.keyCode, shift: shift, control: true); return nil
            }
            if event.keyCode == 49 { guard workspace.fileSurfaceFocused else { return event }; workspace.toggleFocusedSelection(); return nil }
            if event.keyCode == 118 { workspace.closeTab(workspace.activeID); return nil }
            switch text {
            case "c": if shift { NativeIntegration.copyPaths(workspace.selectedURLs) } else { workspace.copy() }
            case "x": workspace.copy(cut: true)
            case "v": workspace.paste()
            case "a": workspace.selectAll()
            case "z": workspace.operations.undo(redo: shift)
            case "y": workspace.operations.undo(redo: true)
            case "t": if shift { workspace.reopenClosedTab() } else { workspace.newTab() }
            case "w": workspace.closeTab(workspace.activeID)
            case "l": workspace.editLocation()
            case "f": if shift { workspace.current.allLocations = true }; workspace.searchFocused = true
            case "n":
                if shift { if workspace.destination != nil { workspace.sheet = .newFolder } }
                else { NotificationCenter.default.post(name: .explorerNewWindow, object: workspace.windowRoot.id) }
            case "+", "=": workspace.zoomFileView(1)
            case "-": workspace.zoomFileView(-1)
            default: return event
            }; return nil
        }
        guard !command, !option else { return event }
        switch event.keyCode {
        case 122: workspace.sheet = .keyboardHelp; return nil
        case 120: workspace.requestRename(); return nil
        case 99: workspace.searchFocused = true; return nil
        case 118: workspace.editLocation(); return nil
        case 96: workspace.current.refresh(); return nil
        case 109 where shift: if !workspace.selected.isEmpty { workspace.sheet = .fileActions }; return nil
        default: break
        }
        guard workspace.fileSurfaceFocused else { return event }
        switch event.keyCode {
        case 48:
            if let controller = workspace.paneController { controller.focus(controller.geometry.focused.other, files: true); return nil }; return event
        case 51: workspace.current.back(); return nil
        case 117: workspace.delete(permanent: shift); return nil
        case 49: workspace.quickLook(); return nil
        case 36, 76: workspace.openSelection(); return nil
        case 53:
            workspace.current.previewURL = nil; workspace.current.selection = []; workspace.current.rangeBaseline = nil
            workspace.current.typeAhead.reset(); workspace.touchSelecting = false; return nil
        case 115, 119, 123, 124, 125, 126: workspace.keyboardMove(event.keyCode, shift: shift, control: false); return nil
        case 116, 121:
            let grid = ![.details, .list, .content, .gallery].contains(workspace.current.options.view)
            let input = InputPreferences.shared
            let rowHeight = grid ? Double(input.gridCellHeight(workspace.current.options.view)) + 10 : workspace.current.options.view == .content ? 70 : Double(input.rowHeight(compact: workspace.preferences.value.compact))
            let rows = max(1, Int(workspace.fileViewportHeight / max(1, rowHeight)) - 1)
            workspace.moveSelection(rows * (grid ? max(1, workspace.current.gridColumns) : 1) * (event.keyCode == 116 ? -1 : 1), extend: shift); return nil
        default:
            if let text = event.characters, !text.isEmpty,
               !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value) }),
               workspace.typeToSelect(text, time: event.timestamp) { return nil }
            return event
        }
    }
}
