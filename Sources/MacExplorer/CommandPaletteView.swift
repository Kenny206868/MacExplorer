import SwiftUI
import AppKit

@MainActor struct CommandPaletteView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @StateObject private var model: CommandPaletteModel
    @ObservedObject private var input = InputPreferences.shared
    @FocusState private var searchFocused: Bool
    @State private var error: String?
    init(workspace: ExplorerWorkspace, model: CommandPaletteModel? = nil) {
        self.workspace = workspace; _model = StateObject(wrappedValue: model ?? CommandPaletteModel())
    }
    private var selectedReason: String? { model.selection.flatMap { $0.unavailable(in: workspace) } }
    var body: some View {
        VStack(spacing: 0) {
            titlebar
            searchbar
            ExplorerRule()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if model.matches.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundStyle(ExplorerDesign.muted)
                                Text("No matching commands").font(.system(size: 15, weight: .semibold))
                                Text("Try a task such as “new folder”, “split”, or “hidden”.").font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted)
                            }.frame(maxWidth: .infinity).padding(.top, 90)
                        } else {
                            ForEach(model.matches) { command in row(command).id(command) }
                        }
                    }.padding(10)
                }.onChange(of: model.selection) { _, selected in if let selected { scroll.scrollTo(selected) } }
            }
            ExplorerRule()
            footer
        }.frame(width: 680, height: input.touchFriendly ? 600 : 540)
            .foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
            .accessibilityIdentifier("explorer.commandPalette")
            .onAppear { searchFocused = true }
            .onChange(of: model.query) { _, _ in error = nil }
    }
    private var titlebar: some View {
        HStack(spacing: 10) {
            Image(systemName: "command.square").font(.system(size: 17)).foregroundStyle(Color.accentColor)
            Text("Commands").font(.system(size: 14, weight: .semibold))
            Text("·").foregroundStyle(ExplorerDesign.muted)
            Text(workspace.current.location.title).font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button { workspace.sheet = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: input.target, height: input.target) }
                .buttonStyle(ExplorerIconStyle()).keyboardShortcut(.cancelAction).accessibilityLabel("Close command palette")
        }.padding(.leading, 22).padding(.trailing, 12).frame(height: 50).background(ExplorerDesign.chrome)
    }
    private var searchbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(ExplorerDesign.muted)
            TextField("Search commands…", text: $model.query).font(.system(size: 17)).textFieldStyle(.plain).focused($searchFocused)
                .onSubmit(runSelected).onExitCommand { workspace.sheet = nil }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { navigate($0, offset: 1) }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { navigate($0, offset: -1) }
                .accessibilityLabel("Search commands").accessibilityIdentifier("explorer.commandSearch")
            if !model.query.isEmpty {
                Button { model.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(ExplorerDesign.muted) }
                    .buttonStyle(.plain).accessibilityLabel("Clear command search")
            }
        }.padding(.horizontal, 22).frame(height: 64)
    }
    private func row(_ command: ExplorerCommand) -> some View {
        let spec = command.spec, reason = command.unavailable(in: workspace), selected = model.selection == command
        return Button { model.selection = command; runSelected() } label: {
            HStack(spacing: 13) {
                Image(systemName: spec.symbol).font(.system(size: 15)).frame(width: 28).foregroundStyle(reason == nil ? Color.accentColor : ExplorerDesign.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                    Text(reason ?? spec.category).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
                Spacer(minLength: 12)
                if !spec.shortcut.isEmpty { Text(spec.shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(ExplorerDesign.muted) }
                if reason != nil { Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted) }
            }.padding(.horizontal, 12).frame(height: input.touchFriendly ? 56 : 48)
                .background(selected ? ExplorerDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spec.title + ", " + (reason ?? spec.category) + (spec.shortcut.isEmpty ? "" : ", " + spec.shortcut))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(reason ?? "Run this command in the pane shown above")
    }
    private var footer: some View {
        HStack(spacing: 10) {
            Text(error ?? selectedReason ?? "↑ ↓ to navigate · Return to run · Escape to close")
                .font(.system(size: 11)).foregroundStyle(error == nil ? ExplorerDesign.muted : Color.red).lineLimit(2)
            Spacer(minLength: 8)
            Text("\(model.matches.count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(ExplorerDesign.muted)
                .accessibilityLabel("\(model.matches.count) matching commands")
            Button("Run", action: runSelected).buttonStyle(ExplorerButtonStyle(primary: true)).disabled(model.selection == nil || selectedReason != nil)
        }.padding(.horizontal, 16).frame(height: input.touchFriendly ? 56 : 50).background(ExplorerDesign.chrome)
    }
    private func navigate(_ key: KeyPress, offset: Int) -> KeyPress.Result {
        guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return .ignored }
        model.move(offset); return .handled
    }
    private func runSelected() {
        guard let command = model.selection else { return }
        do { let invocation = try CommandInvocation(command, workspace: workspace); error = nil; invocation.enqueue() }
        catch { self.error = error.localizedDescription }
    }
}
