import SwiftUI
import AppKit
import SwordRPC
import Darwin

/// Per-game settings are deliberately presented as a native macOS workspace.
/// The sidebar separates the common actions from compatibility tuning so the
/// screen remains readable at both laptop and large-window sizes.
struct GameSettingsView: View {
    @Binding var game: Game
    @Binding var isPresented: Bool

    @Bindable private var operationManager: GameOperationManager = .shared

    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case launch = "Launch"
        case files = "Files"
        case compatibility = "Compatibility"
        case graphics = "Graphics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: "info.circle"
            case .launch: "play.circle"
            case .files: "folder"
            case .compatibility: "shippingbox"
            case .graphics: "display"
            }
        }
    }

    @State private var selection: Section = .overview
    @State private var movingError: Error?
    @State private var isMovingErrorAlertPresented = false
    @State private var isMovingFileImporterPresented = false
    @State private var typingArgument = ""
    @State private var isImageEmpty = true
    @State private var selectedRuntimeID: RuntimeID = .mythicEngine
    @State private var selectedGraphicsBackend: GraphicsBackend = .automatic
    @State private var storagePreflightResult: StoragePreflightResult?
    @State private var isCompatibilityOverrideEnabled = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Game Settings")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(game.storefront?.description ?? "Local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.bar)
            }
        } detail: {
            detailView
                .navigationTitle(selection.rawValue)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        GameCard.ButtonsView(game: $game, withLabel: true)
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task {
            selectedRuntimeID = game.launchProfile.effectiveRuntimeID
            selectedGraphicsBackend = game.launchProfile.graphicsBackend
            isCompatibilityOverrideEnabled = game.launchProfile.runtimeOverride != nil
            ensureCompatibleContainer()
            inspectStorage()
            setDiscordPresence()
        }
        .onChange(of: game.launchProfile.effectiveRuntimeID) { _, newValue in
            selectedRuntimeID = newValue
            if selectedGraphicsBackend != .automatic && !availableGraphicsBackends.contains(selectedGraphicsBackend) {
                selectedGraphicsBackend = .automatic
                var profile = game.launchProfile
                profile.selectGraphicsBackend(.automatic)
                game.launchProfile = profile
            }
        }
        .onChange(of: game.launchProfile.graphicsBackend) { _, newValue in
            selectedGraphicsBackend = newValue
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .overview: overviewView
        case .launch: launchView
        case .files: filesView
        case .compatibility: compatibilityView
        case .graphics: graphicsView
        }
    }

    private var overviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                HStack(spacing: 12) {
                    statusCard(title: "Storefront", value: game.storefront?.description ?? "Local", icon: "bag")
                    statusCard(title: "Runtime", value: game.launchProfile.effectiveRuntimeID.rawValue, icon: "shippingbox")
                    statusCard(title: "Mode", value: isCompatibilityOverrideEnabled ? "Manual" : "Automatic", icon: isCompatibilityOverrideEnabled ? "slider.horizontal.3" : "wand.and.stars")
                }

                sectionCard(title: "Quick actions", icon: "bolt.fill") {
                    HStack(spacing: 10) {
                        GameCard.Buttons.VerificationButton(game: $game, withLabel: true)
                        Button("Launch Settings") { selection = .launch }
                        if case .installed = game.installationState {
                            Button("Open Files") { selection = .files }
                        }
                        if case .installed(_, let platform) = game.installationState,
                           case .windows = platform {
                            Button("Compatibility") { selection = .compatibility }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if case .installed(_, let platform) = game.installationState,
                   case .windows = platform {
                    compatibilitySummary
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var launchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(title: "Launch", subtitle: "Control the arguments and launch-time checks Kraken applies to this game.")

                sectionCard(title: "Launch options", icon: "terminal") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Special instructions passed to the game when it starts. Most people should leave these alone unless a game or compatibility guide tells you to add one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !game.launchArguments.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(game.launchArguments, id: \.self) { argument in
                                        ArgumentItem(game: $game, launchArguments: $game.launchArguments, argument: argument)
                                    }
                                }
                            }
                            .scrollIndicators(.never)
                        }

                        HStack {
                            TextField("Add launch option", text: $typingArgument)
                                .onSubmit(submitLaunchArgument)
                            Button("Add") { submitLaunchArgument() }
                                .disabled(typingArgument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                sectionCard(title: "Game files", icon: "checkmark.shield") {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Verify installation")
                                .font(.headline)
                            Text("Check whether installed game files are intact.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        GameCard.Buttons.VerificationButton(game: $game, withLabel: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(title: "Files", subtitle: "Manage where the game is stored and check whether macOS has offloaded any assets.")

                if case .installed(let location, _) = game.installationState {
                    sectionCard(title: "Installation", icon: "folder") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location")
                                        .font(.headline)
                                    Text(location.prettyPath)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([location])
                                }
                            }

                            Divider()

                            HStack {
                                Text("Move \"\(game.title)\"")
                                Spacer()
                                if operationManager.queue.contains(where: { $0.game == game && $0.type == .move }) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("Move…") { isMovingFileImporterPresented = true }
                                        .disabled(operationManager.queue.first?.game == game)
                                }
                            }
                            .fileImporter(isPresented: $isMovingFileImporterPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                                handleMoveResult(result)
                            }
                            .alert("Unable to move \"\(game.title)\".", isPresented: $isMovingErrorAlertPresented, presenting: movingError) { _ in
                                Button("OK", role: .cancel) { }
                            } message: { error in
                                Text(error?.localizedDescription ?? "Unknown error.")
                            }
                        }
                    }

                    if let storagePreflightResult {
                        storageStatusCard(storagePreflightResult, location: location)
                    }
                } else {
                    sectionCard(title: "Not installed", icon: "tray") {
                        Text("This game does not currently have an installed location managed by Kraken.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var compatibilityView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(title: "Compatibility", subtitle: "Choose whether Kraken manages the Windows runtime automatically or you want to override it for this game.")

                if case .installed(_, let platform) = game.installationState,
                   case .windows = platform {
                    sectionCard(title: "Runtime", icon: "shippingbox") {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Use a manual compatibility runtime", isOn: $isCompatibilityOverrideEnabled)
                                .onChange(of: isCompatibilityOverrideEnabled) { _, enabled in
                                    setManualRuntimeOverride(enabled)
                                }

                            Picker("Runtime", selection: $selectedRuntimeID) {
                                ForEach([Runtime.mythicEngine, Runtime.gptk, Runtime.wine11]) { runtime in
                                    HStack(spacing: 6) {
                                        Text(runtime.name)
                                        Text(runtime.id == .wine11 ? "Engine 3" : (runtime.id == .gptk ? "GPTK" : "Engine 2"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(runtime.id)
                                }
                            }
                            .disabled(!isCompatibilityOverrideEnabled)
                            .onChange(of: selectedRuntimeID) { oldValue, newValue in
                                guard isCompatibilityOverrideEnabled, oldValue != newValue else { return }
                                guard Engine.isRuntimeInstalled(newValue) else {
                                    selectedRuntimeID = oldValue
                                    return
                                }
                                var profile = game.launchProfile
                                profile.selectRuntime(newValue)
                                profile.container = compatibleContainerURL(for: newValue).map(ContainerReference.init(url:))
                                game.launchProfile = profile
                            }

                            ContainerSettingsView(
                                selectedContainerURL: $game.containerURL,
                                withPicker: true,
                                selectedRuntimeID: game.launchProfile.effectiveRuntimeID
                            )
                            .disabled(!isCompatibilityOverrideEnabled)

                            Text(isCompatibilityOverrideEnabled ? "The selected runtime and compatible container are used for this game." : "Automatic mode lets Kraken choose the validated runtime and container.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    sectionCard(title: "Windows compatibility", icon: "checkmark.circle") {
                        Text("Compatibility controls become available when this game is installed as a Windows game.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var graphicsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageIntro(title: "Graphics", subtitle: "Choose the graphics backend and the VRAM amount Windows should be told the game has.")

                sectionCard(title: "Graphics backend", icon: "display") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Graphics", selection: $selectedGraphicsBackend) {
                            Text(GraphicsBackend.automatic.displayName).tag(GraphicsBackend.automatic)
                            ForEach(GraphicsBackend.allCases.filter { $0 != .automatic }, id: \.self) { backend in
                                HStack(spacing: 6) {
                                    Text(backend.displayName)
                                    if !availableGraphicsBackends.contains(backend) {
                                        Text("Unavailable")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(backend)
                            }
                        }
                        .onChange(of: selectedGraphicsBackend) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            if newValue != .automatic && !availableGraphicsBackends.contains(newValue) {
                                selectedGraphicsBackend = oldValue
                                return
                            }
                            var profile = game.launchProfile
                            profile.selectGraphicsBackend(newValue)
                            game.launchProfile = profile
                        }

                        Text(selectedGraphicsBackend == .automatic ? "Kraken selects an available graphics backend automatically." : "Kraken will use the selected backend for this game.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard(title: "Reported GPU memory", icon: "memorychip") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Reported GPU Memory", selection: reportedMemorySelection) {
                            let autoMB = ReportedGPUMemoryResolver.shared.automaticMegabytes()
                            Text("Automatic (\(autoMB) MB)").tag(0)
                            Text("1024 MB (1 GB)").tag(1024)
                            Text("2048 MB (2 GB)").tag(2048)
                            Text("4095 MB (4 GB)").tag(4095)
                            Text("8192 MB (8 GB)").tag(8192)
                            Text("16384 MB (16 GB)").tag(16384)
                        }

                        Text("This changes the VRAM amount reported to Windows games. It does not reserve physical RAM, but an incorrect value can cause crashes or memory pressure.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameImageCard(url: game.horizontalImageURL, isImageEmpty: $isImageEmpty)
                .aspectRatio(2.35, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 270)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)

            HStack(spacing: 14) {
                if isImageEmpty && game.isFallbackImageAvailable {
                    GameImageCard.FallbackGameImageCard(game: .constant(game))
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(game.title)
                        .font(.title.bold())
                        .lineLimit(1)
                    GameCard.SubscriptedInfoView(game: $game)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var compatibilitySummary: some View {
        sectionCard(title: "Compatibility status", icon: "checkmark.shield") {
            HStack {
                Image(systemName: isCompatibilityOverrideEnabled ? "slider.horizontal.3" : "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isCompatibilityOverrideEnabled ? "Manual compatibility" : "Automatic compatibility")
                        .font(.headline)
                    Text(isCompatibilityOverrideEnabled ? "Runtime: \(selectedRuntimeID.rawValue)" : "Kraken manages the runtime and container for this game.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Configure") { selection = .compatibility }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func statusCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func pageIntro(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func storageStatusCard(_ result: StoragePreflightResult, location: URL) -> some View {
        switch result.readiness {
        case .ready:
            sectionCard(title: "Storage ready", icon: "checkmark.seal.fill") {
                Label("\(result.totalFilesChecked) assets verified locally", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case let .materializationRequired(count, bytes):
            sectionCard(title: "Assets need downloading", icon: "icloud.and.arrow.down") {
                Text("\(count) files (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))) are currently dataless stubs. Launching without downloading them can cause severe loading delays.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Download Game Assets Now") {
                    Task.detached {
                        GameStoragePreflight.materializeDatalessFiles(in: location)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .cloudLocationWarning:
            sectionCard(title: "iCloud-managed location", icon: "icloud") {
                Text("macOS may offload assets from this directory when disk space is low. Moving the game to ~/Games or /Users/Shared is recommended.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var availableGraphicsBackends: Set<GraphicsBackend> {
        GraphicsBackendDetector.availableBackends(for: game.launchProfile.effectiveRuntimeID)
    }

    private func compatibleContainerURL(for runtimeID: RuntimeID) -> URL? {
        Wine.containerObjects
            .filter { $0.runtimeID == runtimeID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .first?
            .url
    }

    private func ensureCompatibleContainer() {
        guard game.launchProfile.runtimeOverride == nil else { return }
        let runtimeID = game.launchProfile.effectiveRuntimeID
        guard
            let currentURL = game.launchProfile.container?.url,
            let currentContainer = try? Wine.getContainerObject(at: currentURL),
            currentContainer.runtimeID == runtimeID
        else {
            var profile = game.launchProfile
            profile.container = compatibleContainerURL(for: runtimeID).map(ContainerReference.init(url:))
            game.launchProfile = profile
            return
        }
    }

    private func setManualRuntimeOverride(_ enabled: Bool) {
        var profile = game.launchProfile
        if enabled {
            let runtimeID = profile.container.flatMap { reference in
                (try? Wine.getContainerObject(at: reference.url))?.runtimeID
            } ?? profile.effectiveRuntimeID
            profile.selectRuntime(runtimeID)
            profile.container = compatibleContainerURL(for: runtimeID).map(ContainerReference.init(url:))
        } else {
            let automaticRuntime = profile.container.flatMap { reference in
                (try? Wine.getContainerObject(at: reference.url))?.runtimeID
            } ?? profile.effectiveRuntimeID
            profile.setDefaultRuntime(automaticRuntime)
            profile.clearRuntimeOverride()
        }
        game.launchProfile = profile
    }

    private var reportedMemorySelection: Binding<Int> {
        Binding(
            get: {
                switch game.launchProfile.reportedGPUMemoryPolicy {
                case .automatic: return 0
                case .manual(let mb): return mb
                }
            },
            set: { newValue in
                var profile = game.launchProfile
                if newValue == 0 {
                    profile.selectReportedGPUMemoryPolicy(.automatic)
                } else {
                    profile.selectReportedGPUMemoryPolicy(.manual(megabytes: newValue))
                }
                game.launchProfile = profile
            }
        )
    }

    private func submitLaunchArgument() {
        let cleanedArgument = typingArgument
            .trimmingCharacters(in: .illegalCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var wordExpansion = wordexp_t() // swiftlint:disable:this identifier_name
        defer { wordfree(&wordExpansion) }
        guard Darwin.wordexp(cleanedArgument, &wordExpansion, 0) == 0 else { return }

        let splitArguments: [String] = (0..<Int(wordExpansion.we_wordc))
            .compactMap { String(cString: wordExpansion.we_wordv[$0]!) }

        guard !cleanedArgument.isEmpty else { return }
        guard !game.launchArguments.contains(typingArgument) else { return }
        game.launchArguments += splitArguments
        typingArgument = ""
    }

    private func handleMoveResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let locations):
            guard let newLocation = locations.first else { return }
            Task { @MainActor in
                do {
                    try await game.move(to: newLocation)
                } catch {
                    movingError = error
                    isMovingErrorAlertPresented = true
                }
            }
        case .failure(let error):
            movingError = error
            isMovingErrorAlertPresented = true
        }
    }

    private func inspectStorage() {
        guard case .installed(let location, _) = game.installationState else { return }
        Task.detached(priority: .userInitiated) {
            let result = GameStoragePreflight.inspect(at: location, maxFilesToScan: 5_000)
            await MainActor.run {
                storagePreflightResult = result
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if case .installed(_, let platform) = game.installationState {
                SubscriptedTextView(platform.description)
            }
            GameCard.SubscriptedInfoView(game: $game)
            Spacer()
            Button("Close") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func setDiscordPresence() {
        discordRPC.setPresence({
            var presence: RichPresence = .init()
            presence.details = "Configuring \"\(game.title)\""
            presence.state = "Configuring \(game.title)"
            presence.timestamps.start = .now
            presence.assets.largeImage = "macos_512x512_2x"
            return presence
        }())
    }

    struct ArgumentItem: View {
        @Binding var game: Game
        @Binding var launchArguments: [String]
        let argument: String
        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 5) {
                Text(argument)
                    .monospaced()
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isHovering ? .red : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary, in: .capsule)
            .onHover { isHovering = $0 }
            .onTapGesture {
                launchArguments.removeAll { $0 == argument }
                game.launchArguments = launchArguments
            }
            .help("Remove \(argument)")
        }
    }
}

#Preview {
    GameSettingsView(
        game: .constant(placeholderGame(type: Game.self)),
        isPresented: .constant(true)
    )
    .environmentObject(NetworkMonitor.shared)
}
