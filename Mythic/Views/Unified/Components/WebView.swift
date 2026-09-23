//
//  WebView.swift
//  Kraken
//

import SwiftUI
import WebKit
import OSLog

@MainActor
final class StoreBrowserController: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?

    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        if self.webView === webView {
            synchronize(with: webView)
            return
        }

        self.webView = webView
        observations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] observedView, _ in
                MainActor.assumeIsolated {
                    self?.synchronize(with: observedView)
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] observedView, _ in
                MainActor.assumeIsolated {
                    self?.synchronize(with: observedView)
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] observedView, _ in
                MainActor.assumeIsolated {
                    self?.synchronize(with: observedView)
                }
            }
        ]
        synchronize(with: webView)
    }

    func goBack() {
        guard webView?.canGoBack == true else { return }
        webView?.goBack()
    }

    func goForward() {
        guard webView?.canGoForward == true else { return }
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    fileprivate func navigationDidChange(_ webView: WKWebView) {
        synchronize(with: webView)
    }

    private func synchronize(with webView: WKWebView) {
        let canGoBack = webView.canGoBack
        if self.canGoBack != canGoBack {
            self.canGoBack = canGoBack
        }

        let canGoForward = webView.canGoForward
        if self.canGoForward != canGoForward {
            self.canGoForward = canGoForward
        }

        let currentURL = webView.url
        if self.currentURL != currentURL {
            self.currentURL = currentURL
        }
    }
}

struct WebView: NSViewRepresentable {
    let url: URL
    var datastore: WKWebsiteDataStore = .default()
    @ObservedObject var browser: StoreBrowserController
    @Binding var error: Error?

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yerlsd.kraken",
        category: "WebView"
    )

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = datastore

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        browser.attach(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        browser.attach(nsView)

        guard context.coordinator.requestedURL != url else { return }
        context.coordinator.requestedURL = url
        nsView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var requestedURL: URL?

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.error = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            parent.log.error("\(error.localizedDescription)")
            parent.error = error
            parent.browser.navigationDidChange(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.error = nil
            parent.browser.navigationDidChange(webView)
        }
    }
}

#Preview {
    Group {
        if let url = URL(string: "https://example.com") {
            WebView(
                url: url,
                browser: StoreBrowserController(),
                error: .constant(nil)
            )
        }
    }
}
