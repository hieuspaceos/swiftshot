---
title: "Phase 6: Verify & Regression"
status: todo
---

# Phase 6: Verify & Regression

## Overview

Re-measure against Phase 2 baselines; confirm no feature regressions.

## Implementation Steps

1. `make clean && make` → 0 errors.
2. Relaunch; idle 5min → `footprint` compare vs baseline.
3. 10× capture→edit→close cycles → `leaks` must report 0.
4. Functional smoke:
   - [ ] ⌥⇧4 → overlay → drag → Enter → editor
   - [ ] ⌥⇧3 → editor opens fullscreen capture
   - [ ] Each tool draws: pen, arrow, rect, ellipse, HL, mosaic, text
   - [ ] Undo works (⌘Z)
   - [ ] Copy → paste into another app
   - [ ] Save → file appears in `~/Pictures/SwiftShot`
   - [ ] Floating preview appears, draggable, closes
   - [ ] Hide Desktop Icons toggle works
   - [ ] Menubar menu: all items respond
5. Update `README.md` performance section if numbers changed materially.
6. Reinstall: `cp -R Build/SwiftShot.app /Applications/`.

## Todo

- [ ] Idle footprint <50MB or documented reason
- [ ] Zero leaks over 10 cycles
- [ ] All functional checks pass
- [ ] Latency <300ms hotkey→overlay
- [ ] Installed app updated

## Success Criteria

Every checkbox passes; numbers written into `reports/final.md`.
