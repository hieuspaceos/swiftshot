import Cocoa
import UniformTypeIdentifiers

/// Editor window: annotation canvas in a scroll view plus a toolbar.
/// All shape coordinates are in canvas points (top-left origin),
/// where canvas point size = pixelSize / shot.scale.
final class EditorWindow: NSWindow, NSWindowDelegate, NSTextFieldDelegate {

    let shot: ScreenShot
    /// Called on Copy/Save (with rendered image) and on Cancel (nil).
    var onFinish: ((CGImage?) -> Void)?

    private let canvasView: EditorCanvasView
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var finished = false
    /// Row-1 prompt field for agent questions.
    private let promptField = NSTextField()

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
        let toolbarH: CGFloat = 44
        let maxW = screen.width - 60, maxH = screen.height - toolbarH - 60
        let winW = min(max(canvasSize.width + 2, 720), maxW)
        let winH = min(canvasSize.height + 2 + toolbarH, maxH + toolbarH)
        let origin = NSPoint(x: screen.midX - winW / 2, y: screen.midY - winH / 2)

        // Borderless floating panel — the editor should feel like the
        // capture HUD (Screenshot.app / Shottr), not a document window.
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
                   styleMask: [.borderless, .resizable],
                   backing: .buffered,
                   defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.minSize = NSSize(width: 480, height: 320)
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = true
        self.delegate = self

