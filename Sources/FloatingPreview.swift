import Cocoa

/// Small always-on-top thumbnail pinned to the bottom-right of the screen.
/// Click reopens the editor; × dismisses; fades out after ~10s (hover restores).
final class FloatingPreviewPanel: NSPanel {

    var onReopen: ((CGImage) -> Void)?
    var onDismiss: (() -> Void)?

    /// Full-res image kept for the reopen path; nil once demoted to JPEG.
    private var image: CGImage?
    /// Compact JPEG stand-in used for reopen after demotion.
    private var demotedJPEG: Data?
    private var fadeTimer: Timer?

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        let pointSize = NSSize(width: CGFloat(image.width) / scale,
                               height: CGFloat(image.height) / scale)
        let maxSide: CGFloat = 220
        let ratio = min(maxSide / pointSize.width, maxSide / pointSize.height, 1)
        let thumbW = max(60, pointSize.width * ratio)
        let thumbH = max(36, pointSize.height * ratio)
        let pad: CGFloat = 8, closeSize: CGFloat = 20
        let size = NSSize(width: thumbW + pad * 2, height: thumbH + pad * 2 + closeSize)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 24,
                             y: screen.minY + 24)

        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let container = PreviewContainerView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor

        // Display a downscaled thumbnail; the full CGImage is only kept
        // for the reopen path — rendering a 220px thumb off a 3000px bitmap
        // wastes GPU memory on every redraw.
        let thumb = Self.downscale(image, toPixelsWide: Int(thumbW * 2)) ?? image
        let imageView = ClickableImageView(frame: NSRect(x: pad, y: pad + closeSize,
                                                         width: thumbW, height: thumbH))
        imageView.image = NSImage(cgImage: thumb, size: NSSize(width: thumbW, height: thumbH))
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.onClick = { [weak self] in self?.reopen() }
        container.addSubview(imageView)

        let close = NSButton(frame: NSRect(x: size.width - pad - closeSize,
                                           y: (closeSize - 16) / 2 + 2,
                                           width: 16, height: 16))
        close.bezelStyle = .circular
        close.title = "×"
        close.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        close.isBordered = true
        close.target = self
        close.action = #selector(closeClicked)
        container.addSubview(close)

        self.contentView = container
        scheduleFade()
    }

    private static func downscale(_ image: CGImage, toPixelsWide maxW: Int) -> CGImage? {
        guard image.width > maxW else { return nil }
        let h = image.height * maxW / image.width
        guard let ctx = CGContext(data: nil, width: maxW, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: maxW, height: h))
        return ctx.makeImage()
    }

    func show() {
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 1
        }
    }

    private func scheduleFade() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                self.animator().alphaValue = 0.3
            }
        }
    }

    func resetFade() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
        scheduleFade()
    }

    /// Release the full-res CGImage (~30–70 MB on Retina) and keep a JPEG
    /// for the reopen path. Called when a newer preview supersedes this one.
    func demoteFullImage() {
        guard image != nil else { return }
        if demotedJPEG == nil {
            demotedJPEG = NSBitmapImageRep(cgImage: image!)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
        image = nil
    }

    /// Programmatic close — same path as the × button.
    func dismiss() {
        fadeTimer?.invalidate()
        close()
        onDismiss?()
    }

    /// Image to reopen in the editor: the full-res CGImage, or the JPEG
    /// fallback decoded on demand after demotion.
    private var reopenImage: CGImage? {
        if let image { return image }
        guard let data = demotedJPEG,
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }

    private func reopen() {
        guard let img = reopenImage else { dismiss(); return }
        close()
        onReopen?(img)
        onDismiss?()
    }

    @objc private func closeClicked() {
        dismiss()
    }
}

private final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }
}

private final class PreviewContainerView: NSView {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        (window as? FloatingPreviewPanel)?.resetFade()
    }
}
