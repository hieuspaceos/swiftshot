# SwiftShot

A CleanShot X–lite screenshot utility for macOS. Menubar agent app (no Dock icon),
built with AppKit + SwiftUI, ScreenCaptureKit, CoreGraphics and Carbon hotkeys.
No third-party dependencies.

## Install

**Homebrew (recommended)**

```sh
brew tap hieuspaceos/suite && brew trust hieuspaceos/suite
brew install --cask swiftshot
```

**Manual** — grab the DMG from
[Releases](https://github.com/hieuspaceos/swiftshot/releases/latest), drag into
/Applications, right-click → Open once (ad-hoc signed).

## Features

- **Capture Region** — fullscreen dimmed overlay across all displays; drag a
  rubber-band selection, click inside it or press **⏎** to confirm, **⎋** to cancel.
- **Capture Fullscreen** — captures every connected display as one image.
- **Editor** — annotate before saving:
  - Pen (freehand), Arrow, Rectangle, Ellipse, translucent Highlight,
    Mosaic (pixelate region), Text (click to place, type, Enter/click to commit).
  - 7 preset colors, stroke-width slider, Undo (⌘Z), Cancel (⎋).
- **Agent button** — saves the PNG to the save folder, puts image + file
  URL + path on the clipboard, returns focus to the app that was
  frontmost at capture time (or a chosen target: Terminal, iTerm2,
  Ghostty, Warp, VSCode, Cursor — set in Preferences), and synthesizes
  ⌘V so the shot lands at the prompt. Built for CLI agents
  (omp/claude/codex): terminals get the file path, editors get the image.
- **Floating preview** — after Copy/Save a thumbnail panel pins to the
  bottom-right corner; click to reopen the editor, × to dismiss,
  auto-fades after ~10 s (hover restores).
- **Hide Desktop Icons** — toggles `com.apple.finder CreateDesktop` and
  restarts Finder; menu item shows a checkmark while hidden.
- **Open Save Folder** / **Preferences…** (choose save folder) / **Quit**.

## Hotkeys

| Shortcut | Action |
|---|---|
| **⌃⇧4** | Capture Region |
| **⌃⇧3** | Capture Fullscreen |

Registered globally via Carbon `RegisterEventHotKey` — no Accessibility
permission needed.

## Install

Prebuilt app (arm64, macOS 14+):

1. Download **SwiftShot.zip** from the
   [latest release](https://github.com/hieuspaceos/swiftshot/releases/latest).
2. Unzip and drag `SwiftShot.app` into `/Applications`.
3. The app is ad-hoc signed — if Gatekeeper blocks it, right-click → Open,
   or run `xattr -dr com.apple.quarantine /Applications/SwiftShot.app`.
4. Launch; grant **Screen Recording** on first capture when prompted.

## Build from source

```sh
make            # builds Build/SwiftShot.app
make run        # build + open
make clean
```

Requires Xcode 27+ toolchain, arm64, deployment target macOS 14.

### Headless self-test

```sh
./Build/SwiftShot.app/Contents/MacOS/SwiftShot --selftest
```

Captures all screens, composites a union crop, renders every annotation type
(rect, arrow, highlight, mosaic, text) and writes the result to
`/tmp/swiftshot-selftest.png`. Useful for verifying the capture + render
pipeline without UI.


## Permissions

**Screen Recording** is required for capture. On the first capture attempt
macOS must grant permission; SwiftShot preflights with
`CGPreflightScreenCaptureAccess()` and shows an alert with a button that opens
*System Settings → Privacy & Security → Screen Recording*. Enable SwiftShot
there (quit & relaunch if prompted).

**Accessibility** is used only by the **Agent** button's auto-⌘V (posting
the keystroke into your terminal). macOS prompts on first use; without it
the Agent button still saves the file and fills the clipboard — you paste
manually.

## Default save location

`~/Pictures/SwiftShot`, filenames like `SwiftShot 2026-10-16 at 14.30.00.png`.
Changeable in Preferences.

## Notes / limitations

- Region selection commits on click-inside or Enter (CleanShot-style
  "click to confirm" after dragging).
- Launch-at-login is not bundled; enable via System Settings → Login Items.
- No screen recording/GIF, scrolling capture, OCR, or cloud upload.
## Security & trust

- **Open source** — every byte of the release binary is produced from the
  commit you can read, by GitHub Actions (see the workflow run linked in
  each release). No opaque build steps.
- **Checksums** — every release ships `SwiftShot.dmg.sha256`. Verify:
  ```sh
  shasum -a 256 SwiftShot.dmg
  ```
- **No telemetry, no account, no network calls** — the app works fully
  offline; nothing leaves your Mac.
- **Permissions** — SwiftShot asks for Screen Recording (System Settings → Privacy & Security → Screen Recording)
  and nothing else.
- **Ad-hoc signed** — not yet notarized (needs a paid Apple Developer
  account). On first launch macOS shows "cannot be opened because the
  developer cannot be verified" — right-click → **Open** once, then it
  runs normally forever after.
- **Prefer building yourself?** `git clone`, `make`, `make run` —
  no external dependencies, readable in one sitting.
