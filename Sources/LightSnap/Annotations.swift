import AppKit

enum Tool: Int, CaseIterable {
    case select
    case pen
    case line
    case arrow
    case rect
    case highlight
    case text

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        }
    }

    var help: String {
        switch self {
        case .select: return "Select / move"
        case .pen: return "Pen"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rect: return "Rectangle"
        case .highlight: return "Marker"
        case .text: return "Text"
        }
    }
}

struct Annotation {
    enum Shape {
        case pen([CGPoint])
        case line(from: CGPoint, to: CGPoint)
        case arrow(from: CGPoint, to: CGPoint)
        case rect(CGRect)
        case highlight([CGPoint])
        case text(String, origin: CGPoint, fontSize: CGFloat)
    }

    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat
}

/// Draws annotations into the current NSGraphicsContext. Coordinates are view
/// points with a flipped (top-left origin) coordinate system, both for the
/// live overlay and for the exported bitmap.
enum AnnotationRenderer {
    static func draw(_ annotations: [Annotation]) {
        for annotation in annotations {
            draw(annotation)
        }
    }

    static func draw(_ annotation: Annotation) {
        switch annotation.shape {
        case .pen(let points):
            strokePath(points: points, width: annotation.lineWidth, color: annotation.color)

        case .line(let from, let to):
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round
            annotation.color.setStroke()
            path.stroke()

        case .arrow(let from, let to):
            drawArrow(from: from, to: to, width: annotation.lineWidth, color: annotation.color)

        case .rect(let rect):
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            path.lineJoinStyle = .round
            annotation.color.setStroke()
            path.stroke()

        case .highlight(let points):
            guard let context = NSGraphicsContext.current else { return }
            context.saveGraphicsState()
            context.cgContext.setBlendMode(.multiply)
            strokePath(
                points: points,
                width: max(annotation.lineWidth * 5, 16),
                color: annotation.color.withAlphaComponent(0.5)
            )
            context.restoreGraphicsState()

        case .text(let string, let origin, let fontSize):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: annotation.color,
            ]
            NSAttributedString(string: string, attributes: attributes).draw(at: origin)
        }
    }

    private static func strokePath(points: [CGPoint], width: CGFloat, color: NSColor) {
        guard let first = points.first else { return }

        if points.count == 1 {
            let radius = width / 2
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: first.x - radius, y: first.y - radius, width: width, height: width)).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        if points.count == 2 {
            path.line(to: points[1])
        } else {
            // Midpoint smoothing keeps freehand strokes from looking jagged.
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.curve(to: mid, controlPoint1: current, controlPoint2: current)
            }
            if let last = points.last {
                path.line(to: last)
            }
        }
        color.setStroke()
        path.stroke()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, color: NSColor) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard dx != 0 || dy != 0 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(width * 4, 14)
        let headAngle = CGFloat.pi / 7

        let shaftEnd = CGPoint(
            x: to.x - cos(angle) * headLength * 0.55,
            y: to.y - sin(angle) * headLength * 0.55
        )
        let shaft = NSBezierPath()
        shaft.move(to: from)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        color.setStroke()
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: to)
        head.line(to: CGPoint(
            x: to.x - cos(angle - headAngle) * headLength,
            y: to.y - sin(angle - headAngle) * headLength
        ))
        head.line(to: CGPoint(
            x: to.x - cos(angle + headAngle) * headLength,
            y: to.y - sin(angle + headAngle) * headLength
        ))
        head.close()
        color.setFill()
        head.fill()
    }
}
