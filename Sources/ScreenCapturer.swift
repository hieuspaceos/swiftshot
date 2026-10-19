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

    /// Capture every connected screen. Throws CaptureError.permissionDenied
    /// when Screen Recording permission is missing.
    static func captureAllScreens() async throws -> [ScreenShot] {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        var shots: [ScreenShot] = []
        for screen in NSScreen.screens {
            if let shot = try await capture(screen) {
                shots.append(shot)
            }
        }
        if shots.isEmpty {
            if !CGPreflightScreenCaptureAccess() { throw CaptureError.permissionDenied }
            throw CaptureError.failed("Screen capture returned no images")
        }
        return shots
    }

    static func capture(_ screen: NSScreen) async throws -> ScreenShot? {
        if #available(macOS 15.0, *) {
            if let shot = try? await captureSCK(screen) { return shot }
            NSLog("SwiftShot: SCScreenshotManager failed for screen, using CGWindowList fallback")
            return try captureLegacy(screen)
        } else {
            return try captureLegacy(screen)
        }
    }

    @available(macOS 15.0, *)
    private static func captureSCK(_ screen: NSScreen) async throws -> ScreenShot? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let displayID = screenDisplayID(screen)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return ScreenShot(image: img, scale: screen.backingScaleFactor, frame: screen.frame)
    }

    private static func captureLegacy(_ screen: NSScreen) throws -> ScreenShot? {
        let rect = cgScreenRect(for: screen)
        guard let img = CGWindowListCreateImage(rect, .optionOnScreenOnly,
                                                kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution])
        else { return nil }
        let scale = CGFloat(img.width) / rect.width
        return ScreenShot(image: img, scale: scale, frame: screen.frame)
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
