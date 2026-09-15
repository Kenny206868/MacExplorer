import SwiftUI
import ExplorerCore

@MainActor final class SelectionMaskModel: ObservableObject {
    enum Mode: String, CaseIterable { case replace = "Replace selection", add = "Add to selection", remove = "Remove from selection" }
    @Published var pattern = "*"
    @Published var includeFolders = false
    @Published var caseSensitive = false
    @Published var mode = Mode.replace
    @Published private(set) var names: [String] = []
    @Published private(set) var matches: Set<URL> = []
    @Published private(set) var error: String?
    @Published private(set) var working = false
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var tabID: UUID?
    private var revision: UInt64 = 0
    private var navigable: [URL] = []
    func update(tab: BrowserTab) {
        cancel(); working = true; error = nil; matches = []; names = []
        tabID = tab.id; revision = tab.dataRevision
        let entries = tab.navigation.entries
        navigable = tab.navigation.order.ids
        let token = generation, pattern = pattern, includeFolders = includeFolders, caseSensitive = caseSensitive
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                let result = try await FileReadExecutor.presentation.run { cancellation -> (Set<URL>, [String]) in
                    let mask = try FilenameSelectionMask(pattern, caseSensitive: caseSensitive)
                    var urls = Set<URL>(), names: [String] = []
                    for (index, entry) in entries.enumerated() {
                        if index & 127 == 0 { try cancellation.check() }
                        if (includeFolders || !entry.isDirectory) && mask.matches(entry.name) {
                            urls.insert(entry.url); if names.count < 80 { names.append(entry.name) }
                        }
                    }
                    return (urls, names)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.matches = result.0; self.names = result.1; self.working = false
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription; self.working = false
            }
        }
    }
    /// A refresh, regrouping or collapsed-group change invalidates a preview;
    /// applying it cannot accidentally select a different visible listing.
    func apply(to tab: BrowserTab) -> Bool {
        guard !working, error == nil, tab.id == tabID, tab.dataRevision == revision,
              tab.navigation.order.ids == navigable else { return false }
        let visible = Set(navigable)
        var selection = tab.selection.intersection(visible)
        switch mode { case .replace: selection = matches; case .add: selection.formUnion(matches); case .remove: selection.subtract(matches) }
        tab.rangeBaseline = nil; tab.selection = selection
        if let focus = tab.focusedURL, !visible.contains(focus) { tab.focusedURL = nil }
        return true
    }
    func cancel() { generation &+= 1; task?.cancel(); task = nil; working = false }
    deinit { task?.cancel() }
}

struct SelectionMaskView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @StateObject private var model = SelectionMaskModel()
    var initialPattern = "*"
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Select by pattern").font(.title3.weight(.semibold))
                    Text(tab.location.title).font(.caption).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
                Spacer()
            }
            TextField("*.swift;*.cs | *.g.cs", text: $model.pattern).textFieldStyle(.roundedBorder).focused($focused)
                .accessibilityLabel("Included and excluded filename masks")
            Text("* matches any text · ? matches one character · ; combines masks · | excludes masks")
                .font(.caption).foregroundStyle(ExplorerDesign.muted)
            HStack {
                Toggle("Include folders", isOn: $model.includeFolders)
                Toggle("Case sensitive", isOn: $model.caseSensitive)
                Spacer()
            }.toggleStyle(.checkbox).font(.system(size: 12))
            Picker("Selection", selection: $model.mode) { ForEach(SelectionMaskModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            HStack {
                Text("\(model.matches.count) matching items").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Spacer(); if model.working { ProgressView().controlSize(.small).accessibilityLabel("Matching names") }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(model.names.enumerated()), id: \.offset) { _, name in Text(name).font(.system(size: 12)).lineLimit(1) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 160).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 8))
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Current visible listing only; no additional recursion or filesystem reads. Preview shows up to 80 names. Hidden or collapsed items are not selected.")
                .font(.caption).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply Selection") {
                    guard workspace.current === tab, model.apply(to: tab) else { model.update(tab: tab); return }
                    dismiss(); workspace.focusFileSurface()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.working || model.error != nil)
            }
        }.padding(24).frame(width: 530)
            .accessibilityIdentifier("explorer.selectionMask")
            .onAppear { focused = true; model.pattern = initialPattern; model.update(tab: tab) }
            .onChange(of: model.pattern) { _, _ in model.update(tab: tab) }
            .onChange(of: model.includeFolders) { _, _ in model.update(tab: tab) }
            .onChange(of: model.caseSensitive) { _, _ in model.update(tab: tab) }
            .onChange(of: tab.dataRevision) { _, _ in model.update(tab: tab) }
            .onDisappear { model.cancel() }
    }
}
