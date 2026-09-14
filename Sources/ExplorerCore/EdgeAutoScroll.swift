import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Time-based edge scrolling; independent of display refresh rate and view lifetime.
public enum EdgeAutoScroll {
    public static func delta(pointer: CGPoint, viewport: CGSize, elapsed: TimeInterval,
                             edge: CGFloat = 36, maximumSpeed: CGFloat = 900) -> CGPoint {
        guard pointer.x.isFinite, pointer.y.isFinite, viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0, elapsed.isFinite, elapsed > 0,
              edge.isFinite, edge > 0, maximumSpeed.isFinite, maximumSpeed > 0 else { return .zero }
        let time = CGFloat(min(elapsed, 1.0 / 15.0))
        func axis(_ value: CGFloat, length: CGFloat) -> CGFloat {
            let band = min(edge, length / 2)
            let distance: CGFloat
            if value < band { distance = -min(1, (band - value) / band) }
            else if value > length - band { distance = min(1, (value - length + band) / band) }
            else { return 0 }
            return (distance < 0 ? -1 : 1) * distance * distance * maximumSpeed * time
        }
        return CGPoint(x: axis(pointer.x, length: viewport.width), y: axis(pointer.y, length: viewport.height))
    }
    public static func clampedOrigin(_ origin: CGPoint, content: CGSize, viewport: CGSize) -> CGPoint {
        guard origin.x.isFinite, origin.y.isFinite, content.width.isFinite, content.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite else { return .zero }
        return CGPoint(x: min(max(0, origin.x), max(0, content.width - max(0, viewport.width))),
                       y: min(max(0, origin.y), max(0, content.height - max(0, viewport.height))))
    }
}
