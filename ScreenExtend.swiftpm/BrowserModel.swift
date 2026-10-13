import WebKit
import Combine
import UIKit

/// Single source of truth shared by the controller scene (iPad) and the monitor scene (HDMI).
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    static let shared = BrowserModel()

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var activeTabID: UUID?

    /// Cursor position normalised to 0...1 of the browser surface, so it is independent of monitor size.
    @Published var cursor = CGPoint(x: 0.5, y: 0.5)
    @Published var cursorVisible = true

    @Published var externalDisplayConnected = false
    /// Size (in points) of the browser surface on the monitor; set by MonitorViewController.
    @Published var monitorSize: CGSize?

    /// Set when a page tried to open a popup window. The controller offers to open it.
    @Published var blockedPopupURL: URL?
    @Published var lastMessage: String?

    /// When on (the default), new tabs persist nothing and history is not recorded.
    @Published var privateBrowsing: Bool = UserDefaults.standard.object(forKey: "privateBrowsing") as? Bool ?? true {
        didSet { UserDefaults.standard.set(privateBrowsing, forKey: "privateBrowsing") }
    }

    let library = LibraryStore.shared
    private var tabObservers: [UUID: AnyCancellable] = [:]

    var cursorSensitivity: CGFloat = 1.6
    var scrollSensitivity: CGFloat = 2.0

    /// Page zoom applied to every tab (1.0 = 100%). Persisted.
    @Published var pageZoom: CGFloat = UserDefaults.standard.object(forKey: "pageZoom") as? CGFloat ?? 0 {
        didSet {
            UserDefaults.standard.set(pageZoom, forKey: "pageZoom")
            for tab in tabs { applyZoom(to: tab.webView) }
        }
    }

    private var ruleList: WKContentRuleList?
    private var cursorHideTask: Task<Void, Never>?
    private var lastHoverSent: TimeInterval = 0

    private let homeURL = URL(string: "https://www.google.com")!

    private override init() {
        super.init()
        Task { [weak self] in
            let list = await WebViewFactory.compileRuleList()
            guard let self, let list else { return }
            self.ruleList = list
            for tab in self.tabs {
                tab.webView.configuration.userContentController.add(list)
            }
        }
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    // MARK: - Tabs

    /// Opens a tab. `incognito` defaults to the current private-browsing setting.
    @discardableResult
    func newTab(incognito: Bool? = nil, url: URL? = nil) -> BrowserTab {
        let tab = BrowserTab(incognito: incognito ?? privateBrowsing, ruleList: ruleList)
        if !tab.isIncognito {
            // Keep history titles current once the page reports one.
            tabObservers[tab.id] = tab.$title
                .dropFirst()
                .sink { [weak self, weak tab] title in
                    guard let tab, let url = tab.url else { return }
                    self?.library.updateTitle(for: url, title: title)
                }
        }
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        if pageZoom == 0 { pageZoom = defaultZoom(for: monitorSize) }
        tabs.append(tab)
        activeTabID = tab.id
        tab.load(url ?? homeURL)
        return tab
    }

    /// Sensible starting zoom: ~1x on a 1080p monitor, ~2x on 4K.
    func defaultZoom(for size: CGSize?) -> CGFloat {
        guard let size, size.width > 0 else { return 1.0 }
        let zoom = (size.width / 1920).rounded(.down)
        return max(1.0, min(3.0, zoom == 0 ? 1.0 : zoom))
    }

    func applyZoom(to webView: WKWebView) {
        webView.evaluateJavaScript("window.__se && window.__se.setZoom(\(pageZoom))") { _, _ in }
    }

    func zoomIn()  { pageZoom = min(3.0, (pageZoom + 0.1).rounded(toPlaces: 1)) }
    func zoomOut() { pageZoom = max(0.5, (pageZoom - 0.1).rounded(toPlaces: 1)) }
    func resetZoom() { pageZoom = defaultZoom(for: monitorSize) }

    func select(_ tab: BrowserTab) {
        activeTabID = tab.id
    }

    func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.webView.stopLoading()
        tab.webView.removeFromSuperview()
        tabObservers[tab.id] = nil
        tabs.remove(at: index)

        if tabs.isEmpty {
            // Closing the last tab: start a fresh one rather than leaving nothing to show.
            newTab()
            return
        }
        if activeTabID == tab.id {
            let neighbour = min(index, tabs.count - 1)
            activeTabID = tabs[neighbour].id
        }
    }

    func ensureTab() {
        if tabs.isEmpty { newTab() }
    }

    func toggleBookmarkForCurrentPage() {
        guard let tab = activeTab, let url = tab.url else { return }
        let added = library.toggleBookmark(url: url, title: tab.title)
        lastMessage = added ? "Bookmarked." : "Bookmark removed."
    }

    // MARK: - Navigation

    func navigate(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let tab = activeTab else { newTab(url: resolve(text)); return }
        tab.load(resolve(text))
    }

    private func resolve(_ text: String) -> URL {
        if let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return url
        }
        let looksLikeHost = !text.contains(" ") && text.contains(".")
        if looksLikeHost, let url = URL(string: "https://" + text) {
            return url
        }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://www.google.com/search?q=\(query)")!
    }

    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }
    func reload() { activeTab?.webView.reload() }
    func stop() { activeTab?.webView.stopLoading() }

    func openBlockedPopup() {
        guard let url = blockedPopupURL else { return }
        blockedPopupURL = nil
        newTab(incognito: activeTab?.isIncognito ?? privateBrowsing, url: url)
    }

    // MARK: - Virtual cursor

    private var surfaceSize: CGSize {
        if let size = monitorSize, size.width > 0, size.height > 0 { return size }
        if let bounds = activeTab?.webView.bounds, bounds.width > 0, bounds.height > 0 { return bounds.size }
        return CGSize(width: 1180, height: 820)
    }

    func moveCursor(by delta: CGPoint) {
        let size = surfaceSize
        var p = cursor
        p.x = min(1, max(0, p.x + delta.x * cursorSensitivity / size.width))
        p.y = min(1, max(0, p.y + delta.y * cursorSensitivity / size.height))
        cursor = p
        showCursorBriefly()

        let now = Date().timeIntervalSince1970
        if now - lastHoverSent > 0.05 {
            lastHoverSent = now
            evaluate("window.__se && window.__se.norm('hover', \(cursor.x), \(cursor.y))")
        }
    }

    func click() {
        showCursorBriefly()
        let js = """
        (function(){ if (!window.__se) return 'nobridge';
          window.__se.norm('click', \(cursor.x), \(cursor.y));
          var a = document.activeElement;
          return 'active=' + (a ? a.tagName + '#' + a.id : 'null') + ' vp=' + window.innerWidth + 'x' + window.innerHeight; })()
        """
        activeTab?.webView.evaluateJavaScript(js) { result, error in
            NSLog("SE click %@ %@", (result as? String) ?? "nil", error?.localizedDescription ?? "")
        }
    }

    /// `delta` is the finger movement; content follows the fingers (natural scrolling).
    func scroll(by delta: CGPoint) {
        guard let tab = activeTab else { return }
        let zoom = max(0.01, tab.webView.scrollView.zoomScale)
        let dx = -delta.x * scrollSensitivity / zoom
        let dy = -delta.y * scrollSensitivity / zoom
        evaluate("window.__se && window.__se.norm('scroll', \(cursor.x), \(cursor.y), \(dx), \(dy))")
    }

    private func showCursorBriefly() {
        cursorVisible = true
        cursorHideTask?.cancel()
        cursorHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.cursorVisible = false
        }
    }

    // MARK: - Virtual keyboard

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        evaluate("window.__se && window.__se.insertText(\(jsString(text)))")
    }

    func deleteBackward(_ count: Int = 1) {
        evaluate("window.__se && window.__se.deleteBackward(\(max(1, count)))")
    }

    func pressEnter() {
        evaluate("window.__se && window.__se.pressEnter()")
    }

    func escape() {
        evaluate("window.__se && window.__se.escape()")
    }

    func fillScreen() {
        guard let webView = activeTab?.webView else { return }
        webView.evaluateJavaScript("window.__se ? window.__se.fillScreen() : 'nobridge'") { [weak self] result, _ in
            MainActor.assumeIsolated {
                switch result as? String {
                case "novideo": self?.lastMessage = "No video found on this page."
                case "nobridge": self?.lastMessage = "Page not ready yet."
                default: self?.lastMessage = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private func evaluate(_ js: String) {
        activeTab?.webView.evaluateJavaScript(js) { _, error in
            if let error { print("JS error: \(error.localizedDescription)") }
        }
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // target="_blank" links have no target frame; open them in the same tab.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        applyZoom(to: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyZoom(to: webView)
        if let tab = tabs.first(where: { $0.webView === webView }), !tab.isIncognito, let url = webView.url {
            library.record(url: url, title: webView.title ?? "")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        lastMessage = error.localizedDescription
    }
}

// MARK: - WKUIDelegate

extension BrowserModel: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme != nil, url.absoluteString != "about:blank" {
            blockedPopupURL = url
            lastMessage = "Popup blocked."
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        lastMessage = message
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        lastMessage = message
        completionHandler(true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(defaultText)
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10.0, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}
