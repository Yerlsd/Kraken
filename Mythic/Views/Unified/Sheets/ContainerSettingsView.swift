//
//  ContainerSettings.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 7/2/2024.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI

struct ContainerSettingsView: View {
    @Binding var selectedContainerURL: URL?
    var withPicker: Bool
    var selectedRuntimeID: RuntimeID = Runtime.current.id

    @ObservedObject private var variables: VariableManager = .shared

    @State private var retinaMode: Bool = Wine.Container.Settings().retinaMode
    @State private var modifyingRetinaMode: Bool = true // keep progressview displayed until async fetching is complete
    @State private var retinaModeSuccess: Bool?

    @State private var isDXVKDisclaimerPresented: Bool = false
    @State private var modifyingDXVK: Bool = false
    @State private var dxvkSuccess: Bool?

    @State private var windowsVersion: Wine.WindowsVersion = Wine.Container.Settings().windowsVersion
    @State private var modifyingWindowsVersion: Bool = true // keep progressview displayed until async fetching is complete
    @State private var windowsVersionSuccess: Bool?
    @State private var isAdvancedSectionExpanded: Bool = false

    private func fetchRetinaModeStatus() async {
        guard let selectedContainerURL,
              let container = try? Wine.getContainerObject(at: selectedContainerURL) else { return }
        
        do {
            let fetchedRetinaMode = try await Wine.getRetinaMode(
                containerURL: selectedContainerURL,
                runtimeID: container.runtimeID
            )
            
            await MainActor.run(body: { retinaMode = fetchedRetinaMode })
            // intentionally separated, to prevent both variable updates from occuring during the same render cycle
            await MainActor.run {
                withAnimation {
                    modifyingRetinaMode = false
                }
            }
        } catch {
            await MainActor.run {
                modifyingRetinaMode = false
                retinaModeSuccess = false
            }
        }
    }

    private func fetchWindowsVersion() async {
        guard let selectedContainerURL,
              let container = try? Wine.getContainerObject(at: selectedContainerURL) else { return }

        do {
            if let fetchedWindowsVersion = try await Wine.getWindowsVersion(
                containerURL: selectedContainerURL,
                runtimeID: container.runtimeID
            ) {
                await MainActor.run {
                    windowsVersion = fetchedWindowsVersion
                    withAnimation {
                        modifyingWindowsVersion = false
                    }
                }
            } else {
                await MainActor.run {
                    modifyingWindowsVersion = false
                }
            }
        } catch {
            await MainActor.run {
                modifyingWindowsVersion = false
                windowsVersionSuccess = false
            }
        }
    }

