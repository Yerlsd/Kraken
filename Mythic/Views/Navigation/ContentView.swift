//
//  ContentView.swift
//  Kraken
//

import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @ObservedObject private var updateController: SparkleUpdateController = .shared
    @Bindable private var operationManager: GameOperationManager = .shared

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            HomeView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .status) {
                if !networkMonitor.isConnected {
                    Label("Offline", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                        .help("Kraken is not connected to the internet.")
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("KrakenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text("Kraken")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            List {
                Section("Library") {
                    NavigationLink(destination: HomeView()) {
                        Label("Home", systemImage: "house")
                    }

                    NavigationLink(destination: LibraryView()) {
                        Label("Library", systemImage: "square.grid.2x2")
                    }
                }

                Section("Manage") {
                    NavigationLink(destination: ContainersView()) {
                        Label("Containers", systemImage: "shippingbox")
                    }

                    NavigationLink(destination: AccountsView()) {
                        Label("Accounts", systemImage: "person.2")
                    }
                }

                Section("More") {
                    NavigationLink(destination: StoreView()) {
                        Label("Store", systemImage: "bag")
                    }

                    Button {
                        SupportWindowController.show()
                    } label: {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !operationManager.queue.isEmpty {
                Divider()

                NavigationLink(destination: OperationsView()) {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.down.circle")
                        Text("Operations")
                        Spacer()
                        Text("\(operationManager.queue.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            switch updateController.state {
            case .updateAvailable:
                updateBlock("Update Available", buttonText: "Show More") {
                    updateController.checkForUpdates(userInitiated: true)
                }
            case .readyToRelaunch(let acknowledgement):
                updateBlock("Update Ready", buttonText: "Relaunch") {
                    acknowledgement(.update)
                }
            default:
                EmptyView()
            }
        }
    }

    private func updateBlock(
        _ title: String,
        buttonText: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "arrow.down.app")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(buttonText, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkMonitor.shared)
}
