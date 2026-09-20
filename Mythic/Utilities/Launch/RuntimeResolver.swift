//
//  RuntimeResolver.swift
//  Mythic
//
// Copyright © 2026 Kraken contributors

import Foundation
import OSLog

/// The single authority for "which runtime and which container does this game use".
///
/// Before this existed, the local and Epic launch paths each derived the runtime
/// differently — local used `runtimeOverride ?? container.runtimeID`, Epic used
/// the launch profile's effective runtime — so the same `Game` could resolve to
/// two different runtimes depending only on its storefront.
///
/// The resolver is deliberately small, value-oriented and side-effect free:
///
/// - it takes a `LaunchProfile` (a value) rather than a `Game` (a non-Sendable
///   reference), so it can be used off the main actor and in tests;
/// - it never mutates persisted state, even when validation fails;
/// - it never substitutes a different runtime or container to manufacture a
///   happy path. Every failure is a distinct, typed error so the UI can offer
///   the right remediation.
enum RuntimeResolver {

    // MARK: - Output

    /// Everything needed to launch, with runtime and container already agreed.
    struct ResolvedLaunchTarget: Equatable, Sendable {
        /// Filesystem locations of the runtime that will execute the game.
        let runtime: WineRuntime

        /// The prefix the game runs in.
        let container: ContainerReference

        /// Runtime-appropriate environment, ready to apply to a `Process`.
        let environment: [String: String]

        /// Launch arguments in their persisted order.
        let launchArguments: [String]

        /// Graphics backend resolved for this launch.
        let graphicsBackend: GraphicsBackend

        /// VRAM capacity (in MB) reported to Windows Direct3D games.
        let reportedGPUMemoryMB: Int

        var runtimeID: RuntimeID { runtime.id }
        var containerURL: URL { container.url }
    }

    // MARK: - Errors

    enum ResolutionError: LocalizedError, Equatable {
        /// The selected runtime is not installed on this machine.
        case runtimeNotInstalled(RuntimeID)

        /// The game has no container assigned for the selected runtime.
        case noContainerAssigned(RuntimeID)

        /// The assigned container no longer exists on disk.
        case containerMissing(URL)

        /// The container exists but its `Properties.plist` is unreadable.
        case containerUnreadable(URL)

        /// The container belongs to a different runtime than the one selected.
        case containerRuntimeMismatch(selected: RuntimeID, containerRuntime: RuntimeID, containerURL: URL)

        var errorDescription: String? {
            switch self {
            case let .runtimeNotInstalled(runtimeID):
                return String(localized: "\(Runtime.displayName(for: runtimeID)) isn't installed yet.")
            case let .noContainerAssigned(runtimeID):
                return String(localized: "This game has no \(Runtime.displayName(for: runtimeID)) environment assigned.")
            case let .containerMissing(url):
                return String(localized: "The Windows environment at \(url.prettyPath) no longer exists.")
            case let .containerUnreadable(url):
                return String(localized: "The Windows environment at \(url.prettyPath) is damaged and can't be read.")
            case let .containerRuntimeMismatch(selected, containerRuntime, _):
                return String(localized: """
                    This game is set to run on \(Runtime.displayName(for: selected)), \
                    but its Windows environment belongs to \(Runtime.displayName(for: containerRuntime)).
                    """)
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case let .runtimeNotInstalled(runtimeID):
                return String(localized: "Install \(Runtime.displayName(for: runtimeID)) to continue.")
            case .noContainerAssigned:
                return String(localized: "Create a new Windows environment, or choose an existing one.")
            case .containerMissing:
                return String(localized: "Choose a different Windows environment, or create a new one.")
            case .containerUnreadable:
                return String(localized: "Repair the environment, or choose a different one.")
            case .containerRuntimeMismatch:
                return String(localized: "Choose an environment that belongs to the selected runtime, or create one.")
            }
        }
    }

    // MARK: - Runtime authority

    /// The one rule for deriving a game's runtime, used by every launch path.
    ///
    /// Storefront plays no part: a given `LaunchProfile` always yields the same
    /// runtime whether the game came from Epic, locally, or anywhere else.
    static func runtimeID(for profile: LaunchProfile) -> RuntimeID {
        profile.effectiveRuntimeID
    }

    /// Runtimes Kraken knows about, in display order.
    static let allRuntimeIDs: [RuntimeID] = [.mythicEngine, .gptk, .wine11]

