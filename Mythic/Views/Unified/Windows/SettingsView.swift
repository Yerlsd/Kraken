import Foundation
import SwiftUI

/// Native macOS settings workspace for Kraken.
/// Only controls backed by real Kraken state are exposed here; game-specific
/// runtime and launch configuration stays in the game's own settings window.
struct SettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case library = "Library"
        case downloads = "Downloads"
        case updates = "Updates"
        case services = "Services"
        case engine = "Engine"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .library: "square.grid.2x2"
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
        } detail: {
            ScrollView {
                Form {
                    switch selection {
                    case .general: GeneralSettings()
                    case .library: LibrarySettings()
                    case .downloads: DownloadSettings()
                    case .updates: UpdateSettings()
                    case .services: ServiceSettings()
                    case .engine: EngineSettings()
                    }
                }
                .formStyle(.grouped)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(selection.rawValue)
        }
        .frame(minWidth: 760, minHeight: 520)
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
        Section {
            LabeledContent("Application") {
                Text("Kraken")
            }
            LabeledContent("Purpose") {
                Text("Windows gaming on macOS")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Kraken")
        }

        Section {
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
        } header: {
            Text("Reset")
        }
    }
}

private struct LibrarySettings: View {
    @CodableAppStorage("gameListLayout") private var gameListLayout: GameListViewModel.Layout = .grid
    @AppStorage("libraryArtworkGlow") private var artworkGlow = true

    var body: some View {
        Section {
            Picker("Default library layout", selection: $gameListLayout) {
                Text("Grid").tag(GameListViewModel.Layout.grid)
                Text("List").tag(GameListViewModel.Layout.list)
            }

            Toggle("Artwork depth and hover glow", isOn: $artworkGlow)
        } header: {
            Text("Library appearance")
        }

        Section {
            Text("The library automatically adapts its columns to the available window width. Game-specific artwork and launch settings can be changed from each game's menu.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DownloadSettings: View {
    @AppStorage("installBaseURL") private var installBaseURL: URL = Bundle.appGames!
    @State private var importerPresented = false

    var body: some View {
        Section {
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
                Button("Choose Folder…") { importerPresented = true }
                    .buttonStyle(.borderedProminent)
                Button("Reset") { installBaseURL = Bundle.appGames! }
            }
            .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    installBaseURL = url
                }
            }
        } header: {
            Text("Game installation")
        }
    }
}

private struct UpdateSettings: View {
    var body: some View {
        Section {
            Button("Check for Kraken Updates…", systemImage: "arrow.down.app") {
                SparkleUpdateController.shared.checkForUpdates(userInitiated: true)
            }

            Button("Check for Compatibility Engine Updates…", systemImage: "arrow.down.app.dashed") {
                Task(priority: .userInitiated) {
                    await Engine.displayUpdateChecker(userInitiated: true)
                }
            }
        } header: {
            Text("Updates")
        }

        Section {
            Text("Kraken keeps application updates separate from the compatibility engine so game support can evolve independently.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ServiceSettings: View {
    @AppStorage("discordRPC") private var discordRPCEnabled = true

    var body: some View {
        Section {
            Toggle("Show Kraken activity on Discord", systemImage: "bubble.left.and.bubble.right", isOn: $discordRPCEnabled)
                .disabled(!discordRPC.isDiscordInstalled)
                .onChange(of: discordRPCEnabled) { _, enabled in
                    if enabled {
                        _ = discordRPC.connect()
                    } else {
                        discordRPC.disconnect()
                    }
                }
        } header: {
            Text("Discord")
        }

        Section {
            Text("Epic account authentication and Steam discovery are managed from Accounts. Kraken does not store a Steam web password.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Store services")
        }
    }
}

private struct EngineSettings: View {
    @State private var forceQuitRunning = false
    @State private var purgeShaders = false
    @State private var removeAlert = false
    @State private var removeEngine = false
    @State private var engineVersion: String?

    var body: some View {
        if Engine.isInstalled {
            Section {
                LabeledContent("Installed version") {
                    Text(engineVersion ?? "Checking…")
                        .foregroundStyle(.secondary)
                }

                Button("Force Quit Windows Applications", systemImage: "xmark.app") {
                    forceQuitRunning = true
                    do {
                        try Wine.killAll()
                    } catch {
                        forceQuitRunning = false
                    }
                }
                .disabled(forceQuitRunning)
            } header: {
                Text("Compatibility engine")
            }

            Section {
                Button("Purge D3DMetal Shader Cache", systemImage: "square.stack.3d.up.slash") {
                    purgeShaders = true
                    _ = try? Wine.purgeD3DMetalShaderCache()
                    purgeShaders = false
                }
                .disabled(purgeShaders)

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
            } header: {
                Text("Advanced")
            }
            .task {
                let version = await Engine.installedVersion
                engineVersion = version?.prettyString
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
