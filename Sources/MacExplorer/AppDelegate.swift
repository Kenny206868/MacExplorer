import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class AppRouter {
    static let shared = AppRouter()
    weak var active: ExplorerWorkspace?
    var pending: [URL] = []
    func receive(_ urls: [URL]) { if let active { active.openURLs(urls) } else { pending += urls } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        AppRouter.shared.pending += arguments.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        // Local, app-window-only event routing; never a global event tap.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in MainActor.assumeIsolated { KeyboardRouter.handle(event) } }
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { AppRouter.shared.receive(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success) }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL { AppRouter.shared.receive([url]) }
            else if url.scheme == "macexplorer", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                AppRouter.shared.receive([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if OperationCenter.shared.runningCount > 0 {
            AppRouter.shared.active?.fail("File operations are still running", "Finish or cancel active operations before quitting. Completed files will not be rolled back automatically.")
            return .terminateCancel
        }
        WorkspaceSessionCoordinator.shared.prepareToQuit()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func openInMacExplorer(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        if urls.isEmpty { error.pointee = "Select one or more files or folders." }
        else { AppRouter.shared.receive(urls.map { $0 as URL }); NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor enum KeyboardRouter {
    static func handle(_ event: NSEvent) -> NSEvent? {
        guard let workspace = AppRouter.shared.active, event.window == workspace.window,
              event.window?.attachedSheet == nil, workspace.sheet == nil, workspace.conflict == nil,
              workspace.message == nil, workspace.pendingDeletion.isEmpty else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let control = flags.contains(.control), command = flags.contains(.command), shift = flags.contains(.shift)
        if control && event.keyCode == 48 { workspace.cycleTab(shift ? -1 : 1); return nil }
        if (control || command), let text = event.charactersIgnoringModifiers, let number = Int(text), (1...9).contains(number) {
            workspace.selectTab(number: number); return nil
        }
        if event.window?.firstResponder is NSTextView || event.window?.firstResponder is NSTextField { return event }
        if flags.contains(.option) {
            switch event.keyCode {
            case 123: workspace.current.back(); return nil
            case 124: workspace.current.forward(); return nil
            case 126: workspace.current.up(); return nil
            case 36, 76: if !workspace.selected.isEmpty { workspace.sheet = .properties }; return nil
            default:
                if event.charactersIgnoringModifiers?.lowercased() == "d" { workspace.addressFocused = true; return nil }
                return event
            }
        }
        let nativeList = [.details, .list, .content].contains(workspace.current.options.view)
        if control && !command {
            if [123, 124, 125, 126, 115, 119].contains(event.keyCode) {
                workspace.keyboardMove(event.keyCode, shift: shift, control: true); return nil
            }
            if event.keyCode == 49, let focus = workspace.current.focusedURL {
                workspace.select(focus, extend: true, range: false); return nil
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": workspace.copy()
            case "x": workspace.copy(cut: true)
            case "v": workspace.paste()
            case "a": workspace.selectAll()
            case "z": workspace.operations.undo(redo: shift)
            case "y": workspace.operations.undo(redo: true)
            case "t": if shift { workspace.reopenClosedTab() } else { workspace.newTab() }
            case "w": workspace.closeTab(workspace.activeID)
            case "l": workspace.addressFocused = true
            case "f": workspace.searchFocused = true
            case "n" where shift: if workspace.destination != nil { workspace.sheet = .newFolder }
            default: return event
            }
            return nil
        }
        guard !command, !control else { return event }
        switch event.keyCode {
        case 120: if !workspace.selected.isEmpty { workspace.sheet = .rename }; return nil
        case 99: workspace.searchFocused = true; return nil
        case 96: workspace.current.refresh(); return nil
        case 51: workspace.current.back(); return nil
        case 117: workspace.delete(permanent: shift); return nil
        case 49: workspace.quickLook(); return nil
        case 36, 76: workspace.openSelection(); return nil
        case 53: workspace.current.previewURL = nil; workspace.current.selection = []; workspace.current.rangeBaseline = nil; workspace.current.typeAhead.reset(); return nil
        case 115 where !nativeList: workspace.selectBoundary(last: false, extend: shift); return nil
        case 119 where !nativeList: workspace.selectBoundary(last: true, extend: shift); return nil
        case 123 where !nativeList: workspace.moveSelection(-1, extend: shift); return nil
        case 124 where !nativeList: workspace.moveSelection(1, extend: shift); return nil
        case 125 where !nativeList: workspace.moveSelection(workspace.current.gridColumns, extend: shift); return nil
        case 126 where !nativeList: workspace.moveSelection(-workspace.current.gridColumns, extend: shift); return nil
        default:
            if let text = event.characters, !text.isEmpty,
               !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value) }),
               workspace.typeToSelect(text, time: event.timestamp) { return nil }
            return event
        }
    }
}
