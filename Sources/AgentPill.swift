import Cocoa

/// Post-capture floating pill: appears next to the cursor with a prompt
/// field already focused. Type what the shot is about ("nút Login bị
/// lỗi"), hit ⏎ → the capture gets Vision-annotated around matching
/// text and the whole thing (annotated PNG + path + prompt) is pasted
/// into the agent terminal.
///
///   ⏎ / 🤖 button  → annotate + paste + prompt into target app
///   📋 button      → plain copy (no prompt)
///   ✏️ button      → open the full editor for manual annotation
///   ⎋              → dismiss
final class AgentPill: NSPanel, NSTextFieldDelegate {

    /// Called on Agent (annotated image + prompt) or Copy (image, nil).
    var onCommit: ((CGImage, String?) -> Void)?
    /// Called when the user picks ✏️ — the raw capture, unannotated.
    var onEdit: ((CGImage) -> Void)?

    private let shotImage: CGImage
    private let promptField = NSTextField()

    init(image: CGImage, scale: CGFloat) {
        self.shotImage = image
        let w: CGFloat = 420, h: CGFloat = 40
        // Place near the cursor, clamped into the visible frame.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let x = min(max(mouse.x + 12, vf.minX + 8), vf.maxX - w - 8)
        let y = min(max(mouse.y - h - 12, vf.minY + 8), vf.maxY - h - 8)
        super.init(contentRect: NSRect(x: x, y: y, width: w, height: h),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        contentView = bg

        let thumb = NSImageView(frame: NSRect(x: 8, y: 6, width: 40, height: 28))
        thumb.image = NSImage(cgImage: image, size: NSSize(width: 40, height: 28))
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        bg.addSubview(thumb)

        promptField.frame = NSRect(x: 56, y: 7, width: w - 56 - 3 * 36 - 16, height: 26)
        promptField.placeholderString = "What's this about?  ⏎ sends to agent"
        promptField.isBordered = false
        promptField.drawsBackground = false
        promptField.focusRingType = .none
        promptField.font = .systemFont(ofSize: 13)
        promptField.delegate = self
        bg.addSubview(promptField)

        var bx = w - 3 * 36 - 8
        for (symbol, tip, sel) in [
            ("paperplane.fill", "Send to agent (⏎)", #selector(agentClicked)),
            ("doc.on.doc", "Copy (⌘C)", #selector(copyClicked)),
            ("pencil.tip", "Edit manually", #selector(editClicked)),
        ] as [(String, String, Selector)] {
            let b = NSButton(frame: NSRect(x: bx, y: 4, width: 34, height: 32))
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            b.imagePosition = .imageOnly
            b.toolTip = tip
            b.target = self
            b.action = sel
            bg.addSubview(b)
            bx += 36
        }
    }

    /// Dismiss when the user clicks elsewhere — a pill that survives
    /// after losing key status just piles up as dead panels.
    override func resignKey() {
        super.resignKey()
        close()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(promptField)
    }

    // MARK: - Actions

    @objc private func agentClicked() {
        commit(sendToAgent: true)
    }

    @objc private func copyClicked() {
        onCommit?(shotImage, nil)
        close()
    }

    @objc private func editClicked() {
        onEdit?(shotImage)
        close()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // NSTextField calls this on ⏎ when it's the field editor's
        // delegate and there's no formatter; guard the movement reason.
        if let mv = obj.userInfo?["NSTextMovement"] as? Int, mv == NSReturnTextMovement {
            commit(sendToAgent: true)
        }
    }

    private func commit(sendToAgent: Bool) {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Annotate in the background — OCR on a fullscreen capture takes
        // a few hundred ms, don't stall the UI. Capture onCommit BEFORE
        // close(): isReleasedWhenClosed deallocs the pill, so [weak self]
        // would be nil by the time the background task finishes.
        let image = shotImage
        let cb = onCommit
        close()
        DispatchQueue.global(qos: .userInitiated).async {
            let out = sendToAgent && !prompt.isEmpty
                ? (VisionAnnotator.annotate(image: image, query: prompt,
                                            bestOnly: true) ?? image)
                : image
            DispatchQueue.main.async {
                cb?(out, sendToAgent ? (prompt.isEmpty ? nil : prompt) : nil)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCommit?(shotImage, nil) // treat as plain copy, don't lose the shot
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}
