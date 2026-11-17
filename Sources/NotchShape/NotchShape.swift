import SwiftUI

/// The shape of a Mac notch that opens: square along the top, where it meets the edge of the screen, with
/// rounded bottom corners like the notch's own. When it's open, its top corners flare outward in a curve into
/// the screen's edge, as the notch's do, so it looks grown out of the notch rather than stuck under it. The
/// flare is drawn outside the rectangle, either side, so leave room for it.
///
/// Both the corner radius and the flare animate, so the shape can grow out of the notch and fold back:
///
///     NotchShape(bottomRadius: open ? 26 : 10, flare: open ? 14 : 0)
///         .fill(.black)
///         .frame(width: open ? 480 : 185, height: open ? 180 : 32)
///         .animation(.spring(response: 0.45, dampingFraction: 0.8), value: open)
///
/// This is the shape Notchlight's Dynamic Island, Light and Tray are drawn with.
public struct NotchShape: Shape {
    public var bottomRadius: CGFloat
    public var flare: CGFloat

    public init(bottomRadius: CGFloat, flare: CGFloat = 0) {
        self.bottomRadius = bottomRadius
        self.flare = flare
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, flare) }
        set {
            bottomRadius = newValue.first
            flare = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))
        let f = max(0, min(flare, rect.height - r))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
