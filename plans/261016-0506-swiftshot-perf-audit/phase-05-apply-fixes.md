---
title: "Phase 5: Apply Fixes"
status: todo
---

# Phase 5: Apply Fixes

## Overview

Apply only fixes justified by Phase 3–4 findings. No speculative work.

## Candidate fixes (apply only if finding confirms)

| # | Fix | Condition |
|---|-----|-----------|
| 1 | Downscale preview thumbnail to ≤300px before storing | If `FloatingPreviewPanel` keeps full CGImage |
| 2 | `setNeedsDisplay(in:)` dirty-rect in overlay + editor | If CPU >5% during drag |
| 3 | Release `shots` after overlay commit/cancel | If RSS stays high post-close |
| 4 | Explicit `editors`/`previews` removal on `windowWillClose` | If `leaks` shows NSWindow leaks |
| 5 | Remove/gate CGWindowList fallback | If unreachable on macOS 15+ |
| 6 | Cache rendered editor bitmap during drag | If editor redraw >16ms/frame |

## Implementation Steps

1. Order fixes by RAM impact (preview thumbnail → shots release → leaks).
2. Apply each fix in its own commit-able edit; keep `make` green after each.
3. For dirty-rect rendering: compute union of old+new crosshair lines and
   selection rect, pass to `setNeedsDisplay(in:)`.
4. For preview: `CGImage` → downscale via `CGContext` to thumbnail size,
   discard original.

## Todo

- [x] Preview thumbnail downscaled
- [x] Overlay dirty-rect redraw
- [x] Editor dirty-rect redraw
- [x] shots released after commit
- [x] editors/previews cleanup verified
- [x] CGWindowList fallback gated or removed

## Success Criteria

`make` clean; each applied fix has a matching finding in reports/.
