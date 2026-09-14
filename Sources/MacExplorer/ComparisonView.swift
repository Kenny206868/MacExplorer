import SwiftUI
import AppKit
import ExplorerCore

@MainActor struct ComparisonView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @StateObject private var model: ComparisonModel
    @ObservedObject private var input = InputPreferences.shared
    init(workspace: ExplorerWorkspace, model: ComparisonModel? = nil) {
        self.workspace = workspace; _model = StateObject(wrappedValue: model ?? ComparisonModel(workspace: workspace))
    }
    var body: some View {
        VStack(spacing: 0) {
            heading
            roots
            options
            ExplorerRule()
            filters
            ExplorerRule()
            results
            ExplorerRule()
            footer
        }.frame(width: 880, height: 670)
            .foregroundStyle(ExplorerDesign.text).background(ExplorerDesign.canvas)
            .accessibilityIdentifier("explorer.folderComparison")
            .onDisappear { model.cancel() }
    }
    private var heading: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 22, weight: .light)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text("Compare folders").font(.system(size: 20, weight: .semibold))
                Text("Current folder level · Read-only comparison").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
            }
            Spacer()
            Label("No automatic sync", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            Button("Done") { model.cancel(); workspace.sheet = nil }.buttonStyle(ExplorerButtonStyle()).keyboardShortcut(.cancelAction)
        }.padding(.horizontal, 22).frame(height: 76).background(ExplorerDesign.chrome)
    }
    private var roots: some View {
        HStack(spacing: 14) {
            root(model.context?.leftURL, title: "FIRST PANE", number: "1")
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 13)).foregroundStyle(ExplorerDesign.muted)
            root(model.context?.rightURL, title: "SECOND PANE", number: "2")
        }.padding(.horizontal, 22).padding(.top, 18)
    }
    private func root(_ url: URL?, title: String, number: String) -> some View {
        HStack(spacing: 11) {
            Text(number).font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
                .background(ExplorerDesign.selection, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(ExplorerDesign.muted)
                Text(url?.lastPathComponent ?? "No folder").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(url?.path ?? "Open a folder in this pane").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 9))
    }
    private var options: some View {
        HStack(spacing: 16) {
            Text("Compare").fixedSize()
            Picker("Comparison method", selection: $model.mode) { ForEach(ComparisonMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .labelsHidden().pickerStyle(.segmented).frame(width: 212).disabled(model.running)
            Picker("Names", selection: $model.names) { ForEach(ComparisonNamePolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .frame(width: 188).disabled(model.running)
            Spacer(minLength: 0)
            if model.running {
                ProgressView().controlSize(.small)
                Button(model.cancelling ? "Cancelling…" : "Cancel") { model.cancel() }.buttonStyle(ExplorerButtonStyle()).disabled(model.cancelling)
            } else {
                Button(model.report == nil ? "Compare" : "Compare Again") { Task { await model.compare() } }
                    .buttonStyle(ExplorerButtonStyle(primary: true)).disabled(model.context == nil).keyboardShortcut(.defaultAction)
            }
        }.font(.system(size: 11)).padding(.horizontal, 22).padding(.vertical, 16)
    }
    private var filters: some View {
        HStack(spacing: 5) {
            ForEach(ComparisonFilter.allCases) { filter in
                Button { model.filter = filter } label: {
                    HStack(spacing: 5) {
                        Text(filter.rawValue)
                        Text("\(model.counts[filter] ?? 0)").monospacedDigit().foregroundStyle(ExplorerDesign.muted)
                    }.font(.system(size: 11)).padding(.horizontal, 9).frame(height: input.touchFriendly ? 44 : 32)
                }.buttonStyle(ExplorerIconStyle(selected: model.filter == filter))
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(ExplorerDesign.muted)
                TextField("Filter names", text: $model.query).textFieldStyle(.plain).accessibilityLabel("Filter comparison filenames")
            }.font(.system(size: 11)).padding(8).frame(width: 174)
                .background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 6))
        }.padding(.horizontal, 16).frame(height: input.touchFriendly ? 54 : 46)
    }
    private var results: some View {
        Group {
            if model.running {
                VStack(spacing: 14) {
                    ProgressView(value: Double(model.progress?.completed ?? 0), total: Double(max(1, model.progress?.total ?? 1))).frame(width: 260)
                    Text(model.cancelling ? "Stopping at the next I/O boundary…" : model.progress?.name ?? "Reading folder metadata…").font(.system(size: 13)).lineLimit(1)
                    Text("No files will be changed.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                ContentUnavailableView("Comparison unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.report == nil {
                ContentUnavailableView("Choose how to compare", systemImage: "doc.text.magnifyingglass", description: Text("Size & date reads metadata only. File data compares regular files byte for byte, up to 2 GiB of reads. Subfolders and packages are not traversed."))
            } else if model.visible.isEmpty {
                ContentUnavailableView(model.report?.rows.isEmpty == true ? "Both folders are empty" : "No results in this filter", systemImage: "checkmark.circle", description: Text("Change the filter to see other comparison results."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(model.visible) { row in
                                ComparisonResultRow(row: row, marked: model.marked.contains(row.id), touch: input.touchFriendly) { model.toggle(row) }
                            }
                        } header: { columnHeadings }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var columnHeadings: some View {
        HStack(spacing: 12) {
            Text("FILE NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("FIRST").frame(width: 72, alignment: .trailing)
            Text("SECOND").frame(width: 72, alignment: .trailing)
            Text("RESULT").frame(width: 170, alignment: .leading)
        }.font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(ExplorerDesign.muted)
            .padding(.leading, 48).padding(.trailing, 20).frame(height: 32).background(ExplorerDesign.chrome)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Button("Mark Differences") { model.markDifferences() }.disabled(model.report == nil || model.running)
                Button("Clear") { model.marked = [] }.disabled(model.marked.isEmpty || model.running)
                Spacer(minLength: 8)
                Button("Select in First (\(model.markedFiles(.primary)))") { model.selectInPane(.primary) }
                    .disabled(model.markedFiles(.primary) == 0 || model.running)
                Button("Select in Second (\(model.markedFiles(.secondary)))") { model.selectInPane(.secondary) }
                    .disabled(model.markedFiles(.secondary) == 0 || model.running)
            }.buttonStyle(ExplorerButtonStyle())
            Text("Selection only: use the normal copy/move controls afterward. “Matching metadata” does not verify file data. Resource forks, attributes and permissions are not compared.")
                .font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 20).padding(.vertical, 14).background(ExplorerDesign.chrome)
    }
}

@MainActor private struct ComparisonResultRow: View {
    let row: ComparisonRow
    let marked: Bool
    let touch: Bool
    let action: () -> Void
    private var selectable: Bool { ComparisonModel.canMark(row) }
    private var symbol: String {
        switch row.status {
        case .matchingData: return "checkmark.circle"
        case .metadataMatch: return "equal.circle"
        case .leftOnly: return "arrow.left.circle"
        case .rightOnly: return "arrow.right.circle"
        case .different, .typeConflict: return "exclamationmark.circle"
        case .unavailable, .ambiguous: return "exclamationmark.triangle"
        case .notCompared: return "minus.circle"
        }
    }
    var body: some View {
        Button(action: action) { surface }.buttonStyle(.plain).disabled(!selectable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name + ", " + row.status.rawValue + ", " + row.detail)
            .accessibilityAddTraits(marked ? .isSelected : [])
            .help(row.detail)
    }
    private var surface: some View {
        HStack(spacing: 12) {
            Image(systemName: marked ? "checkmark.square.fill" : "square").font(.system(size: 13)).foregroundStyle(marked ? Color.accentColor : ExplorerDesign.muted).frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name).font(.system(size: 12, weight: marked ? .medium : .regular)).lineLimit(1).truncationMode(.middle)
                if row.left.first?.name != row.right.first?.name, !row.left.isEmpty, !row.right.isEmpty {
                    Text(row.right.map(\.name).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(size(row.left)).frame(width: 72, alignment: .trailing)
            Text(size(row.right)).frame(width: 72, alignment: .trailing)
            Label(row.status.rawValue, systemImage: symbol).font(.system(size: 10)).frame(width: 170, alignment: .leading)
                .foregroundStyle(row.status.isDifference ? Color.orange : row.status == .matchingData ? Color.green : ExplorerDesign.muted)
        }.font(.system(size: 11)).padding(.horizontal, 20).frame(height: touch ? 54 : 46)
            .background(marked ? ExplorerDesign.selection : ExplorerDesign.canvas)
            .overlay(alignment: .bottom) { ExplorerRule().opacity(0.5) }.contentShape(Rectangle())
    }
    private func size(_ values: [ComparisonFile]) -> String {
        guard values.count == 1, let stamp = values.first?.stamp, stamp.kind == .file else { return values.isEmpty ? "—" : "Folder / link" }
        return ByteCountFormatter.string(fromByteCount: stamp.size, countStyle: .file)
    }
}