        // Round the whole HUD window — contentView layer clips corners.
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 14
        self.contentView?.layer?.masksToBounds = true
        self.contentView?.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.97).cgColor

        buildToolbar(in: self.contentView!, canvasSize: canvasSize)

        canvasView.onCancel = { [weak self] in self?.finish(nil) }
        canvasView.needsDisplay = true
    }

    /// Compact icon button for the HUD toolbar — dark, rounded, with a
    /// visible hover/press highlight.
    private func iconButton(_ symbol: String, tip: String, action: Selector,
                            frame: NSRect) -> NSButton {
        let b = HUDIconButton(frame: frame)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.imagePosition = .imageOnly
        b.contentTintColor = .white
        b.toolTip = tip
        b.target = self
        b.action = action
        return b
    }

    /// Icon button with subtle rounded highlight on hover/press so clicks
    /// read as a press, not a no-op.
    private final class HUDIconButton: NSButton {
        private var tracking: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .regularSquare
            isBordered = false
            wantsLayer = true
            layer?.cornerRadius = 7
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let t = tracking { removeTrackingArea(t) }
            let t = NSTrackingArea(rect: bounds,
                                   options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self)
            addTrackingArea(t)
            tracking = t
        }
        override func mouseEntered(with event: NSEvent) {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        }
        override func mouseExited(with event: NSEvent) {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        override func mouseDown(with event: NSEvent) {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.26).cgColor
            super.mouseDown(with: event)
        }
        override func mouseUp(with event: NSEvent) {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            super.mouseUp(with: event)
        }
    }

    // Borderless panels can't become key by default — without this the
    // prompt field never receives keyboard focus.
    override var canBecomeKey: Bool { true }

    // MARK: - Toolbar

    private func buildToolbar(in contentView: NSView, canvasSize: NSSize) {
        // Single-row HUD: prompt first (compact), then actions | tools |
        // color-dot | width | undo | cancel.
        let barH: CGFloat = 48
        let toolbar = NSView(frame: NSRect(x: 0, y: 0,
                                           width: contentView.bounds.width, height: barH))
        toolbar.autoresizingMask = [.width]

        var x: CGFloat = 12
        let iy: CGFloat = (barH - 28) / 2

        // — Prompt first, compact —
        promptField.placeholderString = "Ask…  ⏎ sends"
        promptField.bezelStyle = .roundedBezel
        promptField.font = .systemFont(ofSize: 12)
        promptField.delegate = self
        promptField.frame = NSRect(x: x, y: iy + 1, width: 160, height: 26)
        toolbar.addSubview(promptField)
        x += 168

        // — Actions —
        let specs: [(String, String, Selector)] = [
            ("doc.on.doc", "Copy", #selector(copyClicked)),
            ("square.and.arrow.down", "Save…", #selector(saveClicked)),
            ("paperplane.fill", "Send to agent (⌥-click: choose app)", #selector(agentClicked)),
            ("square.and.arrow.up", "Share…", #selector(shareClicked)),
        ]
        for (symbol, tip, sel) in specs {
            let b = iconButton(symbol, tip: tip, action: sel,
                               frame: NSRect(x: x, y: iy, width: 30, height: 28))
            if symbol == "paperplane.fill" {
                b.sendAction(on: [.leftMouseDown, .rightMouseDown])
            }
            toolbar.addSubview(b)
            x += 32
        }

        x += 6
        // — Drawing tools —
        for tool in EditorTool.allCases {
            let b = iconButton(tool.symbol, tip: tool.title,
                               action: #selector(toolClicked(_:)),
                               frame: NSRect(x: x, y: iy, width: 30, height: 28))
            b.tag = tool.rawValue
            toolbar.addSubview(b)
            toolButtons.append(b)
            x += 32
        }

        x += 6
        // — Color dot —
        colorChip.frame = NSRect(x: x, y: iy + 2, width: 24, height: 24)
        colorChip.wantsLayer = true
        colorChip.layer?.cornerRadius = 12
        colorChip.layer?.borderWidth = 2
        colorChip.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        colorChip.layer?.backgroundColor = canvasView.currentColor.cgColor
        colorChip.title = ""
        colorChip.bezelStyle = .inline
        colorChip.isBordered = false
        colorChip.toolTip = "Stroke color"
        colorChip.setAccessibilityLabel("Stroke color")
        colorChip.target = self
        colorChip.action = #selector(colorChipClicked(_:))
        toolbar.addSubview(colorChip)
        x += 30

        let slider = NSSlider(value: 3, minValue: 1, maxValue: 14,
                              target: self, action: #selector(widthChanged(_:)))
        slider.frame = NSRect(x: x, y: iy + 4, width: 64, height: 20)
        slider.toolTip = "Stroke width"
        toolbar.addSubview(slider)
        x += 70

        // — Undo —
        let undo = iconButton("arrow.uturn.backward", tip: "Undo",
                              action: #selector(undoClicked),
                              frame: NSRect(x: x, y: iy, width: 30, height: 28))
        toolbar.addSubview(undo)

        let cancel = iconButton("xmark", tip: "Cancel", action: #selector(cancelClicked),
                                frame: NSRect(x: toolbar.bounds.width - 40, y: iy,
                                              width: 30, height: 28))
        cancel.autoresizingMask = [.minXMargin]
        toolbar.addSubview(cancel)

        contentView.addSubview(toolbar)

        // Canvas scroll view occupies the top area; the toolbar row sits
        // BELOW it (bottom-mounted HUD).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: barH,
                                                width: contentView.bounds.width,
                                                height: contentView.bounds.height - barH))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.12, alpha: 1)
        canvasView.frame = NSRect(origin: .zero, size: canvasSize)
        scroll.documentView = canvasView
        contentView.addSubview(scroll)
    }

    /// Color swatch chip — click pops a dropdown of palette colors.
    private let colorChip = NSButton()

    @objc private func colorChipClicked(_ sender: NSButton) {
        let menu = NSMenu()
        for (i, color) in EditorWindow.palette.enumerated() {
            let item = NSMenuItem(title: colorName(i),
                                  action: #selector(colorMenuPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = i
            // Big swatch + name so colors read clearly.
            let swatch = NSImage(size: NSSize(width: 24, height: 24))
            swatch.lockFocus()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 22, height: 22),
                         xRadius: 11, yRadius: 11).fill()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 21, height: 21),
                         xRadius: 10.5, yRadius: 10.5).stroke()
            swatch.unlockFocus()
            item.image = swatch
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 4),
                   in: sender)
    }

    @objc private func colorMenuPicked(_ sender: NSMenuItem) {
        canvasView.currentColor = EditorWindow.palette[sender.tag]
        colorChip.layer?.backgroundColor = canvasView.currentColor.cgColor
    }

    private func colorName(_ i: Int) -> String {
        ["Red", "Yellow", "Green", "Blue", "Purple", "White", "Black"][i]
    }

    private func updateColorSelection() {
        colorChip.layer?.backgroundColor = canvasView.currentColor.cgColor
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        canvasView.currentTool = EditorTool(rawValue: sender.tag) ?? .pen
        for b in toolButtons { b.state = (b == sender) ? .on : .off }
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

    /// Save the capture to the save directory, then hand it to the front
    /// CLI agent: put PNG + file URL + path on the pasteboard, re-activate
    /// the previously focused app (the terminal running omp/claude/…), and
    /// synthesize ⌘V so the shot lands at the prompt. Needs Accessibility
    /// permission for the synthetic keystroke; without it the pasteboard
    /// still carries everything so a manual ⌘V works.
    /// ⌥-click shows a picker of running agent targets (terminals and
    /// editors); plain click uses the Preferences target or the app that
    /// was frontmost when the capture started.
    @objc private func agentClicked(_ sender: NSButton) {
        let altDown = NSEvent.modifierFlags.contains(.option)
        if altDown { showAgentTargetMenu(sender); return }
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        agentCommit(prompt: prompt.isEmpty ? nil : prompt)
    }

    /// Agent path shared by the button and ⏎ in the prompt field:
    /// annotate via Vision when a prompt exists, save, paste into the
    /// target, auto-submit.
    private func agentCommit(prompt: String?, target: NSRunningApplication? = nil) {
        guard let image = canvasView.renderFinal() else { return }
        // Annotate synchronously — a region capture is small and the
        // user just asked for delivery; a 200–400 ms pause is fine.
        let out = (prompt.map { VisionAnnotator.annotate(image: image, query: $0,
                                                         bestOnly: true) ?? image }) ?? image
        let dir = defaultSaveDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(defaultFileName(ext: "png"))
        write(out, to: url)
        EditorWindow.copyForAgent(image: out, fileURL: url)
        AgentPaste.paste(into: target, prompt: prompt)
        finish(out)
    }

    /// Menu of running terminals/editors plus "Auto" — transient choice
    /// for this paste only; it doesn't touch the Preferences default.
    private func showAgentTargetMenu(_ anchor: NSButton) {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Auto (last focused app)",
                              action: #selector(agentTargetPicked(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = nil
        menu.addItem(auto)
        menu.addItem(.separator())
        for app in AgentPaste.runningKnownTargets() {
            let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier ?? "?",
                                  action: #selector(agentTargetPicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = app
            if let id = app.bundleIdentifier {
                item.state = (id == AgentPaste.preferredTargetID) ? .on : .off
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4),
                   in: anchor)
    }

    @objc private func agentTargetPicked(_ sender: NSMenuItem) {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        agentCommit(prompt: prompt.isEmpty ? nil : prompt,
                    target: sender.representedObject as? NSRunningApplication)
    }

    /// Live OCR hints: debounce typing, run Vision off the main thread,
    /// show dashed ellipses over matching text as a preview.
    private var hintWork: DispatchWorkItem?

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === promptField else { return }
        let query = promptField.stringValue
        hintWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                DispatchQueue.main.async { self.canvasView.hintRects = [] }
                return
            }
            let rects = VisionAnnotator.matchRects(image: self.shot.image, query: query,
                                                   bestOnly: true)
            DispatchQueue.main.async { self.canvasView.hintRects = rects }
        }
        hintWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18, execute: work)
    }


    /// macOS share sheet — Messages, AirDrop, Mail, plus chat apps that
    /// register a Share extension (Zalo/Messenger appear there when
    /// their macOS apps are installed).
    @objc private func shareClicked(_ sender: NSButton) {
        guard let image = canvasView.renderFinal() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]),
              let nsImage = NSImage(data: data) else { return }
        let picker = NSSharingServicePicker(items: [nsImage])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    /// ⏎ in the prompt field = Agent with that prompt.
    func controlTextDidEndEditing(_ obj: Notification) {
        if let mv = obj.userInfo?["NSTextMovement"] as? Int, mv == NSReturnTextMovement {
            let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            agentCommit(prompt: prompt.isEmpty ? nil : prompt)
        }
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

    /// Pasteboard variant for agent handoff: PNG data + promised TIFF +
    /// file URL + bare POSIX path. Apps that accept image pastes (Orca,
    /// VSCode chat, Claude Code ⌃V…) take the PNG; terminals fall back
    /// to the path string. The prompt text is deliberately NOT merged
    /// into .string — chat boxes prefer text over image and would paste
    /// the prompt instead of the shot. Prompts go through keystrokes
    /// after the paste (see AgentPaste).
    static func copyForAgent(image: CGImage, fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        item.setDataProvider(PasteboardTIFFProvider(image: image), forTypes: [.tiff])
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(fileURL.path, forType: .string)
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
        // The editor floats above panels — drop our level while the
        // save sheet is up so it isn't hidden behind us.
        level = .normal
        panel.begin { [weak self] response in
            self?.level = .floating
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

        // Live OCR hints while the user types in the prompt field —
        // dashed red ellipses at canvas scale (pixels → points via
        // shot.scale), preview only, not part of the render.
        if !hintRects.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(red: 1, green: 0.25, blue: 0.22, alpha: 0.9))
            ctx.setLineWidth(2.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            let s = shot.scale
            for r in hintRects {
                let pt = CGRect(x: r.minX / s, y: r.minY / s,
                                width: r.width / s, height: r.height / s)
                    .insetBy(dx: -6, dy: -6)
                ctx.strokeEllipse(in: pt)
            }
            ctx.restoreGState()
        }
    }


    /// Pixel-space rects to preview as OCR hint ellipses.
    var hintRects: [CGRect] = [] {
        didSet { needsDisplay = true }
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
