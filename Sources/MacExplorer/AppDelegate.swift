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
        NSApp.setActivationPolicy(.regular); NSApp.servicesProvider = self; NSUpdateDynamicServices()
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        AppRouter.shared.pending += arguments.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { KeyboardRouter.handle(event) == nil }
            return consumed ? nil : event
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AppRouter.shared.receive(filenames.map { URL(fileURLWithPath: $0) }); sender.reply(toOpenOrPrint: .success)
    }
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
        WorkspaceSessionCoordinator.shared.prepareToQuit(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func openInMacExplorer(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        if urls.isEmpty { error.pointee = "Select one or more files or folders." }
        else { AppRouter.shared.receive(urls.map { $0 as URL }); NSApp.activate(ignoringOtherApps: true) }
    }
}
