import SwiftUI
import AppKit
import SemanticVersion

struct AboutView: View {
    @State private var engineVersion: SemanticVersion?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                BundleIconView()
                    .frame(width: 92, height: 92)
                    .clipShape(.rect(cornerRadius: 22))
                    .shadow(radius: 10, y: 5)

                Text("Kraken")
                    .font(.largeTitle.bold())

                Text("A native macOS launcher for Windows games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    versionPill(title: "Kraken", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                    if let engineVersion {
                        versionPill(title: "Engine", value: engineVersion.prettyString)
                    }
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)

            Divider()
                .padding(.vertical, 22)

            VStack(alignment: .leading, spacing: 12) {
                Text("About Kraken")
                    .font(.headline)
                Text("Kraken brings Windows game launching, Wine containers and compatibility tooling together in one focused Mac application.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                acknowledgement(title: "CodeWeavers & Wine", detail: "The Wine technology that provides the Windows compatibility layer.", url: "https://www.codeweavers.com/")
                acknowledgement(title: "Whisky", detail: "An important foundation for the compatibility tooling Kraken builds on.", url: "https://getwhisky.app/")
                acknowledgement(title: "Kraken source", detail: "View the project, releases and development updates.", url: "https://github.com/Yerlsd/Kraken")
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            Text("© Kraken contributors")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
        }
        .frame(width: 390, height: 560)
        .background(.regularMaterial)
        .task {
            engineVersion = await Engine.installedVersion
        }
    }

    private func versionPill(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: .capsule)
    }

    private func acknowledgement(title: String, detail: String, url: String) -> some View {
        Button {
            if let destination = URL(string: url) {
                NSWorkspace.shared.open(destination)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView()
}