    /// Runtimes actually installed and usable right now.
    static func installedRuntimeIDs() -> [RuntimeID] {
        allRuntimeIDs.filter(Engine.isRuntimeInstalled)
    }

    // MARK: - Resolution

    /// Validate a profile and produce a launch target, or explain precisely why not.
    ///
    /// This performs no mutation and no provisioning. A caller that wants a
    /// container created must do so through an explicit game operation.
    static func resolve(profile: LaunchProfile) throws -> ResolvedLaunchTarget {
        let selectedRuntimeID = runtimeID(for: profile)

        guard Engine.isRuntimeInstalled(selectedRuntimeID) else {
            throw ResolutionError.runtimeNotInstalled(selectedRuntimeID)
        }

        guard let reference = profile.container else {
            throw ResolutionError.noContainerAssigned(selectedRuntimeID)
        }

        guard Wine.containerExists(at: reference.url) else {
            throw ResolutionError.containerMissing(reference.url)
        }

        let container: Wine.Container
        do {
            container = try Wine.getContainerObject(at: reference.url)
        } catch {
            throw ResolutionError.containerUnreadable(reference.url)
        }

        guard container.runtimeID == selectedRuntimeID else {
            throw ResolutionError.containerRuntimeMismatch(
                selected: selectedRuntimeID,
                containerRuntime: container.runtimeID,
                containerURL: reference.url
            )
        }

        // Resolve graphics backend
        let resolvedBackend = try GraphicsBackendResolver.resolve(
            profile: profile,
            runtimeID: selectedRuntimeID
        )

        // Resolve reported GPU memory
        let reportedMemoryMB = ReportedGPUMemoryResolver.shared.resolveMegabytes(
            for: profile.reportedGPUMemoryPolicy
        )

        // When D3DMetal is selected, ensure the container's system32 has matching companion DLLs
        if resolvedBackend == .d3dmetal {
            try? GPTKInstaller.syncContainerDLLs(containerURL: reference.url, for: selectedRuntimeID)
        }

        // When DXVK is selected, provision container dxvk.conf with the resolved memory reporting
        if resolvedBackend == .dxvk {
            try? DXVKConfigurationManager.writeConfiguration(
                toContainerAtURL: reference.url,
                memoryMB: reportedMemoryMB
            )
        }

        return .init(
            runtime: Engine.wineRuntime(for: selectedRuntimeID),
            container: reference,
            environment: environment(
                forRuntime: selectedRuntimeID,
                containerURL: reference.url,
                settings: container.settings,
                graphicsBackend: resolvedBackend
            ),
            launchArguments: profile.launchArguments,
            graphicsBackend: resolvedBackend,
            reportedGPUMemoryMB: reportedMemoryMB
        )
    }

    /// Whether a profile can currently be launched, without throwing.
    static func canLaunch(profile: LaunchProfile) -> Bool {
        (try? resolve(profile: profile)) != nil
    }

    // MARK: - Environment assembly

    /// Build the complete runtime environment for a container with graphics backend.
    ///
    /// This is the only place runtime-specific environment is assembled. It used
    /// to be duplicated between `Wine.transformProcess` and
    /// `Legendary.launch`, which allowed the two launch paths to drift.
    static func environment(
        forRuntime runtimeID: RuntimeID,
        containerURL: URL,
        settings: Wine.Container.Settings,
        graphicsBackend: GraphicsBackend
    ) -> [String: String] {
        var environment: [String: String] = [:]

        // Common to every Wine runtime.
        environment["WINEPREFIX"] = containerURL.path(percentEncoded: false)
        environment["WINEMSYNC"] = settings.msync.numericalValue.description
        environment["ROSETTA_ADVERTISE_AVX"] = settings.avx2.numericalValue.description

        let runtime = Engine.wineRuntime(for: runtimeID)

        if runtimeID.requiresExplicitLoaderEnvironment {
            /*
             A runtime living in its own app bundle cannot be found by Wine's
             built-in relative lookups, so the loader, server and bundle root
             have to be named explicitly.
             */
            environment["WINESERVER"] = runtime.wineserverExecutable.path
            environment["WINELOADER"] = runtime.wineExecutable.path
            environment["WINE"] = runtime.wineExecutable.path
            environment["WINE64"] = runtime.wineExecutable.path

            if let bundleURL = runtime.wineBundleURL {
                environment["WINE_APP_BUNDLE"] = bundleURL.path
            }
        }

        // Backend-specific environment
        applyBackendEnvironment(
            &environment,
            backend: graphicsBackend,
            runtimeID: runtimeID,
            settings: settings
        )

        return environment
    }

