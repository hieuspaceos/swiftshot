# Baseline — measured 2026-10-16

## Idle (pid 91127, ~40min uptime)

| Metric | Value |
|--------|-------|
| RSS (ps) | 82.3 MB |
| Physical footprint | 29.4 MB |
| Footprint peak | 138.6 MB (likely post-capture residue) |

Note: RSS vs footprint gap = clean/shared pages. Footprint is the number
that matters for "how much RAM is it using".

## Leaks (idle, before cycles)

`leaks` reports 417 leaks / ~20KB — all small XPC/dispatch framework noise
(AppIntents, LNProcessInstanceRegistryClient, _NSXPCConnection*), none in
SwiftShot objects. No CGImage/NSWindow/our-class leaks at idle.

## Capture pipeline (selftest, end-to-end)

`./SwiftShot --selftest` = 1074ms total, includes:
- SCScreenshotManager capture 2992×1934 @2x
- cropRegion union compositing
- 5 drawables + mosaic + text
- renderFinal → PNG encode 1.03MB + write

Per-stage latency (hotkey→overlay, overlay→editor) requires interactive
keypress — deferred; estimate <300ms given SCK capture is ~100-200ms of the
selftest total.

## Verdict

Idle memory is already good (29MB). The real wins are transient: per-capture
peak (138.6MB) and redraw CPU. See memory-findings.md / cpu-findings.md.
