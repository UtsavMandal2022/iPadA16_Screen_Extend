import WebKit
import Combine

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let isIncognito: Bool
    let webView: WKWebView

    @Published private(set) var url: URL?
    @Published private(set) var title: String = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0

    private var observers: [NSKeyValueObservation] = []

    init(incognito: Bool, ruleList: WKContentRuleList?) {
        isIncognito = incognito
        webView = WebViewFactory.make(incognito: incognito, ruleList: ruleList)
        super.init()

        observers = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.url = wv.url }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.title = wv.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.isLoading = wv.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.progress = wv.estimatedProgress }
            },
        ]
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host { return host }
        return isIncognito ? "Incognito" : "New Tab"
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }
}
