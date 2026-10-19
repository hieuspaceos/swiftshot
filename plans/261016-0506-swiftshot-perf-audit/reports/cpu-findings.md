# CPU / Render Findings — static audit 2026-10-16

## Confirmed issues

| # | Finding | File:line | Cost |
|---|---------|-----------|------|
| C1 | `OverlayContentView.mouseMoved` → `needsDisplay = true` → full `draw(_:)` repaints entire screen bitmap + dim fill every mouse event (display rate). Draw cost per frame = full-screen image blit ~5-10ms | `CaptureOverlay.swift:189` | sustained CPU while moving mouse in overlay |
| C2 | `EditorCanvasView.mouseDragged` → `needsDisplay = true` → redraws base image + all shapes every event | `EditorWindow.swift:336` | CPU during annotation drag; scales with shape count |
| C3 | `cropRegion` compositing: verify whether it allocates a new full-union bitmap for single-screen crops (likely yes via CGContext draw) | `Utilities.swift` (cropRegion) | ~1 frame alloc per capture |
| C4 | CGWindowList fallback reachable on macOS 15+ whenever `captureSCK` throws (try?) — silently masks SCK errors AND uses deprecated API | `ScreenCapturer.swift:36-37` | correctness risk, not perf |

## Verified

- `mouseMoved`/`mouseDragged`/`mouseUp`/`keyDown` all invalidate full bounds — no dirty-rect usage anywhere (0 hits for `setNeedsDisplay(in:`)

## Recommended fixes (Phase 5)

1. Overlay: throttle mouseMoved redraws to ~30fps AND/OR split guides into a
   cheap overlay CAShapeLayer so draw() doesn't re-blit the screen image
   (biggest win: keep `shots` blit, draw dim+guides via layers)
   — simpler: skip redraw if nothing except mouse position changed and only
   the guide labels moved? Position label DOES depend on mouse → still needs
   redraw. Best: NSWindow-level — set `contentView.layer` backed, use
   `wantsLayer` + move crosshair lines into layers updated without draw().
   Pragmatic alternative: coalesce mouseMoved via 16ms timer.
2. Editor: `setNeedsDisplay(in:)` on the union of old+new draft rect during
   drag; full redraw only on commit/undo.
3. C3: single-shot fast path — if crop rect ⊂ one shot's frame, crop that
   CGImage directly instead of compositing.
4. C4: log when fallback fires; gate to <macOS 15 or keep as last resort
   with NSLog.
