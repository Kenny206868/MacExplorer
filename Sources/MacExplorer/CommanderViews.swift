import SwiftUI
import ExplorerCore

struct PowerToolsMenu: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var settings = CommanderPreferences.shared
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        Menu {
            Button("Enable Commander Workspace") {
                settings.showCommandBar = true
                if workspace.paneController == nil { workspace.toggleDualPane() }
            }
            Toggle("Show Commander Command Bar", isOn: $settings.showCommandBar)
            Toggle("Classic F3–F8 File Commands", isOn: $settings.classicFunctionKeys)
            Divider()
            Menu("Selection") { CommanderMenuActions(workspace: workspace, actions: [.selectMask, .invert, .sameExtension]) }
            Menu("File Tools") { CommanderMenuActions(workspace: workspace, actions: [.compare, .rename, .pack, .extract]) }
            Divider()
            Toggle("Compact Rows", isOn: $preferences.value.compact)
            Toggle("Item Checkboxes", isOn: $preferences.value.checkboxes)
            Toggle("Hidden Items", isOn: $preferences.value.showHidden)
            Divider()
            CommanderMenuActions(workspace: workspace, actions: [.settings])
        } label: { Label("Power Tools", systemImage: "command.square") }
            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11, weight: .medium))
            .disabled(WorkspaceCommandScope.target(workspace) !== workspace)
            .help("Optional Commander tools, selection masks and keyboard profile")
            .accessibilityIdentifier("explorer.powerTools")
    }
}
struct CommanderMenuActions: View {
    @ObservedObject var workspace: ExplorerWorkspace
    let actions: [CommanderAction]
    var body: some View {
        ForEach(actions) { action in
            Button { action.perform(in: workspace) } label: { Label(action.title, systemImage: action.symbol) }
                .disabled(!action.enabled(in: workspace))
        }
    }
}
struct CommanderCommandBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var settings = CommanderPreferences.shared
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        if settings.showCommandBar {
            VStack(spacing: 0) {
                ExplorerRule()
                HStack(spacing: 6) {
                    ForEach(CommanderAction.functionActions) { action in
                        Button { action.perform(in: workspace) } label: {
                            HStack(spacing: 6) {
                                if settings.classicFunctionKeys {
                                    Text(action.key).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(ExplorerDesign.muted)
                                } else { Image(systemName: action.symbol).font(.system(size: 11)) }
                                Text(action == .newFolder ? "Folder…" : action.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }.frame(maxWidth: .infinity).frame(height: input.touchFriendly ? 44 : 28).contentShape(Rectangle())
                        }.buttonStyle(ExplorerIconStyle()).disabled(!action.enabled(in: workspace))
                            .help(help(action)).accessibilityLabel(help(action)).accessibilityIdentifier("explorer.commander." + action.rawValue)
                    }
                    Divider().frame(height: 16).padding(.horizontal, 3)
                    Menu { CommanderMenuActions(workspace: workspace, actions: [.selectMask, .invert, .sameExtension]) } label: { Text("Select") }
                        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                    Menu { CommanderMenuActions(workspace: workspace, actions: [.compare, .rename, .pack, .extract, .settings]) } label: { Text("Tools") }
                        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                }.padding(.horizontal, 12).padding(.vertical, 4).background(ExplorerDesign.chrome)
            }.accessibilityIdentifier("explorer.commanderBar")
        }
    }
    private func help(_ action: CommanderAction) -> String {
        let prefix = settings.classicFunctionKeys ? action.key + " · " : ""
        switch action {
        case .copy: return prefix + "Copy selected items to the other pane"
        case .move: return prefix + "Confirm moving selected items to the other pane"
        case .edit: return prefix + "Edit selected file in TextEdit"
        case .trash: return prefix + "Confirm moving selected items to Trash"
        default: return prefix + action.title
        }
    }
}
struct CommanderSettingsView: View {
    @ObservedObject private var settings = CommanderPreferences.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "command.square").font(.system(size: 30, weight: .light)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Commander workspace").font(.title3.weight(.semibold))
                    Text("Power tools when you need them. A clean Mac workspace when you don't.").font(.caption).foregroundStyle(ExplorerDesign.muted)
                }
            }.padding(24)
            Form {
                Section("Commands") {
                    Toggle("Show the Commander command bar", isOn: $settings.showCommandBar)
                    Toggle("Use classic F3–F8 file commands", isOn: $settings.classicFunctionKeys)
                    Text("F3 View · F4 TextEdit · F5 Copy · F6 Move · F7 Folder · F8 Trash. Only file-surface focus is remapped. Editors, archive tables, sheets and VoiceOver retain their keys. The keyboard may require Fn.")
                        .font(.caption).foregroundStyle(ExplorerDesign.muted)
                }
                Section("Window and panes") {
                    Toggle("Compact native title bar", isOn: $settings.compactTitlebar)
                    Toggle("Show available storage in each pane", isOn: $settings.paneStorage)
                    Toggle("Show a Terminal button beside each pane path", isOn: $settings.paneTerminalButtons)
                }
                Section("Always available") {
                    Text("⇧⌘D dual panes · Tab switch file panes · ⌘L edit full path · ⌥⌘Return Terminal · ⇧⌥⌘Return both Terminals. Type a path, Tab to complete, Return to open.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Text("Selection masks, multi-rename, archive tools and read-only folder comparison are available in Power Tools. Move and Trash keep their confirmation and collision safeguards.")
                        .font(.caption).foregroundStyle(ExplorerDesign.muted)
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
        }.frame(width: 590, height: 570).accessibilityIdentifier("explorer.commanderSettings")
    }
}
