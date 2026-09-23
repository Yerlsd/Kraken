import SwiftUI

/// Kraken's primary navigation shell.
///
/// Navigation stays in a native macOS sidebar while the content area remains
/// independently resizable. The shell deliberately avoids fixed-width content
/// so the UI remains usable on both a laptop and a large external display.
struct ContentView: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @ObservedObject private var updateController: SparkleUpdateController = .shared
    @Bindable private var operationManager: GameOperationManager = .shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } detail: {
            HomeView()
                .frame(minWidth: 620, minHeight: 420)
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
            List {
                Section("Play") {
                    NavigationLink(destination: HomeView()) {
                        Label("Home", systemImage: "house.fill")
                    }
                    NavigationLink(destination: LibraryView()) {
                        Label("Library", systemImage: "square.grid.2x2.fill")
                    }
                    NavigationLink(destination: StoreView()) {
                        Label("Store", systemImage: "bag.fill")
                    }
                }

                Section("Manage") {
                    NavigationLink(destination: ContainersView()) {
                        Label("Containers", systemImage: "shippingbox.fill")
                    }
                    NavigationLink(destination: AccountsView()) {
                        Label("Accounts", systemImage: "person.2.fill")
                    }
                    Button {
                        SupportWindowController.show()
                    } label: {
                        Label("Support", systemImage: "questionmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }

                if !operationManager.queue.isEmpty {
                    Section("Activity") {
                        NavigationLink(destination: OperationsView()) {
                            Label("Operations", systemImage: "arrow.down.circle.fill")
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 10) {
                Image("KrakenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: 8))
                    .shadow(radius: 3, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Kraken")
                        .font(.headline)
                    Text("Windows gaming on Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            switch updateController.state {
            case .updateAvailable:
                updateBanner(title: "Update available", actionTitle: "View") {
                    updateController.checkForUpdates(userInitiated: true)
                }
            case .readyToRelaunch(let acknowledgement):
                updateBanner(title: "Update ready", actionTitle: "Relaunch") {
                    acknowledgement(.update)
                }
            default:
                EmptyView()
            }
        }
    }

    private func updateBanner(
        title: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkMonitor.shared)
}
