import Foundation
import SwiftUI
import SemanticVersion

/// Native macOS settings workspace for Kraken.
struct SettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case library = "Library"
        case launching = "Launching"
        case downloads = "Downloads"
        case updates = "Updates"
        case services = "Services"
        case engine = "Engine"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .library: "square.grid.2x2"
            case .launching: "play.circle"
            case .downloads: "arrow.down.circle"
            case .updates: "arrow.triangle.2.circlepath"
            case .services: "link"
            case .engine: "cpu"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            Form {
                switch selection {
                case .general:
                    GeneralSettings()
                case .library:
                    LibrarySettings()
                case .launching:
                    LaunchSettings()
                case .downloads:
                    DownloadSettings()
                case .updates:
                    UpdateSettings()
                case .services:
                    ServiceSettings()
                case .engine:
                    EngineSettings()
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 520)
            .navigationTitle(selection.rawValue)
        }
        .frame(minWidth: 760, minHeight: 500)
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Configuring Kraken"
                presence.state = "Settings"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }
}

private struct GeneralSettings: View {
    @State private var resetAlert = false
    @State private var resetSettingsAlert = false

    var body: some View {
        Section("Kraken") {
            LabeledContent("About this app") {
                Text("Windows gaming on macOS")
                    .foregroundStyle(.secondary)
            }

            Button("Reset settings to default", systemImage: "arrow.counterclockwise") {
                resetSettingsAlert = true
            }
            .alert("Reset Kraken Settings?", isPresented: $resetSettingsAlert) {
                Button("Reset", role: .destructive) {
                    if let bundleIdentifier = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes saved preferences but leaves your games and containers alone.")
            }

            Button("Reset Kraken completely", systemImage: "trash") {
                resetAlert = true
            }
            .foregroundStyle(.red)
            .alert("Reset Kraken completely?", isPresented: $resetAlert) {
                Button("Erase Everything", role: .destructive) {
                    if let bundleIdentifier = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
                    }
                    if let appHome = Bundle.appHome {
                        try? FileManager.default.removeItem(at: appHome)
                    }
                    if let containersDirectory = Wine.containersDirectory {
                        try? FileManager.default.removeItem(at: containersDirectory)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This erases Kraken's persistent settings and containers.")
            }
        }
    }
}

private struct LibrarySettings: View {
    @AppStorage("gameCardSize") private var gameCardSize: Double = 220
    @AppStorage("gameImageCardBlur") private var imageCardBlur: Double = 0
    @CodableAppStorage("gameListLayout") private var gameListLayout: GameListViewModel.Layout = .grid

    var body: some View {
        Section("Library appearance") {
            Slider(value: $gameCardSize, in: 180...360, step: 10) {
                Label("Game card size", systemImage: "rectangle.resize")
            } minimumValueLabel: {
                Text("Small").font(.caption)
            } maximumValueLabel: {
                Text("Large").font(.caption)
            }

            Slider(value: $imageCardBlur, in: 0...20, step: 5) {
                Label("Artwork glow", systemImage: "sparkles")
            } minimumValueLabel: {
                Text("Off").font(.caption)
            } maximumValueLabel: {
                Text("Strong").font(.caption)
            }

            Picker("Default library layout", selection: $gameListLayout) {
                Text("Grid").tag(GameListViewModel.Layout.grid)
                Text("List").tag(GameListViewModel.Layout.list)
            }
        }

        Section {
            Text("The library automatically adapts the number of columns to the window width. Nothing is pinned to a fixed number of cards per row.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LaunchSettings: View {
    @AppStorage("minimiseOnGameLaunch") private var minimiseOnLaunch = false
    @AppStorage("quitOnAppClose") private var quitOnClose = false

    var body: some View {
        Section("When launching a game") {
            Toggle("Minimise Kraken to the Dock", systemImage: "dock.arrow.down.rectangle", isOn: $minimiseOnLaunch)
            Toggle("Quit games when Kraken closes", systemImage: "xmark.app", isOn: $quitOnClose)
        }

        Section {
            Text("Game-specific runtime, container, graphics and launch arguments live in the game's own Settings window.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DownloadSettings: View {
    @AppStorage("installBaseURL") private var installBaseURL: URL = Bundle.appGames!
    @State private var importerPresented = false

    var body: some View {
        Section("Game installation") {
            LabeledContent("Default install location") {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(installBaseURL.prettyPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !FileLocations.isWritableFolder(url: installBaseURL) {
                        Label("Folder is not writable", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Choose Folder…") {
                    importerPresented = true
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    installBaseURL = Bundle.appGames!
                }
            }
            .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    installBaseURL = url
                }
            }
        }
    }
}

private struct UpdateSettings: View {
    @AppStorage("engineChannel") private var engineChannel: String = Engine.ReleaseChannel.stable.rawValue
    @AppStorage("engineAutomaticallyChecksForUpdates") private var automaticEngineUpdates = true
    @State private var changeAlert = false

    var body: some View {
        Section("Kraken") {
            Button("Check for Kraken Updates…", systemImage: "arrow.down.app") {
                SparkleUpdateController.shared.checkForUpdates(userInitiated: true)
            }
        }

        Section("Compatibility Engine") {
            Picker("Release channel", selection: $engineChannel) {
                Text("Stable").tag(Engine.ReleaseChannel.stable.rawValue)
                Text("Preview").tag(Engine.ReleaseChannel.preview.rawValue)
            }
            .onChange(of: engineChannel) {
                changeAlert = true
            }

            Toggle("Automatically check for engine updates", systemImage: "arrow.down.app.dashed", isOn: $automaticEngineUpdates)
        }
        .alert("Reinstall engine?", isPresented: $changeAlert) {
            Button("Reinstall", role: .destructive) {
                Task { @MainActor in
                    try? await Engine.remove()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Changing the release channel requires the current engine installation to be removed first.")
        }
    }
}

private struct ServiceSettings: View {
    @AppStorage("discordRPC") private var discordRPCEnabled = true

    var body: some View {
        Section("Discord") {
            Toggle("Show Kraken activity on Discord", systemImage: "bubble.left.and.bubble.right", isOn: $discordRPCEnabled)
                .disabled(!discordRPC.isDiscordInstalled)
                .onChange(of: discordRPCEnabled) { _, enabled in
                    if enabled {
                        _ = discordRPC.connect()
                    } else {
                        discordRPC.disconnect()
                    }
                }
        }

        Section("Epic Games") {
            Text("Epic account authentication and cloud-save operations are managed from the Accounts page.")
                .foregroundStyle(.secondary)
        }

        Section("Steam") {
            Text("Steam games are discovered from the local Steam installation. A separate Steam web login is not currently required.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct EngineSettings: View {
    @State private var forceQuitRunning = false
    @State private var removeEngine = false
    @State private var purgeShaders = false
    @State private var removeAlert = false
    @State private var engineVersion: SemanticVersion?

    var body: some View {
        if Engine.isInstalled {
            Section("Compatibility engine") {
                Button("Force Quit Windows Applications", systemImage: "xmark.app") {
                    forceQuitRunning = true
                    do {
                        try Wine.killAll()
                    } catch {
                        forceQuitRunning = false
                    }
                }
                .disabled(forceQuitRunning)

                Button("Remove Compatibility Engine", systemImage: "trash") {
                    removeAlert = true
                }
                .foregroundStyle(.red)
                .alert("Remove Compatibility Engine?", isPresented: $removeAlert) {
                    Button("Remove", role: .destructive) {
                        removeEngine = true
                        Task { @MainActor in
                            try? await Engine.remove()
                            removeEngine = false
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Windows games will not launch until a compatibility engine is installed again.")
                }
            }

            Section("Advanced") {
                Button("Purge D3DMetal Shader Cache", systemImage: "square.stack.3d.up.slash") {
                    purgeShaders = true
                    _ = try? Wine.purgeD3DMetalShaderCache()
                    purgeShaders = false
                }
                .disabled(purgeShaders)

                LabeledContent("Installed version") {
                    Text(engineVersion?.prettyString ?? "Checking…")
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                engineVersion = await Engine.installedVersion
            }
        } else {
            Engine.NotInstalledView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}

#Preview {
    SettingsView()
}
