import SwiftUI
import AppKit
import SwordRPC

/// Storefront account workspace. Epic has a real web-auth flow; Steam currently
/// uses the local Steam client, so the UI is honest about that distinction rather
/// than pretending Kraken has a Steam OAuth account system it does not have.
struct AccountsView: View {
    @ObservedObject private var epicWebAuthViewModel: EpicWebAuthViewModel = .shared

    @State private var isEpicSignOutConfirmationAlertPresented = false
    @State private var epicSignOutError: Error?
    @State private var isEpicSignOutErrorAlertPresented = false
    @State private var refreshID = UUID()

    private var steamInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") != nil
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Accounts")
                        .font(.largeTitle.bold())
                    Text("Connect the stores Kraken uses to build your unified library.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 18)],
                    spacing: 18
                ) {
                    epicCard
                    steamCard
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Why Steam looks different", systemImage: "info.circle")
                        .font(.headline)
                    Text("Kraken currently discovers Steam games from the Steam installation and local app manifests. It does not need a separate Steam web login for that workflow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(.rect(cornerRadius: 16))
            }
            .padding(28)
        }
        .navigationTitle("Accounts")
        .background(Color(nsColor: .windowBackgroundColor))
        .id(refreshID)
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Managing accounts"
                presence.state = "Accounts"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }

    private var epicCard: some View {
        let signedInUser = try? Legendary.retrieveUser()

        return AccountCard(
            title: "Epic Games",
            subtitle: signedInUser.map { "Signed in as \($0)" } ?? "Not signed in",
            image: Image("EGFaceless"),
            tint: .purple,
            status: signedInUser != nil ? "Connected" : "Not connected",
            statusIcon: signedInUser != nil ? "checkmark.circle.fill" : "person.crop.circle",
            actionTitle: signedInUser != nil ? "Sign Out" : "Sign In",
            actionIcon: signedInUser != nil ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.plus",
            actionRole: signedInUser != nil ? .destructive : nil,
            action: {
                if signedInUser != nil {
                    isEpicSignOutConfirmationAlertPresented = true
                } else {
                    epicWebAuthViewModel.showSignInWindow()
                }
            }
        )
        .alert("Sign out of Epic Games?", isPresented: $isEpicSignOutConfirmationAlertPresented) {
            Button("Sign Out", role: .destructive) {
                Task { @MainActor in
                    do {
                        try await Legendary.signOut()
                        refreshID = UUID()
                    } catch {
                        epicSignOutError = error
                        isEpicSignOutErrorAlertPresented = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Unable to sign out", isPresented: $isEpicSignOutErrorAlertPresented, presenting: epicSignOutError) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var steamCard: some View {
        AccountCard(
            title: "Steam",
            subtitle: steamInstalled ? "Steam is installed on this Mac" : "Steam was not detected",
            image: Image("Steam"),
            tint: .blue,
            status: steamInstalled ? "Detected" : "Unavailable",
            statusIcon: steamInstalled ? "checkmark.circle.fill" : "exclamationmark.circle",
            actionTitle: steamInstalled ? "Open Steam" : "Install Steam",
            actionIcon: "arrow.up.right.square",
            actionRole: nil,
            action: {
                if steamInstalled {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Steam.app"))
                } else if let url = URL(string: "https://store.steampowered.com/about/") {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }

    private struct AccountCard: View {
        let title: String
        let subtitle: String
        let image: Image
        let tint: Color
        let status: String
        let statusIcon: String
        let actionTitle: String
        let actionIcon: String
        let actionRole: ButtonRole?
        let action: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .clipShape(.rect(cornerRadius: 14))
                        .background(.quaternary, in: .rect(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.title2.bold())
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                Divider()

                HStack {
                    Label(status, systemImage: statusIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tint)
                    Spacer()
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(.capsule)
                    .tint(tint)
                    .role(actionRole)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 20))
        }
    }
}

#Preview {
    AccountsView()
}