    /// Apply backend-specific environment variables.
    private static func applyBackendEnvironment(
        _ environment: inout [String: String],
        backend: GraphicsBackend,
        runtimeID: RuntimeID,
        settings: Wine.Container.Settings
    ) {
        switch backend {
        case .automatic:
            // Should have been resolved before this point
            break

        case .d3dmetal:
            environment["WINEDLLOVERRIDES"] = "d3d10,d3d11,d3d12,dxgi=n,b"
            let runtime = Engine.wineRuntime(for: runtimeID)
            let externalPath = runtime.externalLibrariesURL
            let frameworkBinary = externalPath.appending(
                path: "D3DMetal.framework/D3DMetal"
            )
            environment["DYLD_FRAMEWORK_PATH"] = externalPath.path
            environment["DYLD_FALLBACK_LIBRARY_PATH"] = externalPath.path
            environment["D3DMETAL_FRAMEWORK_PATH"] = frameworkBinary.path
            environment["D3DM_SUPPORT_DXR"] = "1"

        case .dxmt:
            environment["WINEDLLOVERRIDES"] = "d3d10,d3d11,dxgi=n"

        case .dxvk:
            environment["WINEDLLOVERRIDES"] = "d3d10core,d3d11,dxgi=n,b"
            environment["DXVK_ASYNC"] = settings.dxvkAsync.numericalValue.description
            environment["DXVK_CONFIG_FILE"] = "C:\\windows\\dxvk.conf"

        case .wined3d:
            // No overrides - use Wine's built-in D3D implementation
            break
        }

        // HUD handling
        if settings.metalHUD {
            switch backend {
            case .dxvk:
                environment["DXVK_HUD"] = "full"
            case .wined3d, .d3dmetal, .dxmt, .automatic:
                environment["MTL_HUD_ENABLED"] = "1"
            }
        }
    }

    /// Apply a resolved target to a process, ready to run.
    static func configure(_ process: Process, for target: ResolvedLaunchTarget) {
        process.executableURL = target.runtime.wineExecutable
        // Caller-supplied variables lose to resolved ones: the resolved runtime
        // environment must not be silently overridden by stale values.
        let baseEnvironment = process.environment ?? ProcessInfo.processInfo.environment
        process.environment = baseEnvironment
            .merging(target.environment, uniquingKeysWith: { _, resolved in resolved })
    }
}

// MARK: - Runtime capabilities

extension RuntimeID {
    /// Whether the runtime needs its loader/server named explicitly in the environment.
    ///
    /// Engine 2 is laid out at a path Wine already resolves relative to its own
    /// loader; the Wine 11 runtime ships as a relocatable `.app` bundle and does not.
    var requiresExplicitLoaderEnvironment: Bool {
        switch self {
        case .mythicEngine, .gptk: return false
        case .wine11:              return true
        }
    }

    /// Whether Kraken can rely on DXVK being present for this runtime.
    ///
    /// Engine 2 bundles DXVK, so `WINEDLLOVERRIDES=d3d11=n,b` resolves to real
    /// DXVK DLLs. The pinned Gcenx Wine 11 build is only verified by Kraken to
    /// contain `wined3d.dll` (see `Engine.isRuntimeInstalled`), so forcing the
    /// native-DLL override there would point Direct3D at DLLs that may not
    /// exist and break rendering outright.
    ///
    /// - Note: UNVERIFIED against an installed Wine 11 runtime. If that build is
    ///   confirmed to ship DXVK, this should become a real capability probe
    ///   rather than a hardcoded answer.
    var providesDXVK: Bool {
        switch self {
        case .mythicEngine, .wine11: return true
        case .gptk: return false
        }
    }
}

extension Runtime {
    /// User-facing name for a runtime, without leaking the raw identifier.
    static func displayName(for runtimeID: RuntimeID) -> String {
        switch runtimeID {
        case .mythicEngine: return Runtime.mythicEngine.name
        case .gptk:         return Runtime.gptk.name
        case .wine11:       return Runtime.wine11.name
        }
    }
}
