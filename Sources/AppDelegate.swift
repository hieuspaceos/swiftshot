import Cocoa
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlay: CaptureOverlayWindow?
    private var editors: [EditorWindow] = []
    private var previews: [FloatingPreviewPanel] = []
    private var pill: AgentPill?
    private var preferencesWindow: PreferencesWindow?

    // Carbon hotkey IDs
    private let kRegionHotkeyID: UInt32 = 1
    private let kFullscreenHotkeyID: UInt32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotkeys()
    }

    // MARK: - Status item & menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "SwiftShot")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let region = NSMenuItem(title: "Capture Region",
                                action: #selector(captureRegionMenu),
                                keyEquivalent: "4")
        region.target = self
        region.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(region)

        let full = NSMenuItem(title: "Capture Fullscreen",
                              action: #selector(captureFullscreenMenu),
                              keyEquivalent: "3")
        full.target = self
        full.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(full)

        menu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide Desktop Icons",
                              action: #selector(toggleDesktopIcons),
                              keyEquivalent: "")
        hide.target = self
        hide.state = Self.desktopIconsHidden() ? .on : .off
        menu.addItem(hide)

        let open = NSMenuItem(title: "Open Save Folder",
                              action: #selector(openSaveFolder),
                              keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(showPreferences),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SwiftShot",
                              action: #selector(quitApp),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Hotkeys  (⌥⇧4 region, ⌥⇧3 fullscreen — avoids macOS ⇧⌘/⌃⇧⌘ screenshot shortcuts)

    private func registerHotkeys() {
        let mods = UInt32(optionKey | shiftKey)
        HotkeyManager.shared.register(id: kRegionHotkeyID,
                                      keyCode: UInt32(kVK_ANSI_4),
                                      modifiers: mods) { [weak self] in
            NSLog("SwiftShot: T0 hotkey REGION fired")
            self?.captureRegion()
        }
        HotkeyManager.shared.register(id: kFullscreenHotkeyID,
                                      keyCode: UInt32(kVK_ANSI_3),
                                      modifiers: mods) { [weak self] in
            NSLog("SwiftShot: hotkey FULLSCREEN pressed")
            self?.captureFullscreen()
        }
    }

    // MARK: - Menu actions

    @objc private func captureRegionMenu() { captureRegion() }
    @objc private func captureFullscreenMenu() { captureFullscreen() }
    @objc private func openDonate() {
        NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/hieuspaceos")!)
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func toggleDesktopIcons() {
        let hidden = !Self.desktopIconsHidden()
        setDesktopIconsHidden(hidden)
        rebuildMenu()
    }

    @objc private func openSaveFolder() {
        let dir = defaultSaveDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Hide desktop icons

    private static func desktopIconsHidden() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "com.apple.finder", "CreateDesktop"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return out == "0" || out?.lowercased() == "false"
        } catch {
            return false
        }
    }

    private func setDesktopIconsHidden(_ hidden: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"]
        try? p.run()
        p.waitUntilExit()

        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        k.arguments = ["Finder"]
        try? k.run()
    }

    func captureRegion() {
        guard ScreenCapturer.checkPermissionOrAlert() else { return }
        AgentPaste.rememberFrontmostApp()
        let screens = NSScreen.screens
        // Lazy per-screen capture: only the display under the cursor is
        // captured before the overlay appears; the rest arrive via
        // patchOverlay so hotkey→overlay latency drops on multi-display
        // setups and uncaptured screens never pay the decode cost.
        let mouse = NSEvent.mouseLocation
        let cursorScreen = screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? screens.first
        guard let cursorScreen else {
            handleCaptureError(CaptureError.noScreens)
            return
        }
        Task { [weak self] in
            do {
                let cursorShot = try await ScreenCapturer.captureScreen(cursorScreen)
                await MainActor.run { [weak self] in
                    self?.showOverlay(screens: screens, cursorShot: cursorShot)
                }
                await self?.patchOverlay(screens: screens, cursorScreen: cursorScreen,
                                         cursorShot: cursorShot)
            } catch {
                await MainActor.run { [weak self] in self?.handleCaptureError(error) }
            }
        }
    }

    func captureFullscreen() {
        guard ScreenCapturer.checkPermissionOrAlert() else { return }
        AgentPaste.rememberFrontmostApp()
        Task { [weak self] in
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                await MainActor.run { [weak self] in self?.finishFullscreen(shots: shots) }
            } catch {
                await MainActor.run { [weak self] in self?.handleCaptureError(error) }
            }
        }
    }

    /// Fetch the non-cursor screens after the overlay is already up and
    /// patch them into the backdrop. Ignored if the session already ended.
    private func patchOverlay(screens: [NSScreen], cursorScreen: NSScreen,
                              cursorShot: ScreenShot?) async {
        let rest = screens.filter { screenDisplayID($0) != screenDisplayID(cursorScreen) }
        guard !rest.isEmpty else { return }
        guard let more = try? await ScreenCapturer.captureScreens(rest) else { return }
        await MainActor.run { [weak self] in
            guard let overlay = self?.overlay, overlay.isVisible else { return }
            overlay.updateShots((cursorShot.map { [$0] } ?? []) + more)
        }
    }

    private func showOverlay(screens: [NSScreen], cursorShot: ScreenShot?) {
        NSLog("SwiftShot: T1 overlay presenting (\(screens.count) screens)")
        // Reuse the single union overlay window across captures — it is only
        // hidden between sessions, not rebuilt. The union frame comes from
        // NSScreen geometry so the window is correct even though only the
        // cursor's screen has been captured so far.
        let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
        let frame = union.isNull ? (NSScreen.main?.frame ?? .zero) : union
        let shots = cursorShot.map { [$0] } ?? []
        let overlay = CaptureOverlayWindow.shared(frame: frame, shots: shots)
        self.overlay = overlay
        overlay.onCommit = { [weak self, weak overlay] region in
            guard let self, let overlay else { return }
            if let (image, scale) = cropRegion(region, from: overlay.currentShots) {
                self.openPill(image: image, scale: scale)
            }
        }
        overlay.onCancel = {} // shared window stays alive (hidden) for reuse
        overlay.present()
    }

    private func finishFullscreen(shots: [ScreenShot]) {
        let union = shots.reduce(CGRect.null) { $0.union($1.frame) }
        guard !union.isNull,
              let (image, scale) = cropRegion(union, from: shots) else {
            handleCaptureError(CaptureError.failed("Could not assemble fullscreen capture"))
            return
        }
        openPill(image: image, scale: scale)
    }

    // MARK: - Pill & editor

    /// The post-capture surface: a floating pill with a prompt field.
    /// ⏎ annotates (Vision OCR → ellipse around matching text) and
    /// delivers shot+prompt to the agent target; ✏️ opens the classic
    /// editor for manual annotation.
    private func openPill(image: CGImage, scale: CGFloat) {
        pill?.close() // dismiss a leftover pill from an earlier capture
        NSLog("SwiftShot: T2 pill opening \(image.width)x\(image.height)")
        for panel in previews { panel.dismiss() }
        EditorWindow.copyToPasteboard(image)
        let newPill = AgentPill(image: image, scale: scale)
        self.pill = newPill
        newPill.onCommit = { [weak self] out, prompt in
            self?.deliverCapture(image: out, prompt: prompt, scale: scale)
        }
        newPill.onEdit = { [weak self] raw in
            self?.openEditor(image: raw, scale: scale)
        }
        newPill.present()
    }

    /// Pill commit path: persist PNG, load the pasteboard with all
    /// representations, then focus the agent target and ⌘V. With a
    /// prompt we deliver `prompt + path` as the string so the agent sees
    /// the instruction and the image reference in one paste.
    private func deliverCapture(image: CGImage, prompt: String?, scale: CGFloat) {
        let dir = defaultSaveDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(defaultFileName(ext: "png"))
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        EditorWindow.copyForAgent(image: image, fileURL: url)
        AgentPaste.paste(prompt: prompt)
        showPreview(image: image, scale: scale)
    }

    // MARK: - Editor & preview

    private func openEditor(image: CGImage, scale: CGFloat) {
        NSLog("SwiftShot: T2 editor opening \(image.width)x\(image.height)")
        // Editing replaces floating previews — dismiss every panel so none
        // retains a full-res CGImage (or its demoted JPEG) while the
        // editor is open.
        for panel in previews { panel.dismiss() }
        // Copy immediately — the raw capture is on the pasteboard even if the
        // user never touches Copy in the editor.
        EditorWindow.copyToPasteboard(image)
        let shot = ScreenShot(image: image, scale: scale, frame: .zero)
        let editor = EditorWindow(shot: shot)
        editors.append(editor)
        editor.onFinish = { [weak self, weak editor] result in
            guard let self else { return }
            if let img = result {
                self.showPreview(image: img, scale: scale)
            }
            if let editor {
                self.editors.removeAll { $0 === editor }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        editor.makeKeyAndOrderFront(nil)
    }

    /// Full-res CGImages (~30–70 MB on Retina) are retained only for the
    /// most recent preview; older ones are demoted to JPEG for reopen, and
    /// the panel count itself is capped.
    private let maxPreviews = 5

    private func showPreview(image: CGImage, scale: CGFloat) {
        for panel in previews { panel.demoteFullImage() }
        while previews.count >= maxPreviews {
            previews.first?.dismiss()
        }
        let panel = FloatingPreviewPanel(image: image, scale: scale)
        previews.append(panel)
        panel.onReopen = { [weak self] img in
            self?.openEditor(image: img, scale: scale)
        }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.previews.removeAll { $0 === panel }
        }
        panel.show()
    }

    private func handleCaptureError(_ error: Error) {
        if case CaptureError.permissionDenied = error {
            ScreenCapturer.showPermissionAlert()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
