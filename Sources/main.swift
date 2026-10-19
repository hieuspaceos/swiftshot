import Cocoa

// Headless self-test: `./SwiftShot --selftest` captures all screens and exits.
if CommandLine.arguments.contains("--selftest") {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        do {
            let shots = try await ScreenCapturer.captureAllScreens()
            for s in shots {
                print("captured: \(s.image.width)x\(s.image.height) px, scale=\(s.scale), frame=\(s.frame)")
            }
            let union = shots.reduce(CGRect.null) { $0.union($1.frame) }
            if let (img, sc) = cropRegion(union, from: shots) {
                print("union crop OK: \(img.width)x\(img.height) px, scale=\(sc)")
                // Exercise the annotation/render pipeline end-to-end.
                let shot = ScreenShot(image: img, scale: sc, frame: union)
                let canvas = EditorCanvasView(shot: shot)
                canvas.frame = NSRect(x: 0, y: 0,
                                      width: CGFloat(img.width) / sc,
                                      height: CGFloat(img.height) / sc)
                canvas.shapes = [
                    Drawable(color: .systemRed, lineWidth: 4,
                             kind: .rect(CGRect(x: 40, y: 40, width: 200, height: 120))),
                    Drawable(color: .systemBlue, lineWidth: 4,
                             kind: .line(start: CGPoint(x: 40, y: 200),
                                         end: CGPoint(x: 300, y: 200), arrowHead: true)),
                    Drawable(color: .systemYellow, lineWidth: 4,
                             kind: .highlight(CGRect(x: 350, y: 60, width: 180, height: 90))),
                ]
                print("stage: basic shapes queued")
                if let r = pixelateRegion(CGRect(x: 550, y: 60, width: 160, height: 100),
                                          of: img, scale: sc) {
                    canvas.shapes.append(Drawable(color: .black, lineWidth: 0,
                        kind: .mosaic(rect: CGRect(x: 550, y: 60, width: 160, height: 100),
                                      image: r)))
                }
                print("stage: mosaic done")
                canvas.shapes.append(
                    Drawable(color: .systemGreen, lineWidth: 4,
                             kind: .text(origin: CGPoint(x: 60, y: 240),
                                         string: NSAttributedString(
                                            string: "SwiftShot selftest",
                                            attributes: [.font: NSFont.systemFont(ofSize: 24),
                                                         .foregroundColor: NSColor.systemGreen]))))
                print("stage: text queued")
                if let rendered = canvas.renderFinal() {
                    print("stage: renderFinal done")
                    let rep = NSBitmapImageRep(cgImage: rendered)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        let url = URL(fileURLWithPath: "/tmp/swiftshot-selftest.png")
                        try? png.write(to: url)
                        print("rendered PNG: \(png.count) bytes -> \(url.path)")
                    }
                } else {
                    print("renderFinal FAILED")
                }
            } else {
                print("union crop FAILED")
            }
        } catch {
            print("capture error: \(error)")
        }
        sem.signal()
    }
    // Pump the runloop (not a bare sem.wait) so AppKit calls that hop to
    // the main thread can complete.
    let deadline = Date().addingTimeInterval(45)
    while sem.wait(timeout: .now()) == .timedOut, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    exit(0)
}

// Headless demo recorder: `./SwiftShot --record <outdir>` renders the real
// capture→annotate pipeline into a PNG frame sequence (no windows opened).
if let i = CommandLine.arguments.firstIndex(of: "--record"),
   CommandLine.arguments.count > i + 1 {
    RecordDemo.run(outdir: CommandLine.arguments[i + 1])
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
