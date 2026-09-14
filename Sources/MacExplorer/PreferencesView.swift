import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import ExplorerCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", input = "Keyboard & input", integration = "macOS integration", updates = "Updates"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .input: return "keyboard"; case .integration: return "desktopcomputer"; case .updates: return "arrow.down.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: return "Choose how your workspace opens and behaves."
        case .appearance: return "A familiar layout, with the appearance you prefer."
        case .input: return "Work with a keyboard, trackpad, or larger controls."
        case .integration: return "Connect your workspace to macOS, on your terms."
        case .updates: return "Build information and signed software updates."
        }
    }
}
struct PreferencesView: View {
    @EnvironmentObject private var preferences: PreferenceStore
    @EnvironmentObject private var updater: AppUpdater
    @ObservedObject private var input = InputPreferences.shared
    @State private var page: SettingsPage
    @State private var error: String?
    @State private var integrationStatus = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var confirmation: String?
    @State private var help = false
    init(initialPage: SettingsPage = .general) { _page = State(initialValue: initialPage) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 180)
            Rectangle().fill(ExplorerDesign.separator).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.rawValue).font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                    Text(page.subtitle).font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                ExplorerRule()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .general: general
                        case .appearance: appearance
                        case .input: inputSettings
                        case .integration: integration
                        case .updates: updates
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ExplorerDesign.canvas)
        }.foregroundStyle(ExplorerDesign.text).frame(width: 682, height: 535)
            .sheet(isPresented: $help) { KeyboardHelpView() }
            .alert("MacExplorer Settings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog(confirmation ?? "Confirm", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                if confirmation == "Use MacExplorer as the folder handler?" { Button("Use MacExplorer") { setFolderHandler(finder: false) } }
                else if confirmation == "Clear recent files?" { Button("Clear Recent Files", role: .destructive) { preferences.value.recent = [] } }
                else { Button("Reset Folder Views", role: .destructive) { preferences.value.folders = [:] } }
                Button("Cancel", role: .cancel) { confirmation = nil }
            }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Settings", systemImage: "gearshape").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 12).padding(.top, 26).padding(.bottom, 22)
            ForEach(SettingsPage.allCases) { value in
                Button { page = value } label: {
                    HStack(spacing: 9) {
                        Image(systemName: value.symbol).frame(width: 18).foregroundStyle(page == value ? Color.accentColor : ExplorerDesign.muted)
                        Text(value.rawValue).font(.system(size: 11, weight: page == value ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(height: 37)
                        .background(page == value ? ExplorerDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityAddTraits(page == value ? .isSelected : [])
                    .accessibilityIdentifier("settings." + value.id)
            }
            Spacer()
            Text("MacExplorer").font(.system(size: 11, weight: .medium)).padding(.horizontal, 12)
            Text("Your files. Your workspace.").font(.system(size: 9)).foregroundStyle(ExplorerDesign.muted).padding(.horizontal, 12).padding(.bottom, 20)
        }.padding(.horizontal, 8).frame(maxHeight: .infinity).background(ExplorerDesign.sidebar)
    }
    private var general: some View {
        Group {
            SettingsCard("WORKSPACE") {
                settingToggle("Restore windows and tabs at launch", value: $preferences.value.restoreTabs)
                SettingsSeparator()
                HStack { Text("New window opens to"); Spacer(); Picker("New window opens to", selection: $preferences.value.startLocation) { Text("Home").tag("Home"); Text("This Mac").tag("This Mac") }.labelsHidden().frame(width: 130) }
                SettingsSeparator()
                settingToggle("Single-click to open files", value: $preferences.value.singleClickOpen)
                Text("Select mode and modifier-key selections always keep files closed.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            SettingsCard("FILES & SEARCH") {
                settingToggle("Confirm before moving items to Trash", value: $preferences.value.confirmTrash)
                SettingsSeparator(); settingToggle("Include subfolders in searches", value: $preferences.value.recursiveSearch)
            }
            SettingsCard("HISTORY") {
                Text("Recent files include documents opened through MacExplorer. No browsing telemetry is collected.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                HStack { Button("Clear Recent…") { confirmation = "Clear recent files?" }; Button("Reset Folder Views…") { confirmation = "Reset saved folder layouts?" } }.buttonStyle(ExplorerButtonStyle())
            }
        }
    }
    private var appearance: some View {
        Group {
            SettingsCard("APPEARANCE") {
                HStack(spacing: 10) {
                    ForEach([("system", "System"), ("light", "Light"), ("dark", "Dark")], id: \.0) { key, title in
                        AppearanceChoice(title: title, dark: key == "dark", mixed: key == "system", selected: preferences.value.theme == key) { preferences.value.theme = key }
                    }
                }
                Text("Uses your macOS accent color and respects increased contrast.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            SettingsCard("FILE PRESENTATION") {
                settingToggle("Show file name extensions", value: $preferences.value.showExtensions)
                SettingsSeparator(); settingToggle("Show hidden items", value: $preferences.value.showHidden)
                SettingsSeparator(); settingToggle("Show selection checkboxes", value: $preferences.value.checkboxes)
                SettingsSeparator(); settingToggle("Compact desktop rows", value: $preferences.value.compact)
                Text("Touch-friendly controls take priority over compact rows. Folder layouts and sort/group settings are remembered individually.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            SettingsCard("AUXILIARY PANES") {
                settingToggle("Details pane", value: $preferences.value.inspector)
                SettingsSeparator(); settingToggle("Quick Look preview pane", value: $preferences.value.previewPane)
            }
        }
    }
    private var inputSettings: some View {
        Group {
            SettingsCard("CONTROLS") {
                settingToggle("Touch-friendly controls", value: $input.touchFriendly)
                Text("44-point file rows and action targets. Use Select, Open, and More Actions without hover or modifier keys.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                HStack(spacing: 9) { Image(systemName: "hand.tap").font(.system(size: 22)).foregroundStyle(Color.accentColor); Text("Press and hold a file for actions. In Select mode, tap to add or remove files.").font(.system(size: 11)) }.padding(.top, 4)
            }
            SettingsCard("TRACKPAD & MOUSE") {
                settingToggle("Enable trackpad gestures", value: $input.gesturesEnabled)
                SettingsSeparator()
                shortcut("Swipe horizontally", "Back / forward")
                shortcut("Pinch", "Change icon density")
                shortcut("Smart zoom or force click", "Quick Look")
                Text("Regular two-finger scrolling stays native. Gesture availability follows your macOS preferences and hardware.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            SettingsCard("KEYBOARD") {
                shortcut("⌘⇧D", "Toggle dual panes")
                shortcut("Tab", "Switch active file pane")
                shortcut("F6 / Shift-F6", "Cycle location, search, and files")
                Button("All keyboard shortcuts…") { help = true }.buttonStyle(ExplorerButtonStyle())
                Text("macOS and Explorer-style shortcuts coexist. Text editors, dialogs, and assistive technologies keep their own keys.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
        }
    }
    private var integration: some View {
        Group {
            SettingsCard("OPEN FOLDERS") {
                Text("Use MacExplorer when opening folders through the public macOS folder association.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                Button("Use MacExplorer…") { confirmation = "Use MacExplorer as the folder handler?" }.buttonStyle(ExplorerButtonStyle(primary: true))
                Button("Restore Finder") { setFolderHandler(finder: true) }.buttonStyle(ExplorerButtonStyle())
                Text("Reversible. Finder continues to manage its desktop, Dock services, and protected system components.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            SettingsCard("STARTUP & ACCESS") {
                settingToggle("Open at login", value: Binding(get: { loginEnabled }, set: setLogin))
                Button("Login Item Settings") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(ExplorerButtonStyle())
                Button("Full Disk Access Settings") { NativeIntegration.privacySettings() }.buttonStyle(ExplorerButtonStyle())
            }
            SettingsCard("OPEN FROM OTHER APPS") {
                Text("Finder → Services → Open in MacExplorer\nopen -a MacExplorer /path/to/folder\nmacexplorer://open?path=/path/to/folder").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Text("Install MacExplorer.app in Applications to register Services, URL routing and login items.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
            if !integrationStatus.isEmpty { Label(integrationStatus, systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(.green) }
        }
    }
    private var installedVersion: String {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return "Development build" }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
    }
    private var updates: some View {
        Group {
            SettingsCard("INSTALLED BUILD") {
                HStack(spacing: 15) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MacExplorer").font(.system(size: 17, weight: .semibold))
                        Text(installedVersion).foregroundStyle(ExplorerDesign.muted)
                    }
                }.padding(.vertical, 8)
            }
            SettingsCard("SOFTWARE UPDATES") {
                if updater.configured {
                    settingToggle("Automatically check for updates", value: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
                    Button("Check for Updates…") { updater.check() }.buttonStyle(ExplorerButtonStyle(primary: true)).disabled(!updater.canCheck)
                    Text("Sparkle verifies update signatures before installation. Automatic installation is off by default.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                } else {
                    Label("Development update channel", systemImage: "info.circle").font(.system(size: 12, weight: .medium))
                    Text("This build has no production update-signing key. Automatic updates remain disabled rather than trusting an unsigned feed.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                }
                Link("Published alphas and release notes", destination: URL(string: "https://github.com/wieslawsoltes/MacExplorer/releases")!).font(.system(size: 12))
            }
        }
    }
    private func settingToggle(_ title: String, value: Binding<Bool>) -> some View { Toggle(title, isOn: value).toggleStyle(.switch).controlSize(.small).font(.system(size: 12)) }
    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack { Text(key).font(.system(size: 10, weight: .medium, design: .monospaced)); Spacer(); Text(action).font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted) }
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
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(ExplorerDesign.muted)
            VStack(alignment: .leading, spacing: 12) { content }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(15).background(ExplorerDesign.chrome.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ExplorerDesign.separator, lineWidth: 1))
        }
    }
}
private struct SettingsSeparator: View { var body: some View { ExplorerRule().opacity(0.75) } }
private struct AppearanceChoice: View {
    let title: String
    let dark: Bool
    let mixed: Bool
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    Rectangle().fill(dark ? Color(white: 0.22) : Color(white: 0.90)).frame(width: 19)
                    VStack(spacing: 4) {
                        Capsule().fill(Color.accentColor.opacity(0.8)).frame(height: 5)
                        ForEach(0..<3) { _ in Capsule().fill(dark ? Color(white: 0.35) : Color(white: 0.83)).frame(height: 3) }
                    }.padding(6)
                    if mixed { Rectangle().fill(Color(white: 0.19)).frame(width: 20) }
                }.frame(height: 53).background(dark ? Color(white: 0.12) : .white).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
            }.padding(7).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : ExplorerDesign.separator, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityLabel(title + " appearance")
    }
}
