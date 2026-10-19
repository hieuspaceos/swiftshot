---
title: "SwiftShot — Performance & RAM Audit"
description: "Audit and optimize SwiftShot menubar app: reduce idle RAM (~84MB → <50MB), capture latency (<300ms), and redraw CPU churn in overlay/editor."
status: pending
priority: P1
effort: "4-6h"
tags: [performance, memory, macos, appkit]
created: 2026-10-16
---

# SwiftShot — Performance & RAM Audit

## Overview

SwiftShot (menubar screenshot + annotation app, `swiftshot/`) idles at ~84MB
RAM and is unverified for leaks, latency, and redraw cost. This plan audits
the real hotspots and applies targeted fixes — no speculative refactoring.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Idle RAM < 50MB, no growth after 10 capture cycles | P1 |
| 2 | Hotkey → overlay visible < 300ms | P1 |
| 3 | Overlay/editor redraw only dirty rects, <5% CPU while idle | P2 |
| 4 | Zero leaked CGImage/NSWindow instances | P1 |

## Baseline (measured 2026-10-16)

| Metric | Value |
|--------|-------|
| Idle RSS | ~84 MB |
| Swift version | 6.4, target arm64-macosx14.0 |
| Key files | `ScreenCapturer.swift`, `CaptureOverlay.swift`, `EditorWindow.swift`, `FloatingPreview.swift`, `AppDelegate.swift`, `Utilities.swift` |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 2 | [Baseline Measurement](./phase-02-baseline-measurement.md) | Pending |
| 3 | [Memory Audit](./phase-03-memory-audit.md) | Pending |
| 4 | [Render & CPU Audit](./phase-04-render-cpu-audit.md) | Pending |
| 5 | [Apply Fixes](./phase-05-apply-fixes.md) | Pending |
| 6 | [Verify & Regression](./phase-06-verify-regression.md) | Pending |

## Known suspects (from code review)

- `ScreenCapturer.captureAllScreens()` holds full-res @2x CGImage per display (~23MB each); `shots` array retained through overlay lifetime.
- `FloatingPreviewPanel` likely keeps full-size CGImage instead of downscaled thumbnail.
- `OverlayContentView.needsDisplay = true` on every `mouseMoved` → full-screen bitmap redraw at mouse-event rate.
- `EditorCanvasView` likely same full-redraw on `mouseDragged`.
- `editors`/`previews` arrays in AppDelegate — verify removal on close.
- Undo stack retains shape array (cheap) — verify no CGImage copies.

## Success Criteria

- [ ] `footprint` idle < 50MB after 5min runtime
- [ ] `leaks` reports 0 leaked CGImage/NSWindow after 10 capture+editor cycles
- [ ] Overlay CPU < 5% while moving mouse without drag
- [ ] Capture → editor open < 300ms on M-series
- [ ] All features still work: ⌥⇧4/⌥⇧3, annotate, copy, save, preview

<!-- slug: swiftshot-perf-audit -->
