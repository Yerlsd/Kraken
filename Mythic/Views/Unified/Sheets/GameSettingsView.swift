// where the hell is the comment

import SwiftUI
import SwordRPC
import OSLog
import Darwin
import Glur

// FIXME: refactor: warning ‼️ below code may need a cleanup
struct GameSettingsView: View {
    @Binding var game: Game
    @Binding var isPresented: Bool

    @Bindable private var operationManager: GameOperationManager = .shared

    @State private var movingError: Error?
    @State private var isMovingErrorAlertPresented = false
    @State private var isMovingFileImporterPresented = false

    @State private var typingArgument = String()
    @State private var isImageEmpty = true

    @State private var isFileSectionExpanded = true
    @State private var isContainerSectionExpanded = true
    @State private var isGameSectionExpanded = true
    @State private var isCompatibilityOverrideExpanded = false

    @State private var selectedRuntimeID: RuntimeID = .mythicEngine

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    ZStack(alignment: .bottomLeading) {
                        GameImageCard(url: game.horizontalImageURL, isImageEmpty: $isImageEmpty)
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(
                                width: geometry.size.width,
                                height: min(270, geometry.size.height * 0.42)
                            )
                            .clipShape(.rect(cornerRadius: 16))
                            .glur(radius: 12, offset: 0.6, interpolation: 0.6)

                        HStack {
                            if isImageEmpty && game.isFallbackImageAvailable {
                                GameImageCard.FallbackGameImageCard(game: .constant(game))
                                    .frame(width: 58, height: 58)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                GameCard.TitleAndInformationView(game: $game, withSubscriptedInfo: false)
                                    .lineLimit(1)

                                GameCard.ButtonsView(game: $game, withLabel: true)
                                    .clipShape(.capsule)
                            }
                        }
                        .padding(16)
                        .conditionalTransform(if: !isImageEmpty) { view in
                            view.foregroundStyle(.white)
                        }
                    }

