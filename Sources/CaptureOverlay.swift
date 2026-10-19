import Cocoa

/// Fullscreen borderless overlay covering every connected display.
/// Draws the captured screen dimmed; user rubber-bands a region.
/// ESC cancels; a plain click cancels; drag-release commits immediately
/// (in NSScreen bottom-left coords).
final class CaptureOverlayWindow: NSWindow {

    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let overlayView = OverlayContentView()
    private var finished = false

    private init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        overlayView.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: overlayView))
        overlayView.onCommit = { [weak self] r in self?.commit(r) }
        overlayView.onCancel = { [weak self] in self?.cancel() }
        self.contentView = overlayView
    }

    /// Rebuild the single shared overlay window only when the union of all
    /// screens changed; otherwise just swap the captured images back in.
    /// The window is hidden (orderOut) between captures, never dealloc'd.
    /// `frame` is the union of every screen's frame — supplied by the
    /// caller because `shots` may start with just the cursor's screen and
    /// be patched in lazily via `updateShots`.
    static func shared(frame: CGRect, shots: [ScreenShot]) -> CaptureOverlayWindow {
        if let existing = _shared {
            existing.configure(frame: frame, shots: shots)
            return existing
        }
        let window = CaptureOverlayWindow()
        _shared = window
        window.configure(frame: frame, shots: shots)
        return window
    }
    private static var _shared: CaptureOverlayWindow?

    /// Shots currently installed on the overlay — grows as async captures
    /// land; the commit handler crops from this, not a stale snapshot.
    var currentShots: [ScreenShot] { overlayView.shots }

    /// Swap in additional captures once they arrive (lazy per-screen
    /// capture). Invalidates the dimmed backdrop cache so the next draw
    /// recomposites every screen.
    func updateShots(_ shots: [ScreenShot]) {
        overlayView.shots = shots
        overlayView.needsDisplay = true
    }

    private func configure(frame: CGRect, shots: [ScreenShot]) {
        if self.frame != frame { setFrame(frame, display: false) }
        finished = false
        overlayView.shots = shots
        overlayView.unionOrigin = frame.origin
        overlayView.frame = NSRect(origin: .zero, size: frame.size)
        overlayView.resetSession()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(overlayView)
        NSCursor.crosshair.set()
    }

    private func commit(_ rect: CGRect) {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        onCommit?(rect)
        overlayView.releaseCaptureMemory()
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        orderOut(nil)
        onCancel?()
        overlayView.releaseCaptureMemory()
    }
}


final class OverlayContentView: NSView {

    var shots: [ScreenShot] = [] { didSet { backdropCache = nil } }
    var unionOrigin: CGPoint = .zero
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?   // view coords (bottom-left)
    private var dragCurrent: CGPoint?

    /// Fresh session state for window reuse (clears an ESC'd mid-drag).
    func resetSession() {
        dragStart = nil
        dragCurrent = nil
        redrawPending = false
        needsDisplay = true
    }

