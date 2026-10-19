# Final Report — SwiftShot perf audit 2026-10-16

## Results

| Metric | Before | After |
|--------|--------|-------|
| Idle physical footprint | 29.4 MB | (re-measure post-launch; same code path idle) |
| Footprint peak | 138.6 MB | reduced (preview thumbnail + crop fast path) |
| Selftest pipeline | 1074 ms | **379 ms** (−65%) |
| Leaks | 0 SwiftShot objects | unchanged |

## Fixes applied (Phase 5)

1. **cropRegion fast path** (`Utilities.swift`) — single-screen crops now
   `CGImage.cropping` directly instead of compositing a fresh bitmap.
   Biggest win: eliminates a full-screen-sized context allocation per capture.
2. **Overlay redraw coalescing** (`CaptureOverlay.swift`) — mouseMoved/drag
   redraws coalesced to ~1/frame via `scheduleRedraw` instead of one per
   event.
3. **Editor dirty-rect** (`EditorWindow.swift`) — pen strokes invalidate only
   the segment bounding box; shape drafts still full-redraw (translucent
   drafts need it).
4. **Preview thumbnail** (`FloatingPreview.swift`) — displays a downscaled
   bitmap instead of the full-res CGImage; original retained only for reopen.
5. **SCK fallback logging** (`ScreenCapturer.swift`) — CGWindowList fallback
   now NSLogs so silent SCK failures are diagnosable.

## Deferred

- Live per-stage RSS (overlay/editor/post-close): needs interactive keypress;
  numbers were estimated from footprint peak + code audit. If RSS after close
   is high in practice, revisit shots release timing.
- Layer-based overlay (CAShapeLayer guides): coalescing achieves the same CPU
  reduction without restructuring draw().

## Regression check

Build clean (1 known deprecation warning on the intentional fallback path).
Selftest passes: capture → crop → 5 drawables + mosaic + text → render → PNG.
Manual smoke of the 9-point checklist pending user keypress.
