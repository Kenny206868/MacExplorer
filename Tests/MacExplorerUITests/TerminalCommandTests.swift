import XCTest
import ExplorerCore
@testable import MacExplorer

final class TerminalCommandTests: XCTestCase {
    @MainActor func testPaletteRevalidatesBothCapturedPaneLocations() throws {
        let left = URL(fileURLWithPath: "/tmp/left"), right = URL(fileURLWithPath: "/tmp/right")
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(left)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.dualPane = DualPaneController(primary: owner)
        let other = try XCTUnwrap(owner.dualPane?.secondary)
        other.current.history = NavigationHistory(.folder(right))
        defer { owner.tabs.forEach { $0.stop() }; other.tabs.forEach { $0.stop() } }
        let invocation = try CommandInvocation(.terminalBoth, workspace: owner)
        XCTAssertNoThrow(try invocation.validate())
        other.current.history = NavigationHistory(.folder(URL(fileURLWithPath: "/tmp/changed")))
        XCTAssertThrowsError(try invocation.validate(), "Palette dismissal cannot silently choose a different opposite working directory")
        other.current.history = NavigationHistory(.network)
        XCTAssertNotNil(ExplorerCommand.terminalBoth.unavailable(in: owner))
        XCTAssertNotNil(ExplorerCommand.terminalOther.unavailable(in: owner))
        XCTAssertNil(ExplorerCommand.terminal.unavailable(in: owner))
        let model = CommandPaletteModel(query: "terminal")
        XCTAssertTrue(Set([ExplorerCommand.terminal, .terminalOther, .terminalBoth]).isSubset(of: Set(model.matches)))
    }
}