    private func settingDescription(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func compatibleContainer() -> Wine.Container? {
        Wine.containerObjects
            .filter { $0.runtimeID == selectedRuntimeID }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
            .first
    }

    private func ensureCompatibleContainer() {
        guard withPicker else { return }

        if let selectedContainerURL,
           let container = try? Wine.getContainerObject(at: selectedContainerURL),
           container.runtimeID == selectedRuntimeID {
            return
        }

        selectedContainerURL = compatibleContainer()?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedContainerURL,
               let container = try? Wine.getContainerObject(at: selectedContainerURL) {
                Group {
                    Toggle(
                        isOn: Binding(
                            get: { container.settings.metalHUD },
                            set: { container.settings.metalHUD = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Performance overlay")

                            settingDescription(
                                "Shows live performance information while you play. "
                                + "Useful when troubleshooting, but adds an on-screen overlay "
                                + "and a small amount of overhead."
                            )
                        }
                    }
                    .disabled(variables.getVariable("booting") == true)

                    Toggle("High-resolution mode", isOn: $retinaMode)
                        .disabled(variables.getVariable("booting") == true)
                        .task(priority: .high) {
                            await fetchRetinaModeStatus()
                        }
                        .withOperationStatus(
                            operating: $modifyingRetinaMode,
                            successful: $retinaModeSuccess,
                            observing: $retinaMode,
                            placement: .leading
                        ) {
                            do {
                                try await Wine.toggleRetinaMode(
                                    containerURL: container.url,
                                    toggle: retinaMode,
                                    runtimeID: container.runtimeID
                                )

                                container.settings.retinaMode = retinaMode
                                retinaModeSuccess = true
                            } catch {
                                retinaModeSuccess = false
                            }
                        }

                    settingDescription(
                        "Makes Windows text and interface elements sharper on Retina displays. "
                        + "It can increase the amount of graphics work required."
                    )

                    Toggle(
                        isOn: Binding(
                            get: { container.settings.msync },
                            set: { container.settings.msync = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Faster synchronization")

                            settingDescription(
                                "Changes how Wine synchronizes Windows processes. "
                                + "It can reduce overhead and improve performance in some games, "
                                + "but a small number of games may behave differently."
                            )
                        }
                    }
                    .disabled(variables.getVariable("booting") == true)

                    Toggle(
                        isOn: Binding(
                            get: { container.settings.avx2 },
                            set: { container.settings.avx2 = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Advanced CPU instructions")

                            settingDescription(
                                "Allows Wine to expose AVX2 instructions to Windows games. "
                                + "This can help CPU-heavy games, but turning it off may help "
                                + "with compatibility problems."
                            )
                        }
                    }
                    .disabled({
                        if #available(macOS 15.0, *) {
                            return false
                        }

                        return true
                    }())

                    if #unavailable(macOS 15.0) {
                        settingDescription(
                            "Requires macOS 15 or later."
                        )
                    }

                    DisclosureGroup(
                        "Advanced settings",
                        isExpanded: $isAdvancedSectionExpanded
                    ) {
                        if withPicker {
                            VStack(alignment: .leading, spacing: 4) {
                                if variables.getVariable("booting") != true {
                                    Picker(
                                        "Container",
                                        selection: $selectedContainerURL
                                    ) {
                                        ForEach(
                                            Wine.containerObjects
                                                .filter {
                                                    $0.runtimeID == selectedRuntimeID
                                                }
                                                .sorted {
                                                    $0.name.localizedStandardCompare(
                                                        $1.name
                                                    ) == .orderedAscending
                                                }
                                        ) { container in
                                            Text(container.name)
                                                .tag(container.url)
                                        }
                                    }
                                } else {
                                    HStack {
                                        Text("Container")
                                        Spacer()
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }

                                settingDescription(
                                    "Kraken normally chooses a compatible container "
                                    + "automatically. Change this only when testing or "
                                    + "troubleshooting a specific Windows environment."
                                )
                            }
                        }

                        if container.runtimeID == .mythicEngine {
                            Toggle(
                                isOn: Binding(
                                    get: { container.settings.dxvk },
                                    set: { _ in
                                        isDXVKDisclaimerPresented = true
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Alternative graphics renderer")

                                    settingDescription(
                                        "Uses DXVK to translate Direct3D through Vulkan. "
                                        + "It can improve performance or compatibility in some "
                                        + "games, but can also introduce stutter, visual problems, "
                                        + "or lower performance."
                                    )
                                }
                            }
                            .withOperationStatus(
                                operating: $modifyingDXVK,
                                successful: $dxvkSuccess,
                                observing: .constant(false),
                                placement: .leading,
                                action: { }
                            )
                            .alert(
                                "Quit games running in this container?",
                                isPresented: $isDXVKDisclaimerPresented
                            ) {
                                Button("OK", role: .destructive) {
                                    Task(priority: .userInitiated) {
                                        modifyingDXVK = true
                                        defer { modifyingDXVK = false }

                                        do {
                                            if container.settings.dxvk {
                                                try await Wine.boot(
                                                    at: container.url,
                                                    parameters: .update
                                                )
                                            } else {
                                                try await Wine.DXVK.install(
                                                    toContainerAtURL: container.url
                                                )
                                            }

                                            container.settings.dxvk.toggle()
                                            dxvkSuccess = true
                                        } catch {
                                            dxvkSuccess = false
                                        }
                                    }
                                }

                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text(
                                    "Changes the graphics translation system used by "
                                    + "this legacy Engine 2 container. It may help some "
                                    + "games and hurt others."
                                )
                            }

                            if container.settings.dxvk {
                                Toggle(
                                    isOn: Binding(
                                        get: { container.settings.dxvkAsync },
                                        set: { container.settings.dxvkAsync = $0 }
                                    )
                                ) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Background shader work")

                                        settingDescription(
                                            "Changes how DXVK handles shader-related work. "
                                            + "It may reduce stalls in some games, but can also "
                                            + "cause compatibility or stability problems."
                                        )
                                    }
                                }
                                .disabled(modifyingDXVK)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Picker(
                                "Windows compatibility version",
                                selection: $windowsVersion
                            ) {
                                ForEach(
                                    Wine.WindowsVersion.allCases,
                                    id: \.self
                                ) { version in
                                    Text("Windows® \(version.rawValue)")
                                        .tag(version)
                                }
                            }
                            .task(priority: .high) {
                                await fetchWindowsVersion()
                            }
                            .withOperationStatus(
                                operating: $modifyingWindowsVersion,
                                successful: $windowsVersionSuccess,
                                observing: $windowsVersion,
                                placement: .leading
                            ) {
                                do {
                                    try await Wine.setWindowsVersion(
                                        containerURL: container.url,
                                        version: windowsVersion,
                                        runtimeID: container.runtimeID
                                    )

                                    container.settings.windowsVersion =
                                        windowsVersion
                                    windowsVersionSuccess = true
                                } catch {
                                    windowsVersionSuccess = false
                                }
                            }

                            settingDescription(
                                "Controls which version of Windows Wine reports to the game. "
                                + "Most games should use the default. Some older games may work "
                                + "better with a different compatibility version."
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                .disabled(!Engine.isRuntimeInstalled(container.runtimeID))
                .id(selectedContainerURL)
            } else {
                if withPicker {
                    DisclosureGroup(
                        "Advanced settings",
                        isExpanded: $isAdvancedSectionExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(
                                "Container",
                                selection: $selectedContainerURL
                            ) {
                                ForEach(
                                    Wine.containerObjects
                                        .filter {
                                            $0.runtimeID == selectedRuntimeID
                                        }
                                        .sorted {
                                            $0.name.localizedStandardCompare(
                                                $1.name
                                            ) == .orderedAscending
                                        }
                                ) { container in
                                    Text(container.name)
                                        .tag(container.url)
                                }
                            }

                            settingDescription(
                                "Kraken normally selects a compatible container "
                                + "automatically. Choose one manually only when "
                                + "testing or troubleshooting."
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }

                ContentUnavailableView(
                    "No Windows environment selected",
                    systemImage: "shippingbox",
                    description: Text(
                        "Kraken could not find a compatible Windows environment "
                        + "for this game yet."
                    )
                )
            }
        }
        .onAppear {
            ensureCompatibleContainer()
        }
    }
}

#Preview {
    Form {
        ContainerSettingsView(
            selectedContainerURL: Binding(
                get: { Wine.containerURLs.first },
                set: { _ in }
            ),
            withPicker: true
        )
    }
    .formStyle(.grouped)
}