                    Form {
                        Section("Options", isExpanded: $isGameSectionExpanded) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Launch options")
                                    Text(
                                        "Special instructions passed to the game when it starts. "
                                        + "Most people should leave these alone unless a game "
                                        + "or compatibility guide tells you to add one."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                    if !game.launchArguments.isEmpty {
                                        ScrollView(.horizontal) {
                                            HStack {
                                                ForEach(game.launchArguments, id: \.self) { argument in
                                                    ArgumentItem(
                                                        game: $game,
                                                        launchArguments: $game.launchArguments,
                                                        argument: argument
                                                    )
                                                }
                                            }
                                        }
                                        .scrollIndicators(.never)
                                    }
                                }

                                Spacer()

                                TextField("Add launch option", text: Binding(
                                    get: { typingArgument },
                                    set: { newValue in
                                        if (0...1).contains(typingArgument.count) {
                                            withAnimation { typingArgument = newValue }
                                        } else {
                                            typingArgument = newValue
                                        }
                                    }
                                ))
                                .onSubmit(submitLaunchArgument)

                                if !typingArgument.isEmpty {
                                    Button("", systemImage: "return") {
                                        submitLaunchArgument()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Check game files")
                                    Text(
                                        "Checks whether the installed game files are intact. "
                                        + "Useful when a game is crashing, missing files, "
                                        + "or behaving unexpectedly."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                    if let currentOperation = operationManager.queue.first,
                                       case .repair = currentOperation.type,
                                       currentOperation.game == game {
                                        ProgressView()
                                            .progressViewStyle(.linear)
                                    }
                                }

                                Spacer()
                                GameCard.Buttons.VerificationButton(game: $game, withLabel: true)
                            }
                        }

                        Section("File", isExpanded: $isFileSectionExpanded) {
                            HStack {
                                Text("Move \"\(game.title)\"")
                                Spacer()

                                if operationManager.queue.contains(where: { $0.game == game && $0.type == .move }) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Move...") {
                                        isMovingFileImporterPresented = true
                                    }
                                    .disabled(operationManager.queue.first?.game == game)
                                    .fileImporter(
                                        isPresented: $isMovingFileImporterPresented,
                                        allowedContentTypes: [.folder],
                                        allowsMultipleSelection: false
                                    ) { result in
                                        switch result {
                                        case .success(let success):
                                            guard let newLocation = success.first else { return }
                                            Task { @MainActor in
                                                do {
                                                    try await game.move(to: newLocation)
                                                } catch {
                                                    movingError = error
                                                    isMovingErrorAlertPresented = true
                                                }
                                            }
                                        case .failure(let failure):
                                            movingError = failure
                                            isMovingErrorAlertPresented = true
                                        }
                                    }
                                    .alert(
                                        "Unable to move \"\(game.title)\".",
                                        isPresented: $isMovingErrorAlertPresented,
                                        presenting: movingError
                                    ) { _ in
                                        if #available(macOS 26.0, *) {
                                            Button("OK", role: .close) { isPresented = false }
                                        } else {
                                            Button("OK", role: .cancel) { isPresented = false }
                                        }
                                    } message: { error in
                                        Text(error?.localizedDescription ?? "Unknown error.")
                                    }
                                }
                            }

                            if case .installed(let location, _) = game.installationState {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Location", comment: "Game Location")
                                        Text(location.prettyPath)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([location])
                                    }
                                }
                            }
                        }

                        if case .installed(_, let platform) = game.installationState,
                           case .windows = platform {
                            Section("Windows compatibility", isExpanded: $isContainerSectionExpanded) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Label(
                                            game.launchProfile.runtimeOverride == nil ? "Automatic" : "Manual",
                                            systemImage: game.launchProfile.runtimeOverride == nil
                                                ? "wand.and.stars"
                                                : "slider.horizontal.3"
                                        )
                                        .font(.headline)

                                        Text(
                                            game.launchProfile.runtimeOverride == nil
                                                ? "Managed by Kraken"
                                                : "Manual compatibility override enabled"
                                        )
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(
                                        systemName: game.launchProfile.runtimeOverride == nil
                                            ? "checkmark.circle.fill"
                                            : "gearshape.fill"
                                    )
                                    .foregroundStyle(.secondary)
                                }

                                Text(
                                    game.launchProfile.runtimeOverride == nil
                                        ? "Kraken uses the game's current validated compatibility setup."
                                        : "The selected runtime and compatible container are used for this game."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                DisclosureGroup(
                                    "Compatibility override",
                                    isExpanded: $isCompatibilityOverrideExpanded
                                ) {
                                    Toggle(
                                        "Use a manual compatibility runtime",
                                        isOn: manualRuntimeOverride
                                    )

                                    Picker("Runtime", selection: $selectedRuntimeID) {
                                        ForEach([Runtime.mythicEngine, Runtime.wine11]) { runtime in
                                            HStack(spacing: 6) {
                                                Text(runtime.name)
                                                Text(runtime.id == .wine11 ? "Engine 3" : "Engine 2")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .tag(runtime.id)
                                        }
                                    }
                                    .disabled(game.launchProfile.runtimeOverride == nil)
                                    .onChange(of: selectedRuntimeID) { oldValue, newValue in
                                        guard game.launchProfile.runtimeOverride != nil else { return }
                                        guard Engine.isRuntimeInstalled(newValue) else { return }
                                        guard oldValue != newValue else { return }

                                        var profile = game.launchProfile
                                        profile.selectRuntime(newValue)
                                        profile.container = compatibleContainerURL(for: newValue)
                                            .map(ContainerReference.init(url:))


                                        game.launchProfile = profile

                                    }

                                    ContainerSettingsView(
                                        selectedContainerURL: $game.containerURL,
                                        withPicker: true,
                                        selectedRuntimeID: game.launchProfile.effectiveRuntimeID
                                    )
                                    .disabled(game.launchProfile.runtimeOverride == nil)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            if let canonicalGame = GameDataStore.shared.library.first(where: { $0.id == game.id }) {
            } else {
            }
            selectedRuntimeID = game.launchProfile.effectiveRuntimeID
            ensureCompatibleContainer()
        }
        .onChange(of: game.launchProfile.effectiveRuntimeID) { _, newValue in
            selectedRuntimeID = newValue
        }

        bottomBar
    }
}

