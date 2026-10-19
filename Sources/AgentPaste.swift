import Cocoa

/// "Send to agent" helper: remembers which app was frontmost before a
/// capture stole focus, then returns focus there and synthesizes ⌘V so
/// the shot lands at the prompt of a CLI agent (omp, claude, codex, …)
/// or an editor chat box.
///
/// Two fallbacks make the feature degrade gracefully:
///   - No target resolved → pasteboard still holds PNG + file URL +
///     path, so a manual ⌘V works.
///   - No Accessibility permission → the synthetic ⌘V is skipped
///     silently (same manual fallback).
enum AgentPaste {

    /// Bundle IDs we recognize as agent targets. Order defines the
    /// ranking used when "Auto" resolves a running app.
    static let knownTargetIDs: [String] = [
        // Agent frontends (not raw terminals) — paste lands in their
        // chat/prompt input.
        "com.stablyai.orca",                // Orca
        "com.mitchellh.ghostty",            // Ghostty
        "dev.warp.Warp-Stable",             // Warp
        "com.googlecode.iterm2",            // iTerm2
        "com.apple.Terminal",               // Terminal.app
        "com.todesktop.230313mzl4w4u92",    // Cursor
        "com.microsoft.VSCode",
    ]

    /// User override from Preferences: a bundle ID, or nil for Auto.
    static var preferredTargetID: String? {
        get { UserDefaults.standard.string(forKey: "agentTarget").flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue ?? "", forKey: "agentTarget") }
    }

    /// The GUI app that was frontmost when capture started — almost
    /// always the terminal where the user is talking to an agent.
    private(set) static var previousApp: NSRunningApplication?

    /// Running apps matching knownTargetIDs, for the Preferences picker.
    static func runningKnownTargets() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier.map(knownTargetIDs.contains) == true
        }
    }

    /// Call before presenting any window that takes focus (overlay or
    /// editor). Must run on the main thread.
    static func rememberFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        previousApp = front
    }

    /// Resolve where the shot should land:
    ///   1. Preferred target from Preferences, if that app is running.
    ///   2. The app that was frontmost at capture time.
    ///   3. Any running known terminal/editor (frontmost-order lookup).
    private static func resolveTarget() -> NSRunningApplication? {
        if let id = preferredTargetID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }),
           !app.isTerminated {
            NSLog("SwiftShot: agent target = pref \(id)")
            return app
        }
        if let prev = previousApp, !prev.isTerminated {
            NSLog("SwiftShot: agent target = frontmost \(prev.bundleIdentifier ?? "?")")
            return prev
        }
        // No recorded frontmost (e.g. capture triggered while our own
        // panel was key) — fall back to the first running known target.
        let fallback = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier.map(knownTargetIDs.contains) == true
        }
        NSLog("SwiftShot: agent target = fallback \(fallback?.bundleIdentifier ?? "none")")
        return fallback
    }

    /// Ask macOS for Accessibility once — shows the system prompt and
    /// opens Settings if the user wants to grant it later. Returning
    /// true means we can post keystrokes right away.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Re-activate the target, post ⌘V, then type the prompt text so it
    /// lands next to the pasted image. `explicit` comes from the
    /// ⌥-click picker and wins over Preferences/Auto for this paste.
    /// If Accessibility is missing we trigger the system prompt once —
    /// the shot is already on the pasteboard so a manual ⌘V works either
    /// way.
    static func paste(into explicit: NSRunningApplication? = nil, prompt: String? = nil) {
        guard let app = explicit ?? resolveTarget() else { return }
        app.activate(options: [])
        guard ensureAccessibility(prompt: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            postCmdV()
            if let prompt, !prompt.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    typePrompt(prompt)
                    // Submit: prompt+shot already sitting at the agent's
                    // input — ⏎ sends it without the user reaching for
                    // the keyboard.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        postReturn()
                    }
                }
            }
        }
    }

    /// Types text by second paste: System Events "keystroke" can't
    /// produce Vietnamese diacritics, so we stash the prompt on a second
    /// pasteboard write and ⌘V again. A short delay separates the two
    /// pastes so the target doesn't see them as one.
    private static func typePrompt(_ prompt: String) {
        let pb = NSPasteboard.general
        // Save current pasteboard items (the image paste) to restore after.
        let saved = pb.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        pb.clearContents()
        pb.setString(" " + prompt, forType: .string)
        postCmdV()

        // Restore the image clipboard after a beat so the second ⌘V
        // has already been consumed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard !saved.isEmpty else { return }
            pb.clearContents()
            for (type, data) in saved {
                pb.setData(data, forType: type)
            }
        }
    }

    private static func postCmdV() {
        // kVK_ANSI_V = 9
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postReturn() {
        // kVK_Return = 36 — submits the agent prompt after paste+prompt.
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
