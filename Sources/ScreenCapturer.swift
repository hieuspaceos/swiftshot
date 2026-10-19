import Cocoa
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: Error {
    case permissionDenied
    case noScreens
    case failed(String)
}

/// Captures screen bitmaps using SCScreenshotManager on macOS 15+,
/// falling back to CGWindowListCreateImage on older systems.
enum ScreenCapturer {

    /// SCShareableContent enumeration goes over XPC and was the dominant
    /// per-capture latency: it is fetched once for all screens and reused
    /// for rapid successive captures (~2 s window).
    private static let contentLock = NSLock()
    private static var contentCache: (content: SCShareableContent, at: Date)?

    private static func shareableContent() async throws -> SCShareableContent {
        contentLock.lock()
        if let cached = contentCache, Date().timeIntervalSince(cached.at) < 2 {
            contentLock.unlock()
            return cached.content
        }
        contentLock.unlock()
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        contentLock.lock()
        contentCache = (content, Date())
        contentLock.unlock()
        return content
    }

    /// Capture every connected screen. Throws CaptureError.permissionDenied
    /// when Screen Recording permission is missing.
    static func captureAllScreens() async throws -> [ScreenShot] {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        return try await captureScreens(NSScreen.screens)
    }

    /// Capture a subset of screens (or a single one) — used by the lazy
    /// overlay path: cursor's screen first, the rest patched in async.
    @discardableResult
    static func captureScreens(_ screens: [NSScreen]) async throws -> [ScreenShot] {
        // Enumerate shareable content once up front instead of once per
        // screen inside captureSCK (N XPC round-trips -> 1).
        var shared: SCShareableContent?
        if #available(macOS 15.0, *) {
            shared = try? await shareableContent()
        }
        var shots: [ScreenShot] = []
        for screen in screens {
            if let shot = try await capture(screen, content: shared) {
                shots.append(shot)
            }
        }
        if shots.isEmpty, !screens.isEmpty {
            if !CGPreflightScreenCaptureAccess() { throw CaptureError.permissionDenied }
            throw CaptureError.failed("Screen capture returned no images")
        }
        return shots
    }

    /// Capture one screen; nil when the display can't be matched/captured.
    static func captureScreen(_ screen: NSScreen) async throws -> ScreenShot? {
        try await captureScreens([screen]).first
    }

    private static func capture(_ screen: NSScreen,
                                content shared: SCShareableContent?) async throws -> ScreenShot? {
        if #available(macOS 15.0, *), let shared {
            if let shot = try? await captureSCK(screen, content: shared) { return shot }
            NSLog("SwiftShot: SCScreenshotManager failed for screen, using CGWindowList fallback")
            return try captureLegacy(screen)
        } else {
            return try captureLegacy(screen)
        }
    }

    /// The CGImage is encoded to PNG immediately and only the bytes are
    /// retained, so the raw bitmap is released between capture and the
    /// editor's decode-on-open.
    @available(macOS 15.0, *)
    private static func captureSCK(_ screen: NSScreen,
                                   content: SCShareableContent) async throws -> ScreenShot? {
        let displayID = screenDisplayID(screen)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let shot = makeShot(img, screen: screen, scale: screen.backingScaleFactor) else { return nil }
        return shot
    }

    private static func captureLegacy(_ screen: NSScreen) throws -> ScreenShot? {
        let rect = cgScreenRect(for: screen)
        guard let img = CGWindowListCreateImage(rect, .optionOnScreenOnly,
                                                kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution])
        else { return nil }
        let scale = CGFloat(img.width) / rect.width
        return makeShot(img, screen: screen, scale: scale)
    }

    private static func makeShot(_ img: CGImage, screen: NSScreen, scale: CGFloat) -> ScreenShot? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return ScreenShot(pngData: data as Data, scale: scale, frame: screen.frame)
    }

    static func checkPermissionOrAlert() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        showPermissionAlert()
        return false
    }

    static func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "SwiftShot needs permission to record your screen.\n\nGrant it in System Settings → Privacy & Security → Screen Recording, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