private extension GameSettingsView {
    var availableGraphicsBackends: Set<GraphicsBackend> {
        GraphicsBackendDetector.availableBackends(for: game.launchProfile.effectiveRuntimeID)
    }

    func compatibleContainerURL(for runtimeID: RuntimeID) -> URL? {
        Wine.containerObjects
            .filter { $0.runtimeID == runtimeID }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .first?
            .url
    }

    func ensureCompatibleContainer() {
        // Don't interfere with manual runtime selection
        guard game.launchProfile.runtimeOverride == nil else {
            return
        }

        let runtimeID = game.launchProfile.effectiveRuntimeID

        guard
            let currentURL = game.launchProfile.container?.url,
            let currentContainer = try? Wine.getContainerObject(at: currentURL),
            currentContainer.runtimeID == runtimeID
        else {
            var profile = game.launchProfile
            profile.container = compatibleContainerURL(for: runtimeID)
                .map(ContainerReference.init(url:))
            game.launchProfile = profile
            return
        }
    }

    var manualRuntimeOverride: Binding<Bool> {
        Binding(
            get: { game.launchProfile.runtimeOverride != nil },
            set: { enabled in
                var profile = game.launchProfile

                if enabled {
                    let runtimeID = profile.container.flatMap { reference in
                        (try? Wine.getContainerObject(at: reference.url))?.runtimeID
                    } ?? profile.effectiveRuntimeID

                    profile.selectRuntime(runtimeID)
                    profile.container = compatibleContainerURL(for: runtimeID)
                        .map(ContainerReference.init(url:))
                } else {
                    let automaticRuntime = profile.container.flatMap { reference in
                        (try? Wine.getContainerObject(at: reference.url))?.runtimeID
                    } ?? profile.effectiveRuntimeID

                    profile.setDefaultRuntime(automaticRuntime)
                    profile.clearRuntimeOverride()
                }

                game.launchProfile = profile
            }
        )
    }

    func submitLaunchArgument() {
        let cleanedArgument = typingArgument
            .trimmingCharacters(in: .illegalCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var w = wordexp_t() // swiftlint:disable:this identifier_name
        defer { wordfree(&w) }

        guard Darwin.wordexp(cleanedArgument, &w, 0) == 0 else { return }

        let splitArguments: [String] = (0..<Int(w.we_wordc))
            .compactMap({ String(cString: w.we_wordv[$0]!) })

        if !cleanedArgument.isEmpty,
           !game.launchArguments.contains(typingArgument) {
            game.launchArguments += splitArguments
            typingArgument = .init()
        }
    }
}

private extension GameSettingsView {
    var bottomBar: some View {
        HStack {
            if case .installed(_, let platform) = game.installationState {
                SubscriptedTextView(platform.description)
            }
            GameCard.SubscriptedInfoView(game: $game)

            Spacer()

            Button("Close") { isPresented = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    func setDiscordPresence() {
        discordRPC.setPresence({
            var presence: RichPresence = .init()
            presence.details = "Configuring \"\(game.title)\""
            presence.state = "Configuring \(game.title)"
            presence.timestamps.start = .now
            presence.assets.largeImage = "macos_512x512_2x"
            return presence
        }())
    }
}

extension GameSettingsView {
    struct ArgumentItem: View {
        @Binding var game: Game
        @Binding var launchArguments: [String]
        var argument: String
        @State var isHoveringOverArgument = false

        var body: some View {
            HStack {
                Text(argument)
                    .monospaced()
                    .foregroundStyle(isHoveringOverArgument ? .red : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .background(in: .capsule)
            .backgroundStyle(.quinary)
            .onHover { hovering in
                withAnimation { isHoveringOverArgument = hovering }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    launchArguments.removeAll(where: { $0 == argument })
                    if launchArguments.isEmpty {
                        game.launchArguments = .init()
                    }
                }
            }
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
