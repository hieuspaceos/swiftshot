import Cocoa
import SwiftUI

/// Preferences window: SwiftUI view hosted in an AppKit window.
final class PreferencesWindow: NSWindow {

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 150),
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        self.title = "SwiftShot Preferences"
        self.isReleasedWhenClosed = false
        self.contentView = NSHostingView(rootView: PreferencesView())
        center()
    }
}

struct PreferencesView: View {
    @State private var saveDir: String = Preferences.saveDirectoryPath()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Save folder:")
                    .frame(width: 90, alignment: .trailing)
                Text(saveDir)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { chooseFolder() }
                Button("Reveal") { revealFolder() }
            }
            HStack {
                Spacer()
                Text("Launch at login: enable via System Settings → Login Items")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: saveDir)
        if panel.runModal() == .OK, let url = panel.url {
            saveDir = url.path
            Preferences.setSaveDirectoryPath(saveDir)
        }
    }

    private func revealFolder() {
        let url = URL(fileURLWithPath: saveDir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

enum Preferences {
    private static let key = "saveDirectory"

    static func saveDirectoryPath() -> String {
        defaultSaveDirectory().path
    }

    static func setSaveDirectoryPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: key)
    }
}
