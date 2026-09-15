import SwiftUI
import ExplorerCore

/// One editing session belongs to one visible pane/tab. Every asynchronous
/// result is generation-checked; typing never enumerates on MainActor.
@MainActor final class PathEditorModel: ObservableObject {
    typealias Resolve = @Sendable (String, URL, URL) async throws -> PathResolution
    typealias Complete = @Sendable (String, URL, URL, Bool) async throws -> PathSuggestions
    @Published private(set) var editing = false
    @Published private(set) var text = ""
    @Published private(set) var suggestions: [PathSuggestion] = []
    @Published private(set) var highlighted: Int?
    @Published private(set) var error: String?
    @Published private(set) var completionNote: String?
    @Published private(set) var resolving = false
    @Published private(set) var completing = false
    @Published private(set) var focusVersion = 0
    private(set) var selectAllOnFocus = true
    var committed: ((PathResolution, Bool) -> Void)?
    private var base = FileManager.default.homeDirectoryForCurrentUser
    private var home = FileManager.default.homeDirectoryForCurrentUser
    private var hidden = false
    private var generation: UInt64 = 0
    private var completionTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?
    private var completeOnArrival = false
    private let resolvePath: Resolve
    private let completePath: Complete
    init(resolve: @escaping Resolve = { try await PathAddressService.shared.resolve($0, base: $1, home: $2) },
         complete: @escaping Complete = { try await PathAddressService.shared.suggestions($0, base: $1, home: $2, showHidden: $3) }) {
        resolvePath = resolve; completePath = complete
    }
    func begin(text: String, base: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, showHidden: Bool) {
        cancelWork(); self.base = base; self.home = home; hidden = showHidden
        self.text = text; editing = true; error = nil; completionNote = nil
        suggestions = []; highlighted = nil; requestFocus(selectAll: true)
    }
    func requestFocus(selectAll: Bool) { selectAllOnFocus = selectAll; focusVersion &+= 1 }
    func change(_ value: String, composing: Bool = false) {
        guard editing else { return }
        cancelWork(); text = value; error = nil; completionNote = nil; suggestions = []; highlighted = nil
        guard !composing else { return }; scheduleCompletion(delay: true)
    }
    private func scheduleCompletion(delay: Bool) {
        let token = generation, text = text, base = base, home = home, hidden = hidden
        completing = true
        completionTask = Task { [weak self, completePath] in
            do {
                if delay { try await Task.sleep(for: .milliseconds(100)) }
                try Task.checkCancellation()
                let value = try await completePath(text, base, home, hidden)
                guard let self, self.editing, self.generation == token, !Task.isCancelled else { return }
                self.suggestions = value.items; self.highlighted = nil; self.completing = false
                self.completionNote = value.truncated ? "Showing bounded folder matches. A full path always works." : nil
                if self.completeOnArrival { self.completeOnArrival = false; if !value.items.isEmpty { self.acceptCompletion() } }
            } catch {
                guard let self, self.generation == token, self.editing, !Task.isCancelled else { return }
                self.completing = false; self.completeOnArrival = false
                self.completionNote = "No folder suggestions. Press Return to check this path."
            }
        }
    }
    func moveHighlight(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        highlighted = min(suggestions.count - 1, max(0, (highlighted ?? (delta > 0 ? -1 : suggestions.count)) + delta))
    }
    @discardableResult func acceptCompletion(_ index: Int? = nil) -> Bool {
        guard editing else { return false }
        let chosen = index ?? highlighted ?? 0
        guard suggestions.indices.contains(chosen) else {
            if completing { completeOnArrival = true }
            else { completeOnArrival = true; scheduleCompletion(delay: false) }
            return false
        }
        let insertion = suggestions[chosen].insertion
        change(insertion); requestFocus(selectAll: false); return true
    }
    func submit(newTab: Bool = false) {
        guard editing, !resolving else { return }
        if let index = highlighted, suggestions.indices.contains(index) { text = suggestions[index].insertion }
        cancelWork(); suggestions = []; highlighted = nil; error = nil; completionNote = nil; resolving = true
        let token = generation, text = text, base = base, home = home
        resolutionTask = Task { [weak self, resolvePath] in
            do {
                let value = try await resolvePath(text, base, home)
                guard let self, self.editing, token == self.generation, !Task.isCancelled else { return }
                self.resolving = false; self.editing = false; self.committed?(value, newTab)
            } catch {
                guard let self, self.editing, token == self.generation, !Task.isCancelled else { return }
                self.resolving = false; self.error = error.localizedDescription; self.requestFocus(selectAll: false)
            }
        }
    }
    func cancel() { cancelWork(); editing = false; suggestions = []; highlighted = nil; error = nil; completionNote = nil }
    private func cancelWork() {
        generation &+= 1; completionTask?.cancel(); resolutionTask?.cancel()
        completionTask = nil; resolutionTask = nil; completing = false; resolving = false; completeOnArrival = false
    }
    deinit { completionTask?.cancel(); resolutionTask?.cancel() }
}
