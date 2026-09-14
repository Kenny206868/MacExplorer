import Foundation

/// Responsive pane policy. User preferences describe intent; the layout never
/// rewrites them merely because a window becomes narrower.
public struct WorkspaceLayout: Sendable, Equatable {
    public let width: Double
    public let sidebarMinimum: Double
    public let sidebarIdeal: Double
    public let contentMinimum: Double
    public let auxiliaryMinimum: Double
    public let combinesAuxiliaryPanes: Bool
    public let auxiliaryCount: Int
    public var compactToolbar: Bool { width < 1050 }
    public var searchWidth: Double { max(160, min(260, width * 0.23)) }
    public var requiredMinimum: Double {
        sidebarMinimum + contentMinimum + Double(auxiliaryCount) * auxiliaryMinimum + Double(auxiliaryCount + 1)
    }
    public init(width: Double, preview: Bool, inspector: Bool) {
        self.width = width.isFinite ? max(0, width) : 800
        sidebarMinimum = 168
        sidebarIdeal = self.width < 1000 ? 184 : 208
        contentMinimum = 350
        auxiliaryMinimum = 240
        combinesAuxiliaryPanes = preview && inspector && self.width < 1240
        auxiliaryCount = combinesAuxiliaryPanes ? 1 : (preview ? 1 : 0) + (inspector ? 1 : 0)
    }
}
