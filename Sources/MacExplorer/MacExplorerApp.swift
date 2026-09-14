import SwiftUI
import AppKit
import Sparkle
import ExplorerCore

@main struct MacExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var preferences = PreferenceStore.shared
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        WindowGroup("MacExplorer", id: "explorer") {
            ExplorerWindow().environmentObject(preferences).environmentObject(updater).preferredColorScheme(preferences.colorScheme)
        }.defaultSize(width: 1260, height: 800).windowStyle(.titleBar)
            .commands { ExplorerCommands(updater: updater) }
        WindowGroup("MacExplorer", id: "detached", for: BrowserSession.self) { session in
            ExplorerWindow(session: session.wrappedValue).environmentObject(preferences).environmentObject(updater).preferredColorScheme(preferences.colorScheme)
        }.defaultSize(width: 1260, height: 800).windowStyle(.titleBar)
        WindowGroup("MacExplorer", id: "restored-session", for: WindowSession.self) { session in
            ExplorerWindow(windowSession: session.wrappedValue).environmentObject(preferences).environmentObject(updater).preferredColorScheme(preferences.colorScheme)
        }.defaultSize(width: 1260, height: 800).windowStyle(.titleBar)
        Window("Window History", id: "session-history") {
            SessionHistoryView().environmentObject(preferences).preferredColorScheme(preferences.colorScheme)
        }.defaultSize(width: 680, height: 480)
        Settings { PreferencesView().environmentObject(preferences).environmentObject(updater).preferredColorScheme(preferences.colorScheme) }
    }
}

@MainActor final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController
    let configured: Bool
    @Published var canCheck = false
    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        configured = Data(base64Encoded: key)?.count == 32 && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        if configured { controller.startUpdater() }
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func check() { if configured { controller.checkForUpdates(nil) } }
    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
}
struct WorkspaceFocusKey: FocusedValueKey { typealias Value = ExplorerWorkspace }
extension FocusedValues {
    var explorerWorkspace: ExplorerWorkspace? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}
