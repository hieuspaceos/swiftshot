import Cocoa
import CoreGraphics

// MARK: - Screen model

/// A captured screen bitmap. `cgImage` is at native pixel resolution;
/// `scale` = pixels per screen point; `frame` is the NSScreen-style frame
/// (bottom-left origin global screen coordinates).
struct ScreenShot {
    let image: CGImage
    let scale: CGFloat
    let frame: CGRect
}

// MARK: - Coordinate helpers

/// NSScreen frames use a bottom-left origin; CGWindowList / SCDisplay use
/// top-left origin anchored at the top-left corner of the primary display.
func cgScreenRect(for screen: NSScreen) -> CGRect {
    let f = screen.frame
    let primaryHeight = NSScreen.screens.first?.frame.height ?? f.maxY
    return CGRect(x: f.origin.x,
                  y: primaryHeight - f.maxY,
                  width: f.width,
                  height: f.height)
}

func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        ?? CGMainDisplayID()
}

// MARK: - Drawing model

enum EditorTool: Int, CaseIterable {
    case pen, arrow, rect, ellipse, highlight, mosaic, text

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .rect: return "Rect"
        case .ellipse: return "Ellipse"
        case .highlight: return "HL"
        case .mosaic: return "Mosaic"
        case .text: return "Text"
        }
    }
}

/// One committed annotation. All coordinates are in "canvas points":
/// the top-left-origin space matching the captured image's point size
/// (pixelSize / scale).
struct Drawable {
    var color: NSColor
    var lineWidth: CGFloat
    var kind: ShapeKind

    enum ShapeKind {
        case freehand([CGPoint])
        case line(start: CGPoint, end: CGPoint, arrowHead: Bool)
        case rect(CGRect)
        case ellipse(CGRect)
        case highlight(CGRect)
        case mosaic(rect: CGRect, image: CGImage) // image already pixelated at scale
        case text(origin: CGPoint, string: NSAttributedString)
    }

    func draw(in ctx: CGContext) {
        switch kind {
        case .freehand(let points):
            guard points.count > 1 else { return }
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: points[0])
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
            ctx.restoreGState()

        case .line(let start, let end, let arrowHead):
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            if arrowHead { drawArrowHead(from: start, to: end, in: ctx) }
            ctx.restoreGState()

        case .rect(let r):
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineJoin(.miter)
            ctx.stroke(r)
            ctx.restoreGState()

        case .ellipse(let r):
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: r)
            ctx.restoreGState()

        case .highlight(let r):
            ctx.saveGState()
            ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
            ctx.fill(r)
            ctx.restoreGState()

        case .mosaic(let rect, let image):
            ctx.saveGState()
            ctx.interpolationQuality = .none
            drawImageUpright(image, in: rect, ctx: ctx)
            ctx.restoreGState()

        case .text(let origin, let string):
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: 1, y: -1)
            string.draw(at: .zero)
            ctx.restoreGState()
        }
    }

    private func drawArrowHead(from a: CGPoint, to b: CGPoint, in ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return }
        let ux = dx / len, uy = dy / len
        let hl = max(10, lineWidth * 4)
        let angle = CGFloat.pi / 7
        let c = cos(angle), s = sin(angle)
        func arm(_ sgn: CGFloat) -> CGPoint {
            let vx = ux * c - sgn * uy * s
            let vy = sgn * ux * s + uy * c
            return CGPoint(x: b.x - vx * hl, y: b.y - vy * hl)
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: b); ctx.addLine(to: arm(1))
        ctx.move(to: b); ctx.addLine(to: arm(-1))
        ctx.strokePath()
    }
}

/// Draw a CGImage upright into `rect` when `ctx` is in a top-left-origin
/// (flipped) coordinate space.
func drawImageUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

// MARK: - Image helpers

/// Pixelate `region` (canvas points, top-left origin) of the base image.
/// `scale` = pixels per canvas point.
func pixelateRegion(_ region: CGRect, of image: CGImage, scale: CGFloat) -> CGImage? {
    let px = CGRect(x: region.minX * scale, y: region.minY * scale,
                    width: region.width * scale, height: region.height * scale).integral
    guard let crop = image.cropping(to: px) else { return nil }
    let w = max(1, Int(region.width)), h = max(1, Int(region.height))
    let smallW = max(1, w / 14), smallH = max(1, h / 14)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let small = CGContext(data: nil, width: smallW, height: smallH,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    small.interpolationQuality = .low
    small.draw(crop, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
    guard let smallImg = small.makeImage() else { return nil }
    guard let big = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    big.interpolationQuality = .none
    big.draw(smallImg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return big.makeImage()
}

/// Cut a region out of multi-screen captures into a single image.
/// `region` is in NSScreen-space (bottom-left origin). `shots[i].scale`
/// gives pixels per point for that screen.
func cropRegion(_ region: CGRect, from shots: [ScreenShot]) -> (CGImage, CGFloat)? {
    // Fast path: region fully inside one shot — crop that CGImage directly
    // instead of compositing into a fresh bitmap.
    if let shot = shots.first(where: { $0.frame.contains(region) }) {
        let s = shot.scale
        let src = CGRect(x: (region.minX - shot.frame.minX) * s,
                         y: (shot.frame.maxY - region.maxY) * s,
                         width: region.width * s, height: region.height * s).integral
        if let sub = shot.image.cropping(to: src) { return (sub, s) }
    }

    let maxAreaScreen = NSScreen.screens.max { s1, s2 in
        s1.frame.intersection(region).width * s1.frame.intersection(region).height
            < s2.frame.intersection(region).width * s2.frame.intersection(region).height
    } ?? NSScreen.main
    let scale = shots.first(where: { $0.frame == maxAreaScreen?.frame })?.scale
        ?? maxAreaScreen?.backingScaleFactor ?? 2.0
    let w = Int((region.width * scale).rounded())
    let h = Int((region.height * scale).rounded())
    guard w > 0, h > 0 else { return nil }
    guard let ctx = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    for shot in shots {
        let inter = shot.frame.intersection(region)
        if inter.isEmpty { continue }
        let s = shot.scale
        // Crop rect in the image's pixel space (top-left origin):
        // image top corresponds to shot.frame.maxY.
        let src = CGRect(x: (inter.minX - shot.frame.minX) * s,
                         y: (shot.frame.maxY - inter.maxY) * s,
                         width: inter.width * s, height: inter.height * s).integral
        guard let sub = shot.image.cropping(to: src) else { continue }
        // Destination in the output ctx (pixel space, bottom-left origin):
        // region.minY maps to y=0.
        let dest = CGRect(x: (inter.minX - region.minX) * scale,
                          y: (inter.minY - region.minY) * scale,
                          width: inter.width * scale, height: inter.height * scale)
        ctx.draw(sub, in: dest)
    }
    guard let out = ctx.makeImage() else { return nil }
    return (out, scale)
}

func defaultSaveDirectory() -> URL {
    if let s = UserDefaults.standard.string(forKey: "saveDirectory"), !s.isEmpty {
        return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/SwiftShot")
}

func defaultFileName(ext: String) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "SwiftShot \(fmt.string(from: Date())).\(ext)"
}
