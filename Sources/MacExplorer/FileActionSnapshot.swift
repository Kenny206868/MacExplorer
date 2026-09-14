import Foundation
import ExplorerCore

/// The action sheet may be dismissed before macOS presents its successor. Never
/// re-read a newly selected file or a newly active tab after that transition.
@MainActor struct FileActionSnapshot {
    private weak var workspace: ExplorerWorkspace?
    private let tabID: UUID
    private let location: Location
    private let selection: Set<URL>
    private let fingerprints: [(URL, FileFingerprint)]
    private let otherDestination: URL?
    init(_ workspace: ExplorerWorkspace) throws {
        guard !workspace.selectedURLs.isEmpty else { throw ExplorerError.message("No files are selected.") }
        self.workspace = workspace; tabID = workspace.current.id; location = workspace.current.location
        selection = workspace.current.selection
        fingerprints = try workspace.selectedURLs.map { ($0, try FileFingerprint($0)) }
        otherDestination = workspace.paneController?.other(than: workspace)?.destination
    }
    func validate() throws {
        guard let workspace, workspace.current.id == tabID, workspace.current.location == location,
              workspace.current.selection == selection, workspace.sheet == nil, workspace.conflict == nil,
              workspace.message == nil,
              workspace.paneController?.other(than: workspace)?.destination == otherDestination,
              fingerprints.allSatisfy({ $0.1.matches($0.0) }) else {
            throw ExplorerError.message("The selection, tab, destination or file changed while the actions sheet was closing. Choose the action again for the current files.")
        }
    }
}
