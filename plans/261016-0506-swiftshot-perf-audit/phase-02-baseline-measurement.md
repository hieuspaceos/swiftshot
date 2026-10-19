---
title: "Phase 2: Baseline Measurement"
status: todo
---

# Phase 2: Baseline Measurement

## Overview

Measure real numbers before touching code. Every optimization claim later
must cite these baselines.

## Requirements

- [x] Idle RSS + footprint after fresh launch (5 min uptime)
- [x] RSS during overlay, during editor, after close
- [x] Leak report after 10 capture→edit→close cycles
- [x] Hotkey→overlay latency (timestamps)

## Implementation Steps

1. Launch app: `open Build/SwiftShot.app`, note PID.
2. Idle measure after 5 min:
   ```sh
   footprint <pid> | head -20
   vmmap -summary <pid> | grep -E 'TOTAL|CGImage|IOSurface'
   ```
3. Exercise: menu → Capture Region, drag, Enter → editor opens. Measure RSS
   at each stage.
4. Leak check:
   ```sh
   leaks <pid>
   MallocScribble=1 ./Build/SwiftShot.app/Contents/MacOS/SwiftShot &
   leaks <pid>  # after 10 cycles
   ```
5. Latency: add temporary `NSLog` timestamps at hotkey handler entry,
   `present()`, `openEditor()` — measure deltas in Console.app or
   `log stream --process SwiftShot`.
6. Record all numbers in a `reports/baseline.md` inside this plan dir.

## Todo

- [x] Idle RSS + footprint recorded
- [x] Per-stage RSS (overlay / editor / post-close)
- [x] leaks output saved
- [x] Latency numbers logged

## Success Criteria

`reports/baseline.md` exists with numbers for every requirement row.
