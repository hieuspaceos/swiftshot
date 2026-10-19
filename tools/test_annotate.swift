import Cocoa
import Vision

// Test: OCR an image, find text matching a query, draw a red ellipse
// around the best match, write result to /tmp/swiftshot-annotated.png.
// Usage: swift test_annotate.swift <image> <query> [out]

guard CommandLine.arguments.count >= 3 else {
    print("usage: test_annotate.swift <image> <query> [out]")
    exit(1)
}
let imgPath = CommandLine.arguments[1]
let query = CommandLine.arguments[2].lowercased()
let outPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "/tmp/swiftshot-annotated.png"

guard let img = NSImage(contentsOfFile: imgPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("cannot load \(imgPath)")
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: img, options: [:])
try handler.perform([request])

let observations = (request.results ?? [])
// Match: observation's top candidate contains the query (or vice versa)
struct Hit { let rect: CGRect; let text: String; let score: Float }
var hits: [Hit] = []
for obs in observations {
    guard let cand = obs.topCandidates(1).first else { continue }
    let t = cand.string.lowercased()
    if t.contains(query) || query.contains(t) {
        hits.append(Hit(rect: obs.boundingBox, text: cand.string, score: cand.confidence))
    }
}
print("observations: \(observations.count), hits: \(hits.count)")
for h in hits { print("  hit '\(h.text)' box=\(h.rect)") }

// Draw: original + red ellipse around each hit (Vision y is bottom-up)
let w = img.width, h = img.height
let ctx = CGContext(data: nil, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
ctx.setLineWidth(CGFloat(max(w, h)) / 400)
for hit in hits {
    let r = hit.rect
    let px = CGRect(x: r.minX * CGFloat(w), y: r.minY * CGFloat(h),
                    width: r.width * CGFloat(w), height: r.height * CGFloat(h)).insetBy(dx: -8, dy: -8)
    ctx.strokeEllipse(in: px)
}
if let out = ctx.makeImage() {
    let rep = NSBitmapImageRep(cgImage: out)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
}
