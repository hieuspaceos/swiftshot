import Cocoa
import UniformTypeIdentifiers

/// Editor window: annotation canvas in a scroll view plus a toolbar.
/// All shape coordinates are in canvas points (top-left origin),
/// where canvas point size = pixelSize / shot.scale.
final class EditorWindow: NSWindow, NSWindowDelegate {

    let shot: ScreenShot
    /// Called on Copy/Save (with rendered image) and on Cancel (nil).
    var onFinish: ((CGImage?) -> Void)?

    private let canvasView: EditorCanvasView
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var finished = false

    static let palette: [NSColor] = [
        .systemRed, .systemYellow, .systemGreen, .systemBlue,
        .systemPurple, .white, .black
    ]

    init(shot: ScreenShot) {
        self.shot = shot
        let canvasSize = NSSize(width: CGFloat(shot.image.width) / shot.scale,
                                height: CGFloat(shot.image.height) / shot.scale)
        canvasView = EditorCanvasView(shot: shot)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let toolbarH: CGFloat = 46
        let maxW = screen.width - 60, maxH = screen.height - toolbarH - 60
        let winW = min(max(canvasSize.width + 2, 720), maxW)
        let winH = min(canvasSize.height + 2 + toolbarH, maxH + toolbarH)
        let origin = NSPoint(x: screen.midX - winW / 2, y: screen.midY - winH / 2)

        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered,
                   defer: false)
        self.title = "SwiftShot — \(Int(canvasSize.width))×\(Int(canvasSize.height))"
        self.minSize = NSSize(width: 480, height: 320)
        self.isReleasedWhenClosed = false
        self.delegate = self

        buildToolbar(in: self.contentView!, canvasSize: canvasSize)

        canvasView.onCancel = { [weak self] in self?.finish(nil) }
        canvasView.needsDisplay = true
    }

    // MARK: - Toolbar

    private func buildToolbar(in contentView: NSView, canvasSize: NSSize) {
        let toolbar = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 46,
                                           width: contentView.bounds.width, height: 46))
        toolbar.autoresizingMask = [.width, .minYMargin]

        var x: CGFloat = 10

        // Action buttons first, at the left edge — always visible even
        // when the capture is narrower than the rest of the toolbar.
        for (title, action) in [("Copy", #selector(copyClicked)),
                                ("Save…", #selector(saveClicked)),
                                ("Cancel", #selector(cancelClicked))] as [(String, Selector)] {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.frame = NSRect(x: x, y: 8, width: 66, height: 30)
            b.autoresizingMask = [.maxYMargin]
            toolbar.addSubview(b)
            x += 72
        }
        x += 10

        for tool in EditorTool.allCases {
            let b = NSButton(title: tool.title, target: self, action: #selector(toolClicked(_:)))
            b.setButtonType(.onOff)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: 11)
            b.tag = tool.rawValue
            b.frame = NSRect(x: x, y: 8, width: 58, height: 30)
            b.autoresizingMask = [.maxYMargin]
            toolbar.addSubview(b)
            toolButtons.append(b)
            x += 62
        }
        toolButtons[0].state = .on // Pen default

        x += 12
        for color in EditorWindow.palette {
            let b = NSButton(frame: NSRect(x: x, y: 14, width: 20, height: 20))
            b.wantsLayer = true
            b.layer?.backgroundColor = color.cgColor
            b.layer?.cornerRadius = 10
            b.layer?.borderWidth = 0
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.title = ""
            b.target = self
            b.action = #selector(colorClicked(_:))
            b.identifier = NSUserInterfaceItemIdentifier("\(EditorWindow.palette.firstIndex(of: color)!)")
            toolbar.addSubview(b)
            colorButtons.append(b)
            x += 26
        }
        updateColorSelection()

        x += 10
        let slider = NSSlider(value: 3, minValue: 1, maxValue: 14,
                              target: self, action: #selector(widthChanged(_:)))
        slider.frame = NSRect(x: x, y: 13, width: 90, height: 20)
        slider.autoresizingMask = [.maxYMargin]
        toolbar.addSubview(slider)
        x += 102

        let undo = NSButton(title: "Undo", target: self, action: #selector(undoClicked))
        undo.bezelStyle = .rounded
        undo.controlSize = .small
        undo.frame = NSRect(x: x, y: 8, width: 50, height: 30)
        undo.autoresizingMask = [.maxYMargin]
        toolbar.addSubview(undo)
        x += 58

        contentView.addSubview(toolbar)

        // Canvas inside scroll view below the toolbar.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0,
                                                width: contentView.bounds.width,
                                                height: contentView.bounds.height - 46))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.12, alpha: 1)
        canvasView.frame = NSRect(origin: .zero, size: canvasSize)
        scroll.documentView = canvasView
        contentView.addSubview(scroll, positioned: .below, relativeTo: toolbar)
    }

    private func updateColorSelection() {
        for (i, b) in colorButtons.enumerated() {
            let selected = canvasView.currentColor == EditorWindow.palette[i]
            b.layer?.borderWidth = selected ? 2.5 : 1
            b.layer?.borderColor = selected
                ? NSColor.white.cgColor
                : NSColor.black.withAlphaComponent(0.4).cgColor
        }
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        canvasView.currentTool = EditorTool(rawValue: sender.tag) ?? .pen
        for b in toolButtons { b.state = (b == sender) ? .on : .off }
    }

    @objc private func colorClicked(_ sender: NSButton) {
        let i = Int(sender.identifier?.rawValue ?? "0") ?? 0
        canvasView.currentColor = EditorWindow.palette[min(max(i, 0), EditorWindow.palette.count - 1)]
        updateColorSelection()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvasView.currentLineWidth = CGFloat(sender.doubleValue)
    }

    @objc private func undoClicked() {
        canvasView.undo()
    }

    @objc private func cancelClicked() {
        finish(nil)
    }

    @objc private func copyClicked() {
        guard let image = canvasView.renderFinal() else { return }
        EditorWindow.copyToPasteboard(image)
        finish(image)
    }

    /// Writes a PNG representation to the general pasteboard. TIFF is
    /// promised lazily via a provider instead of being encoded eagerly —
    /// the uncompressed TIFF of a full capture was the largest single
    /// contributor to the editor's ~390 MB peak.
    static func copyToPasteboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        item.setDataProvider(PasteboardTIFFProvider(image: image), forTypes: [.tiff])
        pb.writeObjects([item])
    }

    @objc private func saveClicked() {
        guard let image = canvasView.renderFinal() else { return }
        let dir = defaultSaveDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.directoryURL = dir
        panel.nameFieldStringValue = defaultFileName(ext: "png")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.write(image, to: url)
            self?.finish(image)
        }
    }

    private func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        let isJPEG = url.pathExtension.lowercased() == "jpg"
            || url.pathExtension.lowercased() == "jpeg"
        let type: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
        let props: [NSBitmapImageRep.PropertyKey: Any] =
            isJPEG ? [.compressionFactor: 0.92] : [:]
        if let data = rep.representation(using: type, properties: props) {
            try? data.write(to: url)
        }
    }

    private func finish(_ image: CGImage?) {
        guard !finished else { return }
        finished = true
        onFinish?(image)
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !finished {
            finished = true
            onFinish?(nil)
        }
        return true
    }
}

