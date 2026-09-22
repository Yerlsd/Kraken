import SwiftUI
import Sparkle
import WhatsNewKit

@main
struct KrakenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("isOnboardingPresented") var isOnboardingPresented: Bool = true
    @StateObject private var networkMonitor: NetworkMonitor = .shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Kraken", id: "main") {
            Group {
                if isOnboardingPresented {
                    OnboardingView()
                        .task(priority: .high) {
                            await MainActor.run {
                                NSApp.mainWindow?.isImmersive = true
                            }
                        }
                } else {
                    ContentView()
                        .whatsNewSheet()
                        .environmentObject(networkMonitor)
                        .task(priority: .high) {
                            await MainActor.run {
                                NSApp.mainWindow?.isImmersive = false
                            }
                        }
                }
            }
            .modifier(SparkleUpdater())
            .frame(minWidth: 980, minHeight: 620)
        }
        .handlesExternalEvents(matching: ["open"])
        .environment(
            \.whatsNew,
            WhatsNewEnvironment(
                versionStore: {
#if DEBUG
                    InMemoryWhatsNewVersionStore()
#else
                    UserDefaultsWhatsNewVersionStore()
#endif
                }(),
                whatsNewCollection: self
            )
        )
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Kraken") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Kraken Updates…") {
                    SparkleUpdateController.shared.checkForUpdates(userInitiated: true)
                }

                Button("Check for Kraken Engine Updates…") {
                    Task(priority: .userInitiated) {
                        await Engine.displayUpdateChecker(userInitiated: true)
                    }
                }

                Button("Restart Onboarding…") {
                    withAnimation {
                        isOnboardingPresented = true
                    }
                }
                .disabled(isOnboardingPresented)
            }

            CommandGroup(replacing: .help) {
                Link("Kraken on GitHub", destination: URL(string: "https://github.com/Yerlsd/Kraken")!)
                Link("Report an Issue…", destination: URL(string: "https://github.com/Yerlsd/Kraken/issues/new")!)
                Link("Compatibility Database", destination: URL(string: "https://github.com/Yerlsd/Kraken#compatibility")!)
            }
        }

        Window("About Kraken", id: "about") {
            AboutView()
                .onAppear {
                    if let window = NSApp.window(withID: "about") {
                        window.isImmersive = true
                    }
                }
        }

        Settings {
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkMonitor.shared)
}
