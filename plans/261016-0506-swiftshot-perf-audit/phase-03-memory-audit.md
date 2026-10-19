---
title: "Phase 3: Memory Audit"
status: todo
---

# Phase 3: Memory Audit

## Overview

Static review + runtime tracing of every large allocation: CGImage frames,
NSWindow backing stores, undo stacks, preview thumbnails.

## Key suspects

| Suspect | File | Hypothesis |
|---------|------|------------|
| Full-res captures retained | `ScreenCapturer.swift` | `[ScreenShot]` array lives through overlay AND editor; release after commit |
| Floating preview full-res | `FloatingPreview.swift` | thumbnail should downscale to ≤300px before display |
| Editors never freed | `AppDelegate.swift` | `editors` array may retain closed windows |
| Undo stack CGImages | `EditorWindow.swift` | stack should hold `Drawable` value types only |
| Overlay backing store | `CaptureOverlay.swift` | fullscreen window = ~23MB layer; verify `orderOut` frees it |

## Implementation Steps

1. Grep for `CGImage`, `NSImage`, `NSBitmapImageRep` lifetime: who retains, when released.
2. `vmmap <pid>` during overlay → confirm image bytes freed after `orderOut`.
3. Check `editors.removeAll` / `previews.removeAll` actually run (NSWindowDelegate `windowWillClose`).
4. Check undo stack: `Drawable` enum should be value type; confirm no
   `[CGImage]` snapshots.
5. Preview: find `renderFinal` call → verify it downscales for thumbnail.
6. Write `reports/memory-findings.md` with file:line per confirmed leak.

## Todo

- [x] Trace shots array lifetime
- [x] Verify editor/preview dealloc
- [x] Verify undo stack is shapes-only
- [x] Confirm preview downscales
- [x] List findings with file:line

## Success Criteria

`reports/memory-findings.md` lists each confirmed leak or "no leak — verified"
with evidence.
