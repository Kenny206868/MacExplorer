import SwiftUI
import ExplorerCore

struct CollisionView: View {
    let prompt: ConflictPrompt
    @ObservedObject var workspace: ExplorerWorkspace
    @State private var all = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: "An item with this name already exists", subtitle: prompt.collision.destination.lastPathComponent)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("From").foregroundStyle(.secondary); Text(prompt.collision.source.path).textSelection(.enabled) }
                GridRow { Text("To").foregroundStyle(.secondary); Text(prompt.collision.destination.path).textSelection(.enabled) }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                if prompt.collision.canMerge {
                    Label("Merge combines folder contents and keeps existing destination-only items. Conflicting files are decided separately.", systemImage: "folder.badge.plus")
                }
                Text("Keep Both creates a numbered copy. Replace replaces the entire item and retains the old item as a hidden recovery backup.")
            }.font(.callout).foregroundStyle(.secondary)
            Toggle("Apply this decision to remaining conflicts of this kind", isOn: $all)
            Divider()
            HStack(spacing: 10) {
                Button("Cancel Operation") { workspace.answerCollision(.cancel) }.keyboardShortcut(.cancelAction)
                Spacer(minLength: 12)
                Button("Skip") { workspace.answerCollision(.skip, all: all) }
                Button("Replace") { workspace.answerCollision(.replace, all: all) }
                if prompt.collision.canMerge { Button("Merge Folders") { workspace.answerCollision(.merge, all: all) } }
                Button("Keep Both") { workspace.answerCollision(.keepBoth, all: all) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 670)
    }
}
