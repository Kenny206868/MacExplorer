import Foundation

/// Bounded gesture state keyed to the owning pane. A cancelled or malformed
/// gesture cannot leak accumulated magnification into another file browser.
public struct PinchAccumulator: Sendable {
    private var owner: UUID?
    private var accumulated = 0.0
    public init() {}
    public mutating func reset() { owner = nil; accumulated = 0 }
    public mutating func consume(_ delta: Double, owner: UUID, began: Bool = false, ended: Bool = false, cancelled: Bool = false) -> Int {
        guard delta.isFinite, !cancelled else { reset(); return 0 }
        if self.owner != owner || began { accumulated = 0; self.owner = owner }
        accumulated += min(1, max(-1, delta))
        let direction = abs(accumulated) >= 0.18 ? (accumulated > 0 ? 1 : -1) : 0
        if direction != 0 { accumulated = 0 }
        if ended { reset() }
        return direction
    }
}
