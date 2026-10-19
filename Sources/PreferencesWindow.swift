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
    @State private var agentTarget: String = AgentPaste.preferredTargetID ?? ""
    @State private var runningTargets: [(id: String, name: String)] = []

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
                Text("Send to agent:")
                    .frame(width: 90, alignment: .trailing)
                Picker("", selection: $agentTarget) {
                    Text("Auto (last focused app)").tag("")
                    ForEach(runningTargets, id: \.id) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
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
        .onAppear { refreshTargets() }
        .onChange(of: agentTarget) { AgentPaste.preferredTargetID = $0.isEmpty ? nil : $0 }
    }

    private func refreshTargets() {
        runningTargets = AgentPaste.runningKnownTargets()
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.1 < $1.1 }
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
