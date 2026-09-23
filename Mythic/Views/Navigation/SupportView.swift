//
//  SupportView.swift
//  Kraken
//

import SwiftUI
import AppKit
import SwordRPC

struct SupportView: View {
    private let resources = [
        SupportResource(
            title: "Project on GitHub",
            detail: "Source code, releases, and development updates.",
            action: "Open Repository",
            symbol: "chevron.left.forwardslash.chevron.right",
            tint: .primary,
            urlString: "https://github.com/Yerlsd/Kraken"
        ),
        SupportResource(
            title: "Kraken Releases",
            detail: "Download the latest available version of Kraken.",
            action: "View Releases",
            symbol: "arrow.down.app",
            tint: .blue,
            urlString: "https://github.com/Yerlsd/Kraken/releases"
        ),
        SupportResource(
            title: "Community Support",
            detail: "Ask questions and share game compatibility findings.",
            action: "Open Discord",
            symbol: "bubble.left.and.bubble.right",
            tint: .indigo,
            urlString: "https://discord.gg/kQKdvjTVqh"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Support")
                        .font(.largeTitle.bold())
                    Text("Find Kraken updates and community help.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(resources) { resource in
                        SupportResourceCard(resource: resource)
                    }
                }

                Label {
                    Text("When asking for help, include the game title, your macOS version, and relevant launch details. Do not share account credentials or private account files.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Support")
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence = RichPresence()
                presence.details = "Finding Kraken support"
                presence.state = "Support"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                return presence
            }())
        }
    }
}

private struct SupportResource: Identifiable {
    let title: String
    let detail: String
    let action: String
    let symbol: String
    let tint: Color
    let urlString: String

    var id: String { title }
}

private struct SupportResourceCard: View {
    let resource: SupportResource

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: resource.symbol)
                .font(.title2)
                .foregroundStyle(resource.tint)
                .frame(width: 42, height: 42)
                .background(resource.tint.opacity(0.10), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(resource.title)
                    .font(.headline)
                Text(resource.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let destination = URL(string: resource.urlString) {
                Link(destination: destination) {
                    Label(resource.action, systemImage: "arrow.up.right")
                        .font(.callout.weight(.medium))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .padding(18)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }
}

public final class SupportWindowController: NSWindowController {
    static var shared: SupportWindowController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kraken Support"
        window.minSize = NSSize(width: 560, height: 420)
        window.contentViewController = NSHostingController(rootView: SupportView())
        window.center()
        self.init(window: window)
    }

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let controller = SupportWindowController()
            shared = controller
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#Preview {
    SupportView()
}
