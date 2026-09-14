import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class DetailsColumnStore: ObservableObject {
    static let shared = DetailsColumnStore()
    static let dragType = "com.wieslawsoltes.macexplorer.details-column"
    @Published var value: DetailsColumns
    private let defaults: UserDefaults
    private let key = "MacExplorer.DetailsColumns.v2"
    private var ticket: (UUID, DetailsColumn)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DetailsColumns.self, from: $0) } ?? DetailsColumns()
    }
    func save() { if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) } }
    func reset() { value = DetailsColumns(); save() }
    func toggle(_ column: DetailsColumn) {
        guard column != .name else { return }
        if value.hidden.contains(column) { value.hidden.remove(column) } else { value.hidden.insert(column) }
        save()
    }
    func begin(_ column: DetailsColumn) -> NSItemProvider {
        let id = UUID(); ticket = (id, column)
        let bytes = Data(id.uuidString.utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType, visibility: .ownProcess) { completion in completion(bytes, nil); return nil }
        return provider
    }
    func accept(_ providers: [NSItemProvider], before column: DetailsColumn) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(Self.dragType) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: Self.dragType) { data, _ in
            Task { @MainActor in
                guard let ticket = self.ticket, let data, String(data: data, encoding: .utf8) == ticket.0.uuidString else { return }
                self.value.move(ticket.1, before: column); self.ticket = nil; self.save()
            }
        }
        return true
    }
}
