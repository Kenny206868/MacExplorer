import Foundation

/// Shared geometry contract, independent of SwiftUI and filesystem state.
/// Desktop density never reduces the explicit touch target below 44 points.
public struct WorkspaceChromeLayout: Equatable, Sendable {
    public let width: Double
    public let touch: Bool
    public init(width: Double, touch: Bool = false) {
        self.width = width.isFinite ? max(0, width) : 0
        self.touch = touch
    }
    public var footerHeight: Double { touch ? 52 : 38 }
    public var paneStatusHeight: Double { touch ? 44 : 26 }
    public var compactActions: Bool { width < 1180 }
    public var iconOnlyActions: Bool { touch && width < 1180 }
    public var showsDestination: Bool { width >= (touch ? 1280 : 1000) }
    // Leave room for traffic lights, native title/navigation and trailing tools.
    // The system toolbar still owns overflow and user customization.
    public var titlebarWidth: Double { min(900, max(touch ? 224 : 180, width - 760)) }
    public var titlebarHeight: Double { touch ? 48 : 32 }
    public var titlebarShowsLocations: Bool { titlebarWidth >= 320 }
    public var titlebarShowsCompare: Bool { titlebarWidth >= 600 }
}
