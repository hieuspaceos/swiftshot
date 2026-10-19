---
title: "SwiftShot perf optimization"
status: todo
goal: "Idle footprint ≤ 60 MB, hotkey→overlay < 120 ms, peak during edit < 250 MB"
---

# SwiftShot — Performance Optimization

Baseline (2026-10-19): idle ~108 MB, peak ~392 MB during capture+edit,
1.6 MB bundle. Audited against source — see corrections inline.

## Verified actions

### A. Hotkey → overlay latency
- [x] **Hoist `SCShareableContent` out of the per-screen loop** —
      `captureAllScreens` calls `capture(screen)` per `NSScreen`, and each
      `captureSCK` awaits `SCShareableContent.excludingDesktopWindows`
      (N XPC enumerations per capture). Enumerate once, match displays by
      `displayID`; optionally cache for ~2 s. Biggest latency win.
      (`Sources/ScreenCapturer.swift:14-24`)
- [x] **Cache the dimmed backdrop** — `OverlayContentView.draw(_:)` re-draws
      every screen's full-res CGImage + dim fill on every mouseMoved/drag.
      Composite once into a `CALayer`/`NSImage`, reuse during selection.
      (`Sources/CaptureOverlay.swift`)
- [x] Reuse the single union overlay window instead of rebuilding per
      capture (it's already one window over the union frame — just hide,
      don't dealloc).

### B. Editor peak (~392 MB)
- [x] **PNG-only pasteboard write** — `openEditor` calls
      `copyToPasteboard` synchronously before the editor appears, encoding
      PNG **plus an uncompressed TIFF** of the full capture — likely the
      single largest peak contributor. Write PNG only, or promise TIFF
      lazily via `NSPasteboardItem` provider.
      (`Sources/EditorWindow.swift:195-208`)
- [x] Cap undo stack at 20 entries. Note: shapes are already value-type
      `Drawable` structs — only `.mosaic` embeds a full-scale CGImage; no
      snapshot compression needed.

### C. Floating preview retention
- [x] Thumbnails are already downscaled (`downscale(..., thumbW*2)`) —
      real issue is `AppDelegate.previews` retaining each full-res CGImage
      (~30-70 MB on Retina) until dismiss, with **no cap**. Keep only the
      most recent preview's full-res image, or store a JPEG for reopen.

## Stale items — already done, remove

- ~~Defer `CGPreflightScreenCaptureAccess` to first hotkey~~ — already
  deferred; launch only calls `setupStatusItem()` + `registerHotkeys()`.
- ~~ScreenCapturer retains buffers~~ — `ScreenCapturer` is a stateless
  enum; it retains nothing. The retained bytes live in `previews` + pasteboard.

## Verify

```sh
PID=$(pgrep -x SwiftShot | head -1)
leaks -nostacks $PID
# latency: T0/T1/T2 signposts already instrumented; hotkey→overlay < 120 ms
instruments -t "Time Profiler" # 10× capture→edit→close
```

---

## Phase 2 — In-use peak reduction (target: editor ≤ ~100 MB, from ~154 MB)

Measured after phase 1 (Activity Monitor, editor open): ~154 MB.
Breakdown: ~30 MB full-res CGImage, ~23 MB composited dimmed backdrop,
mosaic strokes each embed a CGImage (undo ×20 → unbounded), previews
retain panel refs, all screens captured eagerly on overlay open.

Actions:
- [x] 1. **PNG-encode capture, drop the CGImage** — `ScreenCapturer` should
       hand `Data` (PNG bytes) to the editor and release the raw bitmap;
       editor decodes once on open. Frees ~25-30 MB between captures.
- [x] 2. **Cap mosaic bitmap entries at 5** — `.mosaic` is the only
       Drawable carrying a full-scale CGImage; bound those separately so
       the 20-deep undo stack can't retain ~400 MB worst case.
- [x] 3. **Half-res dimmed backdrop** — backdrop is a dimmed composite,
       never inspected at 1:1. Render `backdropImage()` at 1/2 backing
       scale; ~11 MB instead of ~23 MB.
- [x] 4. **Dismiss stale previews when editor opens** —
       `AppDelegate.previews` retains panel refs even after demoteFullImage;
       dismiss all but the triggering preview on `showEditor`.
- [x] 5. **Lazy per-screen capture** — `captureAllScreens` currently
       captures every display up-front for the overlay backdrop. Capture
       only the screen under the cursor immediately; fetch the rest
       asynchronously and update the backdrop when they arrive.

Verify: open editor on a 5K screenshot, footprint ≤ ~100 MB; undo stack of
20 mosaics stays bounded.