/// Encodes TIFF only when a paste target actually requests it.
private final class PasteboardTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    private let image: CGImage

    init(image: CGImage) { self.image = image }

    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff,
              let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation
        else { return }
        item.setData(tiff, forType: .tiff)
    }
}

// MARK: - Canvas

final class EditorCanvasView: NSView, NSTextFieldDelegate {

    let shot: ScreenShot
    var shapes: [Drawable] = []
    var currentTool: EditorTool = .pen
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var currentPen: [CGPoint]?
    private var draftRect: CGRect?
    private var textField: NSTextField?

    init(shot: ScreenShot) {
        self.shot = shot
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Undo is `popLast` on `shapes`; cap the stack so long sessions can't
    /// grow unbounded. `.mosaic` is the only Drawable that embeds a
    /// full-scale CGImage, so those are bounded separately at 5 — a
    /// 20-deep stack of mosaic bitmaps could retain ~400 MB worst case.
    private let maxUndoableShapes = 20
    private let maxMosaicShapes = 5

    private func pushShape(_ shape: Drawable) {
        shapes.append(shape)
        if shapes.count > maxUndoableShapes {
            shapes.removeFirst(shapes.count - maxUndoableShapes)
        }
        let mosaics = shapes.reduce(0) { $0 + ($1.isMosaic ? 1 : 0) }
        if mosaics > maxMosaicShapes {
            var toRemove = mosaics - maxMosaicShapes
            shapes.removeAll {
                guard toRemove > 0, $0.isMosaic else { return false }
                toRemove -= 1 // drops the OLDEST mosaic entries first
                return true
            }
        }
    }

    /// canvas-space point (top-left origin) for an event location.
    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Flip to top-left canvas space for the remainder of drawing.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        drawImageUpright(shot.image, in: bounds, ctx: ctx)

        for shape in shapes { shape.draw(in: ctx) }

        // Draft previews.
        if let pts = currentPen, pts.count > 1 {
            ctx.saveGState()
            ctx.setStrokeColor(currentColor.cgColor)
            ctx.setLineWidth(currentLineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: pts[0])
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if let r = draftRect {
            let draft = Drawable(color: currentColor, lineWidth: currentLineWidth,
                                 kind: draftKind(rect: r))
            draft.draw(in: ctx)
        }
    }

    private func draftKind(rect: CGRect) -> Drawable.ShapeKind {
        guard let s = dragStart else { return .rect(rect) }
        let end = CGPoint(x: rect.maxX, y: rect.maxY)
        switch currentTool {
        case .arrow: return .line(start: s, end: end, arrowHead: true)
        case .rect: return .rect(rect)
        case .ellipse: return .ellipse(rect)
        case .highlight: return .highlight(rect)
        case .mosaic: return .rect(rect) // outline only while dragging
        default: return .rect(rect)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if textField != nil {
            commitTextField()
            return
        }
        let p = canvasPoint(event)
        if currentTool == .text {
            startTextField(at: p)
            return
        }
        dragStart = p
        if currentTool == .pen {
            currentPen = [p]
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = canvasPoint(event)
        if currentTool == .pen {
            currentPen?.append(p)
        } else if let s = dragStart {
            draftRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                               width: abs(p.x - s.x), height: abs(p.y - s.y))
        }
        autoscroll(with: event)
        // Invalidate only the dirty region: draft rect union, or the last
        // pen segment bounding box inflated by line width.
        let pad = currentLineWidth + 8
        if currentTool == .pen, let pts = currentPen, pts.count > 1 {
            let last = pts.suffix(2)
            let r = CGRect(x: min(last.first!.x, last.last!.x) - pad,
                           y: min(last.first!.y, last.last!.y) - pad,
                           width: abs(last.last!.x - last.first!.x) + pad * 2,
                           height: abs(last.last!.y - last.first!.y) + pad * 2)
            let vr = CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
            setNeedsDisplay(vr)
        } else {
            setNeedsDisplay(bounds) // draft shapes need full redraw (translucent overlay)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = canvasPoint(event)
        defer {
            dragStart = nil
            draftRect = nil
            needsDisplay = true
        }
        guard let s = dragStart else { currentPen = nil; return }

        switch currentTool {
        case .pen:
            if let pts = currentPen, pts.count > 1 {
                pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth,
                                   kind: .freehand(pts)))
            }
            currentPen = nil

        case .arrow:
            guard s != p else { break }
            pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth,
                               kind: .line(start: s, end: p, arrowHead: true)))

        case .rect, .ellipse, .highlight, .mosaic:
            let r = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                           width: abs(p.x - s.x), height: abs(p.y - s.y))
            guard r.width > 3, r.height > 3 else { break }
            switch currentTool {
            case .rect:
                pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth, kind: .rect(r)))
            case .ellipse:
                pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth, kind: .ellipse(r)))
            case .highlight:
                pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth, kind: .highlight(r)))
            case .mosaic:
                if let img = pixelateRegion(r, of: shot.image, scale: shot.scale) {
                    pushShape(Drawable(color: currentColor, lineWidth: 0,
                                       kind: .mosaic(rect: r, image: img)))
                }
            default: break
            }

        case .text:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        // Cmd-Z undo, ESC cancel.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "z" {
            undo()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    func undo() {
        if textField != nil { commitTextField() }
        _ = shapes.popLast()
        needsDisplay = true
    }

    // MARK: - Text tool

    private func startTextField(at canvasPoint: CGPoint) {
        let field = NSTextField(frame: .zero)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.systemFont(ofSize: max(14, currentLineWidth * 5), weight: .medium)
        field.textColor = currentColor
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.placeholderString = "Text"
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        field.frame = NSRect(x: canvasPoint.x, y: bounds.height - canvasPoint.y - 28,
                             width: 220, height: 28)
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextField()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextField()
    }

    private func commitTextField() {
        guard let field = textField else { return }
        textField = nil
        let str = field.stringValue
        let origin = CGPoint(x: field.frame.minX, y: bounds.height - field.frame.maxY)
        field.removeFromSuperview()
        guard !str.isEmpty else { needsDisplay = true; return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(14, currentLineWidth * 5), weight: .medium),
            .foregroundColor: currentColor
        ]
        pushShape(Drawable(color: currentColor, lineWidth: currentLineWidth,
                           kind: .text(origin: origin,
                                       string: NSAttributedString(string: str, attributes: attrs))))
        needsDisplay = true
    }

    // MARK: - Export

    /// Render base image + shapes at full pixel resolution.
    func renderFinal() -> CGImage? {
        commitTextField()
        let w = shot.image.width, h = shot.image.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(shot.image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let scale = shot.scale
        // Flip to top-left and scale points→pixels.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for shape in shapes { shape.draw(in: ctx) }
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
}
