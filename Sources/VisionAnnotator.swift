import Cocoa
import Vision

/// Auto-annotation: finds text in a capture that matches the user's
/// prompt and draws attention marks (red ellipses) around the matches —
/// so "the Login button is broken" arrives at the agent with Login
/// already circled, no manual drawing needed.
enum VisionAnnotator {

    /// Runs on-device OCR (VNRecognizeTextRequest) and returns an
    /// annotated copy of `image` with ellipses around text matching
    /// `query`, or nil when nothing matches (caller sends the raw shot).
    /// Matching is loose: either side may contain the other, so
    /// "login" hits "Login to continue".
    static func annotate(image: CGImage, query rawQuery: String,
                         bestOnly: Bool = true) -> CGImage? {
        // One circle per term — "phone" → single spot; "input phone and
        // city" → a circle on phone and one on city. An ordinal
        // ("login 2") still picks the Nth match.
        let boxes = bestPerTerm(image: image, query: rawQuery)
        guard !boxes.isEmpty else { return nil }
        return drawEllipses(on: image, around: boxes)
    }

    /// Same matching as `annotate` but returns pixel-space rects instead
    /// of drawing. `bestOnly` picks the single highest-confidence match.
    /// A trailing number in the query ("login 2") is an ordinal: the Nth
    /// match counting top→bottom, left→right — so two "Login" buttons
    /// can be disambiguated by typing "login 2".
    static func matchRects(image: CGImage, query rawQuery: String,
                           bestOnly: Bool = false) -> [CGRect] {
        // Peel a trailing ordinal off the query before term extraction:
        // "login 2" → term "login", ordinal 2.
        var query = rawQuery.lowercased()
        var ordinal: Int? = nil
        if let m = query.range(of: #"\s+(\d+)$"#, options: .regularExpression),
           let n = Int(query[m].trimmingCharacters(in: .whitespaces)) {
            ordinal = n
            query = String(query[..<m.lowerBound])
        }
        let terms = extractTerms(from: query)
        guard !terms.isEmpty else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty
        else { return [] }

        let w = CGFloat(image.width), h = CGFloat(image.height)
        var rects: [(CGRect, Float)] = []
        for obs in observations {
            guard let cand = obs.topCandidates(1).first else { continue }
            let text = cand.string.lowercased()
            for term in terms where text.contains(term) || term.contains(text) {
                let score = text == term ? Float(2) : cand.confidence
                let subs = subRects(of: term, in: text, box: obs.boundingBox)
                for r in (subs.isEmpty ? [obs.boundingBox] : subs) {
                    rects.append((CGRect(x: r.minX * w, y: (1 - r.maxY) * h,
                                         width: r.width * w, height: r.height * h), score))
                }
            }
        }

        if let n = ordinal {
            // Reading order: top→bottom, left→right.
            let sorted = rects.sorted { a, b in
                abs(a.0.minY - b.0.minY) > 24 ? a.0.minY < b.0.minY
                                              : a.0.minX < b.0.minX
            }
            let idx = min(max(n, 1), sorted.count) - 1
            return idx >= 0 ? [sorted[idx].0] : []
        }
        if bestOnly, let top = rects.max(by: { $0.1 < $1.1 }) { return [top.0] }
        return rects.map { $0.0 }
    }

    /// One circle per extracted term: each term gets its own best
    /// match, so "input phone and city" circles phone AND city (two
    /// circles), while a lone "phone" still produces one.
    static func bestPerTerm(image: CGImage, query rawQuery: String) -> [CGRect] {
        let query = rawQuery.lowercased()
        let terms = extractTerms(from: query)
        guard !terms.isEmpty else { return [] }
        return terms.compactMap { term in
            matchRects(image: image, query: term, bestOnly: true).first
        }
    }

    /// Sub-rect for a term *inside* an observation's block — Vision only
    /// gives block-level boxes, so we locate the term's character range
    /// in the candidate string and slice the block horizontally (text
    /// flows left-to-right).
    private static func subRects(of term: String, in text: String, box: CGRect) -> [CGRect] {
        guard !term.isEmpty, let cand = text.range(of: term) else { return [] }
        let total = CGFloat(text.count)
        guard total > 1 else { return [] }
        let start = CGFloat(text.distance(from: text.startIndex, to: cand.lowerBound)) / total
        let len = CGFloat(term.count) / total
        let r = CGRect(x: box.minX + start * box.width, y: box.minY,
                       width: max(len * box.width, box.width / total), height: box.height)
        return [r]
    }

    private static func extractTerms(from query: String) -> [String] {
        var terms: [String] = []
        // Quoted phrases: "nút Login" → "login" treated as one term.
        var regex: NSRegularExpression?
        regex = try? NSRegularExpression(pattern: "\"([^\"]+)\"|'([^']+)'")
        let ns = query as NSString
        regex?.enumerateMatches(in: query, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            let t = ns.substring(with: r).trimmingCharacters(in: .whitespaces)
            if t.count >= 3 { terms.append(t) }
        }
        if !terms.isEmpty { return terms }
        // Fallback: significant words (≥3 chars), plus the whole query
        // when it's short — "ổn chưa" should still circle both words.
        var words = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        if query.count >= 2 && query.count <= 30 { words.insert(query, at: 0) }
        return Array(words.prefix(5)) // cap so prose prompts don't circle everything
    }

    private static func drawEllipses(on image: CGImage, around boxes: [CGRect]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setStrokeColor(CGColor(red: 1, green: 0.22, blue: 0.2, alpha: 1))
        ctx.setLineWidth(CGFloat(max(w, h)) / 400)
        for r in boxes {
            // `boxes` are now pixel-space, top-left origin — CGContext is
            // bottom-left, so flip Y.
            let px = CGRect(x: r.minX, y: CGFloat(h) - r.maxY,
                            width: r.width, height: r.height)
                .insetBy(dx: -10, dy: -10)
            ctx.strokeEllipse(in: px)
        }
        return ctx.makeImage()
    }
}
