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
        // Local, app-window-only event routing implements Explorer's F2/F5/Delete conventions.
        // It never installs a global event tap or records keyboard input.
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
        guard let workspace = AppRouter.shared.active, event.window == workspace.window, workspace.sheet == nil, workspace.conflict == nil else { return event }
        if event.window?.firstResponder is NSTextView || event.window?.firstResponder is NSTextField { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option) {
            switch event.keyCode { case 123: workspace.current.back(); return nil; case 124: workspace.current.forward(); return nil; case 126: workspace.current.up(); return nil; default: break }
        }
        if flags.contains(.control), !flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": workspace.copy(); case "x": workspace.copy(cut: true); case "v": workspace.paste(); case "a": workspace.selectAll(); case "z": workspace.operations.undo(redo: flags.contains(.shift)); case "t": workspace.newTab(); case "w": workspace.closeTab(workspace.activeID); case "l": workspace.addressFocused = true; case "f": workspace.searchFocused = true; default: return event
            }
            return nil
        }
        guard !flags.contains(.command), !flags.contains(.control) else { return event }
        switch event.keyCode {
        case 120: if !workspace.selected.isEmpty { workspace.sheet = .rename }; return nil
        case 96: workspace.current.refresh(); return nil
        case 51, 117: workspace.delete(permanent: flags.contains(.shift)); return nil
        case 49: workspace.quickLook(); return nil
        case 36, 76: workspace.openSelection(); return nil
        case 125 where workspace.current.options.view != .details: workspace.moveSelection(1, extend: flags.contains(.shift)); return nil
        case 126 where workspace.current.options.view != .details: workspace.moveSelection(-1, extend: flags.contains(.shift)); return nil
        default: return event
        }
    }
}
