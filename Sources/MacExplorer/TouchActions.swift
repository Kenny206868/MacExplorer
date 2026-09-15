import SwiftUI
import AppKit
import ExplorerCore

struct TouchFileActions: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "hand.tap").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("File actions").font(.title2.weight(.semibold))
                    Text("\(workspace.selected.count) selected in \(workspace.current.location.title)").font(.callout).foregroundStyle(ExplorerDesign.muted)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ExplorerRule()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                action("Open", "arrow.up.forward.app") { workspace.openSelection() }
                action("Quick Look", "eye") { workspace.quickLook() }
                action("Copy", "doc.on.doc") { workspace.copy() }
                action("Cut", "scissors") { workspace.copy(cut: true) }
                action("Rename", "character.cursor.ibeam") { workspace.requestRename() }
                action("Properties…", "info.circle") { workspace.sheet = .properties }
                action("Tags…", "tag") { workspace.sheet = .tags }
                action("Move to Trash", "trash") { workspace.delete() }
                if let controller = workspace.paneController {
                    action("Copy to other pane", "arrow.right.doc.on.clipboard") { controller.requestTransfer(from: workspace, move: false) }
                    action("Move to other pane…", "arrow.right.square") { controller.requestTransfer(from: workspace, move: true) }
                }
            }.disabled(workspace.selected.isEmpty)
            Text("Use Select mode for multiple files without a keyboard. File operations keep their normal collision and recovery rules.").font(.caption).foregroundStyle(ExplorerDesign.muted)
        }.padding(24).frame(width: 520).background(ExplorerDesign.canvas)
    }
    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button {
            do {
                let snapshot = try FileActionSnapshot(workspace)
                DeferredSheetAction.shared.enqueue(for: workspace, validate: snapshot.validate) { _ in perform() }
            } catch { workspace.sheet = nil; workspace.fail("File action unavailable", error.localizedDescription) }
        } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(ExplorerButtonStyle())
    }
}
struct KeyboardHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let shortcuts: [(String, String)] = [
        ("Cmd/Ctrl + Shift + P", "Search and run commands"),
        ("Cmd/Ctrl + L · Cmd + Shift + G", "Edit or reselect the entire folder path"),
        ("Tab · Cmd + Return", "Complete path / Open path in a new tab"),
        ("Cmd + Option + Return", "Open active location in Terminal"),
        ("Cmd + Shift + Option + Return", "Open both pane locations in Terminal"),
        ("Cmd/Ctrl + Shift + D", "Toggle dual-pane browsing"),
        ("Tab / Shift + Tab", "Switch between file panes"),
        ("Cmd + Option + C", "Copy selected files to the other pane"),
        ("Cmd + Option + M", "Move selected files to the other pane, after confirmation"),
        ("Control + Option", "Reserved for VoiceOver, never a file action"),
        ("F6 / Shift + F6", "Cycle location, search, and file focus"),
        ("F2 / Return / Escape", "Edit a file name / Commit rename / Cancel rename"),
        ("F3 / F4 / F5", "Search / Location / Refresh"),
        ("Arrow keys · Home · End", "Move selection"),
        ("Page Up / Page Down", "Move by the visible page"),
        ("Shift + navigation", "Extend a contiguous selection"),
        ("Ctrl + navigation", "Move focus without changing selection"),
        ("Ctrl + Space", "Toggle the focused file"),
        ("Type a file name", "Incremental type-to-select"),
        ("Alt + Left / Right / Up", "Back / Forward / Parent folder"),
        ("Cmd/Ctrl + T / W", "New tab / Close tab"),
        ("Cmd/Ctrl + Shift + T", "Reopen the last closed tab"),
        ("Ctrl + Tab / Page Up/Down", "Cycle tabs in the active pane"),
        ("Cmd/Ctrl + 1…9", "Select a tab in the active pane"),
        ("Cmd/Ctrl + plus / minus", "Change file-view density"),
        ("Cmd/Ctrl + X / C / V", "Cut / Copy / Paste"),
        ("Cmd/Ctrl + Z · Ctrl + Y", "Undo / Redo"),
        ("Delete / Shift + Delete", "Trash / Confirm permanent deletion"),
        ("Return · Space · Shift + F10", "Open / Quick Look / File actions"),
        ("Trackpad swipe · pinch", "History navigation / Icon density"),
        ("Smart zoom · force click", "Quick Look where the device supports it")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Keyboard & gestures").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Commands operate on the active pane. Text fields, sheets, and Quick Look keep their native keyboard behavior.").font(.callout).foregroundStyle(ExplorerDesign.muted)
            ExplorerRule()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shortcuts, id: \.0) { key, action in
                        HStack(alignment: .top) {
                            Text(key).font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 220, alignment: .leading)
                            Text(action).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 10).overlay(alignment: .bottom) { ExplorerRule() }
                    }
                }
            }
        }.padding(24).frame(width: 720, height: 660).background(ExplorerDesign.canvas)
    }
}
