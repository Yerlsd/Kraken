//
//  ContainersView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 12/9/2023.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import SwordRPC

struct ContainersView: View {
    @State private var isContainerCreationViewPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Containers")
                        .font(.largeTitle.bold())
                    Text("Manage the Windows environments and runtimes used by your games.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !Wine.containerObjects.isEmpty {
                    Label("\(Wine.containerObjects.count) container\(Wine.containerObjects.count == 1 ? "" : "s")", systemImage: "shippingbox")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ContainerListView()
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Containers")
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Managing game containers"
                presence.state = "Managing containers"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"

                return presence
            }())
        }

        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if Engine.isInstalled {
                    Button {
                        isContainerCreationViewPresented = true
                    } label: {
                        Label("New Container", systemImage: "plus")
                    }
                    .help("Create a Wine container")
                }

                if let containersDirectory = Wine.containersDirectory {
                    Button {
                        NSWorkspace.shared.open(containersDirectory)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .help("Open the containers folder in Finder")
                }
            }
        }
        .sheet(isPresented: $isContainerCreationViewPresented) {
            ContainerCreationView(isPresented: $isContainerCreationViewPresented)
        }
    }
}

#Preview {
    ContainersView()
}
