import SwiftUI
import AppKit
import QuickLookUI
import UniformTypeIdentifiers
import ExplorerCore

@MainActor enum NativeIntegration {
    static func chooseFolder(owner: ExplorerWorkspace, completion: ((URL) -> Void)? = nil) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = owner.destination; panel.prompt = completion == nil ? "Open Folder" : "Choose"
        let answer: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { if let completion { completion(url) } else { owner.navigate(.folder(url)) } }
        }
        if let window = owner.window { panel.beginSheetModal(for: window, completionHandler: answer) } else { panel.begin(completionHandler: answer) }
    }
    static func copyPaths(_ urls: [URL]) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string) }
    static func openWith(_ urls: [URL], application: URL, owner: ExplorerWorkspace) {
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in owner.fail("Open failed", error.localizedDescription) } }
        }
    }
    static func terminal(_ directory: URL, owner: ExplorerWorkspace) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { owner.fail("Terminal unavailable", "Terminal.app could not be located."); return }
        openWith([directory], application: app, owner: owner)
    }
    static func connect(_ address: String, owner: ExplorerWorkspace) {
        guard let url = URL(string: address), ["smb", "afp", "nfs", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { owner.fail("Invalid server address", "Use smb://server/share, afp://server/share, nfs://server/path, or an HTTPS WebDAV address."); return }
        guard url.user == nil, url.password == nil else { owner.fail("Do not include credentials", "Enter only the server address. macOS will request credentials using its own authentication interface."); return }
        if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") { openWith([url], application: finder, owner: owner) }
        else if !NSWorkspace.shared.open(url) { owner.fail("Connection failed", "macOS could not open the server address.") }
    }
    static func privacySettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) } }
    static func eject(_ url: URL, owner: ExplorerWorkspace) {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: url) } catch { owner.fail("Could not eject", error.localizedDescription) }
    }
    static func volumes() -> [URL] { FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsLocalKey], options: [.skipHiddenVolumes]) ?? [] }
    static func cloudFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var folders: [URL] = []
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileNames.exists(iCloud) { folders.append(iCloud) }
        folders += (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent("Library/CloudStorage"), includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return folders
    }
    static func trashDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result = [home.appendingPathComponent(".Trash")]
        for volume in volumes() where volume.path != "/" {
            let trash = volume.appendingPathComponent(".Trashes/\(getuid())")
            if FileNames.exists(trash) { result.append(trash) }
        }
        return result
    }
}
struct NativePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = false; view.shouldCloseWithWindow = true; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { if view.previewItem?.previewItemURL != url { view.previewItem = url as NSURL } }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
struct WindowAccessor: NSViewRepresentable {
    let owner: ExplorerWorkspace
    final class View: NSView {
        weak var owner: ExplorerWorkspace?
        let chrome = NativeWindowChrome()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let owner else { return }
            owner.window = window; chrome.attach(to: window, owner: owner); window.minSize = NSSize(width: 800, height: 500)
            window.tabbingMode = .disallowed; AppRouter.shared.active = owner.routedWorkspace
            if !AppRouter.shared.pending.isEmpty { let urls = AppRouter.shared.pending; AppRouter.shared.pending = []; DispatchQueue.main.async { owner.openURLs(urls) } }
        }
    }
    func makeNSView(context: Context) -> View { let view = View(); view.owner = owner; return view }
    func updateNSView(_ view: View, context: Context) { view.owner = owner; if let window = view.window { view.chrome.attach(to: window, owner: owner) } }
}
