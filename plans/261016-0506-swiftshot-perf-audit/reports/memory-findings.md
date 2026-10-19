# Memory Findings — static audit 2026-10-16

## Confirmed issues

| # | Finding | File:line | Cost |
|---|---------|-----------|------|
| M1 | FloatingPreviewPanel retains full-res CGImage for entire preview life (until dismiss) — needed for reopen, but a bitmap ~23MB @2x sits in RAM doing nothing | `FloatingPreview.swift:10,14` | ~5-23MB per preview |
| M2 | `shots` array (full-screen bitmaps) lives in the overlay-commit closure: `overlay.onCommit` captures `shots` strongly → closure + shots retained until overlay dealloc — OK — BUT `cropRegion` re-composites all shots even for single-screen/within-screen crops (see C3) | `AppDelegate.swift:185-189`, `Utilities.swift` | extra bitmap copy per crop |
| M3 | Editor holds both `canvasView` NSImageView backing AND shapes re-rendered per draw — acceptable; but `mosaic` Drawable embeds a CGImage (small, region-sized — fine) | `Utilities.swift:65` | minor |

## Verified non-issues

- `editors` array: `onFinish` removes; `windowShouldClose` calls `onFinish(nil)` → no leak path (EditorWindow.swift:216-229)
- `previews` array: `onDismiss` removes; close button fires it (FloatingPreview.swift:105-109); fade only dims to 0.3 — panel stays (by design)
- Undo stack: `shapes: [Drawable]` value types; only `.mosaic` carries CGImage (region-sized, not full screen) — acceptable
- Overlay `orderOut` + `self.overlay = nil` on commit/cancel → window + backing released (AppDelegate.swift:187,193)
- No retain cycles found: all closures capture `[weak self]`/`[weak editor]`/`[weak panel]`

## Recommendation

M1: keep full CGImage but ALSO store downscaled thumbnail for display —
NSImageView currently wraps the full image. Cheaper: render thumb CGImage
once at init, display that; keep original only for reopen path. Or accept
since preview is transient. **Decision: apply thumbnail-for-display fix
(display bitmap small), keep original for reopen.**
