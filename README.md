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
/Applications and open (Developer ID signed + notarized).

## Features

- **Capture Region** — fullscreen dimmed overlay across all displays; drag a
  rubber-band selection, click inside it or press **⏎** to confirm, **⎋** to cancel.
- **Capture Fullscreen** — captures every connected display as one image.
- **Agent Pill** — after every capture a floating prompt pill appears at
  the cursor: type what the shot is about ("nút Login bị lỗi"), hit **⏎**
  → Vision OCR circles the matching text in the shot → image + prompt
  are pasted into your agent app and auto-submitted. No editor, no
  manual annotate — screenshot becomes a message.
- **Vision auto-annotate** — on-device OCR (`VNRecognizeTextRequest`)
  finds the term you typed and draws a red ellipse around it:
  - one circle per term — "phone" → single spot, "input phone and city"
    → a circle on each
  - ordinal: **"login 2"** circles the 2nd "login" (top→bottom,
    left→right)
  - quoted phrases: `"billing information"` matches the whole phrase
  - works fully offline, no Apple Intelligence/Siri needed
- **Editor** — floating HUD (borderless panel, no chrome):
  - Single-row toolbar: Copy / Save / Send-to-agent / Share icons,
    drawing tools (Pen, Arrow, Rect, Ellipse, Highlight, Mosaic, Text),
    7 colors, stroke slider, Undo — all visible at once
  - Inline prompt field with **live OCR preview**: dashed ellipse
    appears over the matching text as you type; ⏎ = annotate + send
  - Share button → macOS share sheet (Messages, AirDrop, Mail, and
    any chat app with a Share extension — Zalo/Messenger included)
- **Agent delivery** — paste lands where your agent lives:
  - Auto = app that was frontmost at capture, or pick a fixed target
    in Preferences / ⌥-click for a one-off choice (Terminal, iTerm2,
    Ghostty, Warp, VSCode, Cursor, Orca)
  - Image-capable targets get the real PNG; plain terminals get the
    file path; the prompt is typed as a second paste (Unicode-safe,
    Vietnamese diacritics intact) then ⏎ submits
- **Floating preview** — after delivery a thumbnail panel pins to the
  bottom-right corner; click to reopen the editor, × to dismiss,
  auto-fades after ~10 s (hover restores).
- **Hide Desktop Icons** — toggles `com.apple.finder CreateDesktop` and
  restarts Finder; menu item shows a checkmark while hidden.
- **Open Save Folder** / **Preferences…** (save folder + agent target)
  / **Quit**.

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
3. Launch; grant **Screen Recording** on first capture when prompted.

## Build from source

```sh
make            # builds Build/SwiftShot.app
make run        # build + open
make install    # build + copy to /Applications + relaunch
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

**Accessibility** is used by agent delivery (⌘V + typed prompt + ⏎ into
your terminal). macOS prompts on first use; without it the Agent path
still saves the file and fills the clipboard — you paste manually.

## Default save location

`~/Pictures/SwiftShot`, filenames like `SwiftShot 2026-10-16 at 14.30.00.png`.
Changeable in Preferences.

## Notes / limitations

- Region selection commits on click-inside or Enter (CleanShot-style
  "click to confirm" after dragging).
- Launch-at-login is not bundled; enable via System Settings → Login Items.
- No screen recording/GIF, scrolling capture, or cloud upload.
- OCR annotate matches *text visible in the shot* — it finds words, not
  meaning ("the broken button" won't resolve which button is broken).
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
- **Signed & notarized** — release builds are signed with a Developer ID
  certificate and notarized by Apple; macOS opens them with no Gatekeeper
  warning.
- **Prefer building yourself?** `git clone`, `make`, `make run` —
  no external dependencies, readable in one sitting.