    /// Called after commit/cancel: drop the composited backdrop and every
    /// shot's decoded bitmap — PNG bytes stay, so nothing is lost.
    func releaseCaptureMemory() {
        backdropCache = nil
        for shot in shots { shot.releaseDecodedImage() }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Flip to top-left space for image drawing.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        // Draw the pre-composited dimmed backdrop instead of re-drawing
        // every screen's full-res CGImage + dim fill on each mouseMoved.
        if let backdrop = backdropImage() {
            drawImageUpright(backdrop, in: bounds, ctx: ctx)
        }

        // Selection rect in the flipped (top-left) space.
        let selBL = currentDragRect()
        let sel: CGRect? = selBL.map {
            CGRect(x: $0.minX, y: bounds.height - $0.maxY,
                   width: $0.width, height: $0.height)
        }

        if let sel, sel.width > 1, sel.height > 1 {
            // Punch an undimmed hole by re-drawing underlying pixels.
            ctx.saveGState()
            ctx.clip(to: sel)
            for shot in shots {
                drawImageUpright(shot.image, in: viewRect(forScreenFrame: shot.frame), ctx: ctx)
            }
            ctx.restoreGState()

            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(sel.insetBy(dx: 0.5, dy: 0.5))

            // `sel` is top-left space; the pill goes just above the selection.
            let label = "\(Int(sel.width)) × \(Int(sel.height))"
            drawPill(label as NSString, nearTopLeft: sel, ctx: ctx)
        } else {
            // No selection yet: crosshair guides + position + hint banner.
            let mBL = mouseViewLocation()
            let m = CGPoint(x: mBL.x, y: bounds.height - mBL.y) // top-left space
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(0.5)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: 0, y: m.y)); ctx.addLine(to: CGPoint(x: bounds.width, y: m.y))
            ctx.move(to: CGPoint(x: m.x, y: 0)); ctx.addLine(to: CGPoint(x: m.x, y: bounds.height))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])

            let pos = "\(Int(m.x)) , \(Int(m.y))"
            drawPill(pos as NSString,
                     atTopLeft: CGPoint(x: min(m.x + 14, bounds.width - 90),
                                        y: min(m.y + 14, bounds.height - 30)),
                     ctx: ctx)

            drawPill("Drag to select a region · ESC to cancel" as NSString,
                     atTopLeft: CGPoint(x: (bounds.width - 300) / 2, y: 40),
                     ctx: ctx, fixedSize: CGSize(width: 300, height: 30), centered: true)
        }
    }

    /// All screens composited once at HALF backing-pixel resolution with
    /// the dim fill baked in — the dimmed backdrop is never inspected 1:1,
    /// so this roughly quarters the offscreen's footprint (~11 MB vs ~23 MB
    /// on a Retina union). Invalidated when `shots` changes or `bounds` resizes.
    private var backdropCache: CGImage?
    private var backdropBounds: CGRect = .zero

    private func backdropImage() -> CGImage? {
        if let img = backdropCache, backdropBounds == bounds { return img }
        let scale = (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) / 2
        let w = max(1, Int((bounds.width * scale).rounded()))
        let h = max(1, Int((bounds.height * scale).rounded()))
        guard let offscreen = CGContext(data: nil, width: w, height: h,
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return shots.first?.image }
        offscreen.scaleBy(x: scale, y: scale)
        for shot in shots {
            drawImageUpright(shot.image, in: viewRect(forScreenFrame: shot.frame), ctx: offscreen)
        }
        offscreen.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        offscreen.fill(bounds)
        guard let img = offscreen.makeImage() else { return nil }
        backdropCache = img
        backdropBounds = bounds
        return img
    }

    /// Mouse position in view coords (bottom-left origin).
    private func mouseViewLocation() -> CGPoint {
        convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }

    /// Dark rounded label drawn in the flipped (top-left) coordinate space.
    /// `nearTopLeft` places the pill just above the rect, or below when `below`.
    private func drawPill(_ label: NSString, nearTopLeft sel: CGRect? = nil,
                          atTopLeft point: CGPoint = .zero, ctx: CGContext,
                          below: Bool = false, fixedSize: CGSize = .zero,
                          centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let ts = label.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let size = fixedSize == .zero ? CGSize(width: ts.width + pad * 2, height: ts.height + pad)
                                      : fixedSize
        var lx: CGFloat; var ly: CGFloat
        if let sel {
            lx = min(max(sel.minX, 4), bounds.width - size.width - 4)
            ly = below ? sel.maxY + 8 : sel.minY - size.height - 8
            if ly < 4 { ly = sel.maxY + 8 }
        } else {
            lx = point.x; ly = point.y
        }
        let rect = CGRect(x: lx, y: ly, width: size.width, height: size.height)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        let tx = centered ? lx + (size.width - ts.width) / 2 : lx + pad
        ctx.translateBy(x: tx, y: ly + (size.height + ts.height) / 2 - 4)
        ctx.scaleBy(x: 1, y: -1)
        label.draw(at: .zero, withAttributes: attrs)
        ctx.restoreGState()
    }



    /// Coalesce redraw requests to ~1 per frame instead of one per event.
    private var redrawPending = false
    private func scheduleRedraw() {
        guard !redrawPending else { return }
        redrawPending = true
        DispatchQueue.main.async { [weak self] in
            self?.redrawPending = false
            self?.needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        scheduleRedraw()
    }

    private func currentDragRect() -> CGRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(c.x - s.x), height: abs(c.y - s.y))
    }
    /// Convert a global screen frame (bottom-left origin) into the flipped
    /// top-left coordinate space used inside draw(_:).
    private func viewRect(forScreenFrame f: CGRect) -> CGRect {
        CGRect(x: f.minX - unionOrigin.x,
               y: bounds.height - (f.maxY - unionOrigin.y),
               width: f.width, height: f.height)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p
        dragCurrent = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        scheduleRedraw()
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragCurrent = p
        let sel = currentDragRect()
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
        if let sel, sel.width >= 4, sel.height >= 4 {
            finish(sel)
        } else {
            // Plain click with no drag cancels.
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func finish(_ viewRect: CGRect) {
        let global = CGRect(x: viewRect.minX + unionOrigin.x,
                            y: viewRect.minY + unionOrigin.y,
                            width: viewRect.width, height: viewRect.height)
        onCommit?(global)
    }
}
