import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import ExplorerCore

struct PreferencesView: View {
    @EnvironmentObject private var preferences: PreferenceStore
    @EnvironmentObject private var updater: AppUpdater
    @State private var error: String?
    @State private var integrationStatus = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var confirmHandler = false
    var body: some View {
        TabView {
            Form {
                Section("Browsing") {
                    Toggle("Restore tabs when opening a window", isOn: $preferences.value.restoreTabs)
                    Toggle("Single-click to open in icon and list views", isOn: $preferences.value.singleClickOpen)
                    Toggle("Confirm before moving items to Trash", isOn: $preferences.value.confirmTrash)
                    Toggle("Search subfolders", isOn: $preferences.value.recursiveSearch)
                }
                Section("History") {
                    Text("Recent files contain only documents opened through MacExplorer. No browsing telemetry is collected.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear Recent Files") { preferences.value.recent = [] }
                    Button("Reset Per-folder View Settings") { preferences.value.folders = [:] }
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Picker("Appearance", selection: $preferences.value.theme) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
                Section("Files and folders") {
                    Toggle("Show hidden items", isOn: $preferences.value.showHidden)
                    Toggle("Show file name extensions", isOn: $preferences.value.showExtensions)
                    Toggle("Item check boxes in Details view", isOn: $preferences.value.checkboxes)
                    Toggle("Compact rows", isOn: $preferences.value.compact)
                    Toggle("Details pane", isOn: $preferences.value.inspector)
                    Toggle("Quick Look preview pane", isOn: $preferences.value.previewPane)
                }
                Text("Layout, sort order, and grouping are remembered separately for each folder. Column visibility, width, and order use native SwiftUI table customization.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("Appearance", systemImage: "paintpalette") }
            Form {
                Section("macOS integration") {
                    Button("Use MacExplorer to Open Folders…") { confirmHandler = true }
                    Button("Restore Finder as the Folder Handler") { setFolderHandler(finder: true) }
                    Text("This changes the public folder-type association only. Finder remains responsible for the desktop, Dock integration, some system dialogs, and private shell services.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Open at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                    Button("Open Login Item Settings") { SMAppService.openSystemSettingsLoginItems() }
                    Button("Open Full Disk Access Settings") { NativeIntegration.privacySettings() }
                }
                Section("Open from other applications") {
                    Text("Finder → Services → Open in MacExplorer\nTerminal: open -a MacExplorer /path/to/folder\nURL: macexplorer://open?path=/path/to/folder").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Install the app in /Applications for Services, URL routing, and login-item registration. File access always respects macOS privacy controls and permissions.").font(.caption).foregroundStyle(.secondary)
                }
                if !integrationStatus.isEmpty { Text(integrationStatus).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("Integration", systemImage: "desktopcomputer") }
            Form {
                Section("Software updates") {
                    Text("MacExplorer \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")").font(.headline)
                    if updater.configured {
                        Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
                        Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
                        Text("Updates and their feeds are verified with the release signing key before installation. Automatic installation is off by default.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("Updates are not configured in this build", systemImage: "info.circle")
                        Text("A release maintainer must configure a MacExplorer-specific Sparkle public key and publish a signed appcast. Development builds never silently trust unsigned update feeds.").font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Release downloads and release notes", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/releases")!)
                }
            }.formStyle(.grouped).tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }.padding(12).frame(width: 660, height: 535)
            .alert("Integration", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog("Use MacExplorer as the public folder handler?", isPresented: $confirmHandler, titleVisibility: .visible) { Button("Use MacExplorer") { setFolderHandler(finder: false) }; Button("Cancel", role: .cancel) {} } message: { Text("This is reversible here using Restore Finder. It does not replace Finder's protected system components.") }
    }
    private func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { self.error = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private func setFolderHandler(finder: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { error = "Run an installed MacExplorer.app bundle first."; return }
        let application = finder ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") : Bundle.main.bundleURL
        guard let application else { error = "The target application could not be located."; return }
        NSWorkspace.shared.setDefaultApplication(at: application, toOpen: UTType.folder) { failure in
            Task { @MainActor in if let failure { error = failure.localizedDescription } else { integrationStatus = finder ? "Finder is the folder handler." : "MacExplorer is the folder handler." } }
        }
    }
}
