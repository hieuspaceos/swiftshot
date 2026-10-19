---
title: "Phase 4: Render & CPU Audit"
status: todo
---

# Phase 4: Render & CPU Audit

## Overview

Reduce wasteful redraws in overlay and editor; measure capture pipeline cost.

## Key suspects

| Suspect | File | Hypothesis |
|---------|------|------------|
| Full redraw on mouseMoved | `CaptureOverlay.swift` | `needsDisplay = true` repaints whole screen each mouse event → 60fps+ CPU |
| Full redraw on mouseDragged | `EditorWindow.swift` | same issue on canvas |
| Capture pipeline copy | `ScreenCapturer.swift` | `cropRegion` may composite all screens even for single display |
| `CGWindowListCreateImage` fallback | `ScreenCapturer.swift` | deprecated path — check if it's ever taken on macOS 15+ |

## Implementation Steps

1. Overlay: confirm `draw(_:)` repaints entire `bounds` every mouseMoved.
   - Fix target: `setNeedsDisplay(in: dirtyRect)` around crosshair +
     selection only, or move guide lines to a separate CAShapeLayer.
2. Editor: same treatment — invalidate only the dragged shape's rect.
3. Time `captureAllScreens()` + `cropRegion()` — if >150ms, profile which
   stage dominates.
4. Verify CGWindowList fallback only fires when SCScreenshotManager
   unavailable; if it can fire on macOS 15+, remove or gate it.
5. Record CPU % while dragging overlay for 10s (`top -pid`).

## Todo

- [x] Measure overlay redraw cost
- [x] Measure editor redraw cost
- [x] Profile capture pipeline stages
- [x] Confirm fallback path reachability

## Success Criteria

`reports/cpu-findings.md` lists redraw frequency + capture latency split.
