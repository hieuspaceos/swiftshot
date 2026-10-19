import Cocoa

// MARK: - Headless demo recorder
// `./SwiftShot --record <outdir>` renders the real capture→annotate pipeline
// into a PNG frame sequence (1920x1080, 60fps) — no windows are created.
// ffmpeg turns the frames into the showcase video:
//   ffmpeg -framerate 60 -i <outdir>/f%04d.png -c:v libx264 -pix_fmt yuv420p demo.mp4

enum RecordDemo {

    static let W: CGFloat = 1920, H: CGFloat = 1080
    static let TOTAL = 900

    static func run(outdir: String) {
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor in
            defer { sem.signal() }
            do {
                // Synthetic scene — no live screen capture, so recording runs
                // fully headless without touching the user's session.
                guard let (img, sc) = syntheticScene() else {
                    print("record: scene build failed"); return
                }
                try? FileManager.default.createDirectory(atPath: outdir,
                                                         withIntermediateDirectories: true)
                for f in 0..<TOTAL {
                    autoreleasepool {
                        render(frame: f, shot: img, scale: sc, outdir: outdir)
                    }
                    if f % 90 == 0 { print("frame \(f)/\(TOTAL)") }
                }
                print("record: done -> \(outdir)")
            } catch {
                print("record error: \(error)")
            }
        }
        let deadline = Date().addingTimeInterval(300)
        while sem.wait(timeout: .now()) == .timedOut, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(0)
    }

    // MARK: synthetic scene

    /// Builds a clean "desktop" image (real wallpaper + two Finder-style
    /// windows) — what --record uses instead of capturing the live screen.
    /// Rendered at 2x → scale = 2.
    private static func syntheticScene() -> (CGImage, CGFloat)? {
        let sw: CGFloat = 1512, sh: CGFloat = 950   // points; output @2x
        guard let ctx = CGContext(data: nil, width: Int(sw * 2), height: Int(sh * 2),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: 2, y: 2)

        // real wallpaper (fall back to gradient)
        var drew = false
        if let url = NSWorkspace.shared.desktopImageURL(for: NSScreen.main ?? NSScreen()),
           let wp = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let iw = CGFloat(wp.width), ih = CGFloat(wp.height)
            let z = max(sw / iw, sh / ih)
            ctx.draw(wp, in: CGRect(x: (sw - iw * z) / 2, y: (sh - ih * z) / 2,
                                   width: iw * z, height: ih * z))
            drew = true
        }
        if !drew {
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [CGColor(red: 0.10, green: 0.18, blue: 0.42, alpha: 1),
                         CGColor(red: 0.42, green: 0.24, blue: 0.55, alpha: 1),
                         CGColor(red: 0.75, green: 0.33, blue: 0.49, alpha: 1)] as CFArray,
                locations: [0, 0.55, 1])!
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: sw, y: sh), options: [])
        }

        // two clean windows like the staged screenshots: Finder home + Applications
        drawFinderWindow(ctx, rect: CGRect(x: 0, y: sh - 990 + 40 - 26, width: 756, height: 950),
                         title: "hieuspace",
                         items: ["Applications","bin","cAlgo","cTrader","Desktop","Downloads",
                                 "html-video","Movies","Music","orca","Public"],
                         folderStyle: true)
        drawFinderWindow(ctx, rect: CGRect(x: 756, y: sh - 990 + 40 - 26, width: 756, height: 950),
                         title: "Applications",
                         items: ["App Store","Apps","Automator","Brave Browser","Calculator",
                                 "Calendar","Contacts","Dictionary","FaceTime","Find My",
                                 "Font Book","Freeform"],
                         folderStyle: false)

        // menubar
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.85))
        ctx.fill(CGRect(x: 0, y: sh - 26, width: sw, height: 26))
        drawText(ctx, "  Finder   File   Edit   View   Go   Window   Help",
                 at: CGPoint(x: 12, y: sh - 19), size: 13,
                 color: CGColor(gray: 0.1, alpha: 1))
        drawText(ctx, "Mon 19 Oct 13:50",
                 at: CGPoint(x: sw - 150, y: sh - 19), size: 12,
                 color: CGColor(gray: 0.1, alpha: 1))

        guard let img = ctx.makeImage() else { return nil }
        return (img, 2)
    }

    /// Minimal Finder-style window: dark sidebar + icon grid — matches the
    /// staged screenshots used on the site.
    private static func drawFinderWindow(_ ctx: CGContext, rect: CGRect,
                                         title: String, items: [String], folderStyle: Bool) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40,
                      color: CGColor(gray: 0, alpha: 0.45))
        roundRect(ctx, rect, 10)
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.saveGState()
        roundRect(ctx, rect, 10)
        ctx.clip()
        // sidebar
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: 190, height: rect.height))
        let side = ["Recents","Shared","","FAVORITES","Applications","Desktop","Documents",
                    "Downloads","","LOCATIONS","iCloud Drive","hieuspace","Macintosh HD",
                    "Network","Trash"]
        var sy = rect.maxY - 60
        for s in side {
            let header = s == "FAVORITES" || s == "LOCATIONS"
            drawText(ctx, s.isEmpty ? " " : s,
                     at: CGPoint(x: rect.minX + 14, y: sy), size: header ? 10 : 12,
                     color: header ? CGColor(gray: 0.45, alpha: 1)
                                   : CGColor(gray: 0.75, alpha: 1))
            sy -= s.isEmpty ? 14 : 20
        }
        // toolbar
        ctx.setFillColor(CGColor(gray: 0.17, alpha: 1))
        ctx.fill(CGRect(x: rect.minX + 190, y: rect.maxY - 40, width: rect.width - 190, height: 40))
        let lights: [CGColor] = [
            CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1),
            CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
            CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
        for (i, c) in lights.enumerated() {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: rect.minX + 12 + CGFloat(i) * 20,
                                       y: rect.maxY - 26, width: 12, height: 12))
        }
        drawText(ctx, title, at: CGPoint(x: rect.minX + 210, y: rect.maxY - 27),
                 size: 13, color: CGColor(gray: 0.6, alpha: 1))
        // icon grid
        let cols = 4
        for (i, name) in items.enumerated() {
            let col = i % cols, row = i / cols
            let ix = rect.minX + 214 + CGFloat(col) * 130
            let iy = rect.maxY - 140 - CGFloat(row) * 120
            // icon
            let ir = CGRect(x: ix, y: iy, width: 60, height: 46)
            roundRect(ctx, ir, 8)
            ctx.setFillColor(folderStyle
                ? CGColor(red: 0.49, green: 0.78, blue: 0.95, alpha: 1)
                : CGColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1))
            ctx.fillPath()
            // folder tab
            if folderStyle {
                ctx.fill(CGRect(x: ir.minX, y: ir.maxY - 4, width: 22, height: 8))
            }
            drawText(ctx, name, at: CGPoint(x: ix - max(0, textWidth(name, 11) - 60) / 2,
                                            y: iy - 14),
                     size: 11, color: CGColor(gray: 0.85, alpha: 1))
        }
        ctx.restoreGState()
        ctx.restoreGState()
    }

    // MARK: frame pipeline

    /// The captured desktop, fit into 1920x1080 (letterboxed, blurred backdrop).
    private static func drawDesktop(_ ctx: CGContext, shot: CGImage, scale: CGFloat) {
        // blurred zoomed backdrop
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let sw = CGFloat(shot.width) / scale, sh = CGFloat(shot.height) / scale
        let z = max(CGFloat(W) / sw, CGFloat(H) / sh) * 1.15
        let bg = CGRect(x: (CGFloat(W) - sw * z) / 2, y: (CGFloat(H) - sh * z) / 2,
                        width: sw * z, height: sh * z)
        ctx.saveGState()
        ctx.setAlpha(0.5)
        ctx.draw(shot, in: bg)
        ctx.restoreGState()
        // dim
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.restoreGState()
    }

    /// desktop rect where the real capture sits (16:9-fit, centered)
    private static func fit(_ shot: CGImage, scale: CGFloat) -> CGRect {
        let sw = CGFloat(shot.width) / scale, sh = CGFloat(shot.height) / scale
        let z = min(CGFloat(W) / sw, CGFloat(H) / sh)
        return CGRect(x: (CGFloat(W) - sw * z) / 2, y: (CGFloat(H) - sh * z) / 2,
                      width: sw * z, height: sh * z)
    }

    static func render(frame f: Int, shot: CGImage, scale: CGFloat, outdir: String) {
        guard let ctx = CGContext(
            data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }

        let screen = fit(shot, scale: scale)
        let easeOut: (CGFloat) -> CGFloat = { 1 - pow(1 - $0, 3) }
        let prog = { (a: Int, b: Int) -> CGFloat in
            guard f > a else { return 0 }
            return easeOut(min(1, CGFloat(f - a) / CGFloat(b - a)))
        }

        // ---- phase A (0-300): desktop + dim overlay + rubber band + flash
        // ---- phase B (300-660): editor window, annotations commit progressively
        // ---- phase C (660-900): back to desktop + floating preview

        drawDesktop(ctx, shot: shot, scale: scale)

        if f < 300 {
            let dim = prog(10, 30) * 0.45
            ctx.setFillColor(CGColor(gray: 0, alpha: dim))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.draw(shot, in: screen)

            // rubber band from (x0,y0) to animated end
            let t = prog(80, 210)
            let r0 = CGPoint(x: screen.minX + 130, y: screen.minY + 120)
            let r1 = CGPoint(x: screen.maxX - 190, y: screen.maxY - 140)
            let cur = CGPoint(x: r0.x + (r1.x - r0.x) * t, y: r0.y + (r1.y - r0.y) * t)
            if t > 0 {
                let sel = CGRect(x: r0.x, y: r0.y,
                                 width: cur.x - r0.x, height: cur.y - r0.y)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
                ctx.setLineWidth(1.5)
                ctx.stroke(sel)
                // undim inside selection
                ctx.saveGState()
                ctx.clip(to: [sel])
                ctx.setFillColor(CGColor(gray: 0, alpha: -dim)) // noop; draw shot over
                ctx.draw(shot, in: screen)
                ctx.restoreGState()
            }
            // white flash on commit
            let flash = prog(218, 224) * (1 - prog(224, 240))
            if flash > 0 {
                ctx.setFillColor(CGColor(gray: 1, alpha: flash))
                ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            }
        } else if f < 660 {
            // ---- editor window
            let lf = f - 300
            let pop = { (a: Int, b: Int) -> CGFloat in
                guard lf > a else { return 0 }
                return easeOut(min(1, CGFloat(lf - a) / CGFloat(b - a)))
            }
            let inT = pop(0, 20)

            // window frame: toolbar 46pt + titlebar ~28 + canvas (the shot)
            let cw: CGFloat = 1400, ch: CGFloat = 790
            let wx: CGFloat = (CGFloat(W) - cw) / 2
            let wy: CGFloat = (CGFloat(H) - ch) / 2 + (1 - inT) * 50
            ctx.saveGState()
            ctx.setAlpha(inT)

            // shadow + window
            ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 46,
                          color: CGColor(gray: 0, alpha: 0.6))
            let win = CGRect(x: wx, y: wy, width: cw, height: ch + 74)
            roundRect(ctx, win, 10)
            ctx.setFillColor(CGColor(gray: 0.16, alpha: 1))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)

            // titlebar
            let tb = CGRect(x: wx, y: wy + ch + 46, width: cw, height: 28)
            ctx.setFillColor(CGColor(gray: 0.17, alpha: 1))
            ctx.fill(tb)
            // traffic lights
            let lights: [CGColor] = [
                CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1),
                CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                CGColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
            for (i, c) in lights.enumerated() {
                ctx.setFillColor(c)
                ctx.fillEllipse(in: CGRect(x: wx + 12 + CGFloat(i) * 20, y: tb.minY + 8, width: 12, height: 12))
            }
            drawText(ctx, "SwiftShot — 1250×710",
                     at: CGPoint(x: wx + 80, y: tb.minY + 8),
                     size: 13, color: CGColor(gray: 0.7, alpha: 1))

            // toolbar bg
            let tbar = CGRect(x: wx, y: wy + ch, width: cw, height: 46)
            ctx.setFillColor(CGColor(gray: 0.23, alpha: 1))
            ctx.fill(tbar)

            // canvas = region capture (the shot, scaled into the canvas area)
            ctx.saveGState()
            ctx.clip(to: [CGRect(x: wx, y: wy, width: cw, height: ch)])
            let cz = min(cw / screen.width, ch / screen.height)
            let cd = CGRect(x: wx + (cw - screen.width * cz) / 2,
                            y: wy + (ch - screen.height * cz) / 2,
                            width: screen.width * cz, height: screen.height * cz)
            ctx.draw(shot, in: cd)

            // --- annotations appear progressively (using real renderFinal for committed set)
            let shot2 = ScreenShot(image: shot, scale: scale, frame: .zero)
            let canvas = EditorCanvasView(shot: shot2)
            canvas.frame = NSRect(x: 0, y: 0,
                                  width: CGFloat(shot.width) / scale,
                                  height: CGFloat(shot.height) / scale)

            // annotation stages — same kinds the editor draws
            var shapes: [Drawable] = []
            let CS = CGSize(width: canvas.frame.width, height: canvas.frame.height)
            if lf >= 40 {
                // arrow across the left window
                shapes.append(Drawable(color: .systemRed, lineWidth: 5,
                    kind: .line(start: CGPoint(x: CS.width * 0.28, y: CS.height * 0.72),
                                end: CGPoint(x: CS.width * 0.52, y: CS.height * 0.42),
                                arrowHead: true)))
            }
            if lf >= 90 {
                shapes.append(Drawable(color: .systemGreen, lineWidth: 4,
                    kind: .rect(CGRect(x: CS.width * 0.60, y: CS.height * 0.18,
                                       width: CS.width * 0.28, height: CS.height * 0.30))))
            }
            if lf >= 130 {
                shapes.append(Drawable(color: .systemYellow, lineWidth: 4,
                    kind: .highlight(CGRect(x: CS.width * 0.10, y: CS.height * 0.12,
                                            width: CS.width * 0.22, height: CS.height * 0.14))))
            }
            if lf >= 170, let mos = pixelateRegion(
                CGRect(x: CS.width * 0.10, y: CS.height * 0.55,
                       width: CS.width * 0.16, height: CS.height * 0.12),
                of: shot, scale: scale) {
                shapes.append(Drawable(color: .black, lineWidth: 0,
                    kind: .mosaic(rect: CGRect(x: CS.width * 0.10, y: CS.height * 0.55,
                                               width: CS.width * 0.16, height: CS.height * 0.12),
                                  image: mos)))
            }
            if lf >= 210 {
                shapes.append(Drawable(color: .systemYellow, lineWidth: 4,
                    kind: .text(origin: CGPoint(x: CS.width * 0.34, y: CS.height * 0.30),
                                string: NSAttributedString(
                                    string: "Everything I need ↑",
                                    attributes: [.font: NSFont.boldSystemFont(ofSize: 26),
                                                 .foregroundColor: NSColor.systemYellow]))))
            }
            canvas.shapes = shapes
            if let rendered = canvas.renderFinal() {
                ctx.draw(rendered, in: cd)
            }
            ctx.restoreGState()

            // toolbar buttons — mirrors real layout: Copy Save… Cancel | tools | colors | slider | Undo
            var bx = wx + 10
            let by = wy + ch + 8
            for (i, t) in ["Copy", "Save…", "Cancel"].enumerated() {
                let pressed = (i == 0 && lf >= 250 && lf < 262)
                drawButton(ctx, rect: CGRect(x: bx, y: by, width: 66, height: 30),
                           title: t, accent: i == 0, pressed: pressed)
                bx += 72
            }
            bx += 10
            let tools = ["Pen", "Arrow", "Rect", "Ellipse", "HL", "Mosaic", "Text"]
            // active tool follows the annotation being drawn
            let act = lf < 40 ? 0 : lf < 90 ? 1 : lf < 130 ? 2 : lf < 170 ? 4 : lf < 210 ? 5 : lf < 250 ? 6 : 0
            for (i, t) in tools.enumerated() {
                drawPill(ctx, rect: CGRect(x: bx, y: by, width: 58, height: 30),
                         title: t, active: i == act)
                bx += 62
            }
            bx += 12
            let palette = EditorWindow.palette
            for (i, c) in palette.enumerated() {
                ctx.setFillColor(c.cgColor)
                let r = CGRect(x: bx, y: by + 5, width: 20, height: 20)
                ctx.fillEllipse(in: r)
                ctx.setStrokeColor(i == 0 ? CGColor(gray: 1, alpha: 1)
                                          : CGColor(gray: 1, alpha: 0.3))
                ctx.setLineWidth(i == 0 ? 2.5 : 1)
                ctx.strokeEllipse(in: r)
                bx += 26
            }
            bx += 10
            // slider
            ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
            roundRect(ctx, CGRect(x: bx, y: by + 13, width: 90, height: 4), 2)
            ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: bx + 18, y: by + 8, width: 14, height: 14))
            bx += 102
            drawButton(ctx, rect: CGRect(x: bx, y: by, width: 50, height: 30),
                       title: "Undo", accent: false, pressed: false)
            ctx.restoreGState()
        } else {
            // ---- floating preview bottom-right
            let lf = f - 660
            let pop = { (a: Int, b: Int) -> CGFloat in
                guard lf > a else { return 0 }
                return easeOut(min(1, CGFloat(lf - a) / CGFloat(b - a)))
            }
            ctx.draw(shot, in: screen)
            let pt = pop(10, 30)
            let pw: CGFloat = 330, ph: CGFloat = 200
            let px = CGFloat(W) - pw - 42, py = CGFloat(40) + (1 - pt) * 60
            ctx.saveGState()
            ctx.setAlpha(pt)
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 34,
                          color: CGColor(gray: 0, alpha: 0.6))
            let pr = CGRect(x: px, y: py, width: pw, height: ph)
            roundRect(ctx, pr, 10)
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            roundRect(ctx, pr, 10)
            ctx.clip()
            ctx.draw(shot, in: pr)
            // mini annotations hint (arrow + text)
            ctx.setStrokeColor(CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1))
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: px + 80, y: py + 60))
            ctx.addLine(to: CGPoint(x: px + 150, y: py + 120))
            ctx.strokePath()
            ctx.restoreGState()
            // dismiss ×
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
            ctx.fillEllipse(in: CGRect(x: px + pw - 28, y: py + ph - 28, width: 22, height: 22))
            drawText(ctx, "×", at: CGPoint(x: px + pw - 22, y: py + ph - 24),
                     size: 14, color: CGColor(gray: 1, alpha: 1))
            ctx.restoreGState()

            // "copied" toast early on
            let toast = (1 - prog(70, 110)) * pop(10, 24)
            if toast > 0 {
                let tr = CGRect(x: CGFloat(W) - 330 - 42, y: py + ph + 18, width: 240, height: 34)
                ctx.saveGState()
                ctx.setAlpha(toast)
                roundRect(ctx, tr, 9)
                ctx.setFillColor(CGColor(gray: 0.13, alpha: 0.95))
                ctx.fillPath()
                drawText(ctx, "✓ Copied to clipboard",
                         at: CGPoint(x: tr.minX + 14, y: tr.minY + 10),
                         size: 14, color: CGColor(gray: 1, alpha: 1))
                ctx.restoreGState()
            }
        }

        // menubar strip on top, always
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.85))
        ctx.fill(CGRect(x: 0, y: CGFloat(H) - 26, width: W, height: 26))
        drawText(ctx, "  Finder   File   Edit   View   Go   Window   Help",
                 at: CGPoint(x: 14, y: CGFloat(H) - 19),
                 size: 13, color: CGColor(gray: 0.1, alpha: 1))
        drawText(ctx, "􀣰  􀊯   Mon 19 Oct 13:38",
                 at: CGPoint(x: CGFloat(W) - 250, y: CGFloat(H) - 19),
                 size: 12, color: CGColor(gray: 0.1, alpha: 1))

        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        if let png = rep.representation(using: .png, properties: [:]) {
            let path = String(format: "%@/f%04d.png", outdir, f)
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: drawing helpers (all in y-up space)

    private static func roundRect(_ ctx: CGContext, _ r: CGRect, _ rad: CGFloat) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
    }

    private static func drawButton(_ ctx: CGContext, rect: CGRect, title: String,
                                   accent: Bool, pressed: Bool) {
        let g: CGFloat = pressed ? 0.3 : 0.34
        ctx.setFillColor(accent
            ? CGColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
            : CGColor(gray: g, alpha: 1))
        roundRect(ctx, rect, 6)
        ctx.fillPath()
        drawText(ctx, title, at: CGPoint(x: rect.midX - textWidth(title, 13) / 2,
                                         y: rect.minY + 9),
                 size: 13, color: CGColor(gray: 1, alpha: 1))
    }

    private static func drawPill(_ ctx: CGContext, rect: CGRect, title: String, active: Bool) {
        ctx.setFillColor(active ? CGColor(gray: 0.40, alpha: 1) : CGColor(gray: 0.30, alpha: 1))
        roundRect(ctx, rect, 6)
        ctx.fillPath()
        drawText(ctx, title, at: CGPoint(x: rect.midX - textWidth(title, 11) / 2,
                                         y: rect.minY + 10),
                 size: 11, color: CGColor(gray: 1, alpha: 1))
    }

    private static func textWidth(_ s: String, _ size: CGFloat) -> CGFloat {
        let a = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size)])
        return a.size().width
    }

    private static func drawText(_ ctx: CGContext, _ s: String, at p: CGPoint,
                                 size: CGFloat, color: CGColor) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor(cgColor: color) ?? .white]))
        ctx.saveGState()
        ctx.textPosition = p
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
