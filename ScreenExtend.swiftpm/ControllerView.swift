import SwiftUI
import WebKit

/// Everything shown on the iPad screen.
struct ControllerView: View {
    @ObservedObject private var model = BrowserModel.shared
    @StateObject private var dimmer = ScreenDimmer()

    @State private var urlText = ""
    @State private var typedText = ""
    @State private var suppressTypingDiff = false
    @State private var previewMode: PreviewMode = .preview
    @State private var forceSpeaker = false
    @State private var showLibrary = false
    @State private var screenCount = UIScreen.screens.count
    @ObservedObject private var library = LibraryStore.shared
    @FocusState private var urlFocused: Bool
    @FocusState private var typingFocused: Bool

    enum PreviewMode: String, CaseIterable { case preview = "Preview", trackpad = "Trackpad" }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if urlFocused && !urlText.isEmpty {
                suggestionsBar
            }
            HStack(spacing: 12) {
                actionBar
                statusBar
            }
            mainArea
            keyboardBar
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .onAppear { model.ensureTab() }
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .onChange(of: model.activeTab?.url) { _, newURL in
            if !urlFocused { urlText = newURL?.absoluteString ?? "" }
        }
        .onChange(of: model.activeTabID) { _, _ in
            urlText = model.activeTab?.url?.absoluteString ?? ""
        }
        .onChange(of: urlFocused) { _, focused in
            // Select the whole URL when the field gains focus, like Safari.
            guard focused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .onChange(of: model.externalDisplayConnected) { _, connected in
            if !connected { dimmer.restore() }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!(model.activeTab?.canGoBack ?? false))
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!(model.activeTab?.canGoForward ?? false))
            Button {
                if model.activeTab?.isLoading == true { model.stop() } else { model.reload() }
            } label: {
                Image(systemName: model.activeTab?.isLoading == true ? "xmark" : "arrow.clockwise")
            }

            HStack(spacing: 6) {
                if model.activeTab?.isIncognito == true {
                    Image(systemName: "eyeglasses").foregroundStyle(.secondary)
                }
                TextField("Search or enter website", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($urlFocused)
                    .onSubmit {
                        model.navigate(to: urlText)
                        urlFocused = false
                    }
                if model.activeTab?.isLoading == true {
                    ProgressView(value: model.activeTab?.progress ?? 0)
                        .frame(width: 60)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .layoutPriority(1)

            tabsMenu

            Button { model.newTab() } label: { Image(systemName: "plus") }
                .help("New tab")
            Button { model.toggleBookmarkForCurrentPage() } label: {
                Image(systemName: library.isBookmarked(model.activeTab?.url) ? "star.fill" : "star")
            }
            .disabled(model.activeTab?.url == nil)
            .accessibilityLabel("Bookmark this page")
            .help("Bookmark this page")
            Button { showLibrary = true } label: { Image(systemName: "book") }
                .accessibilityLabel("Library")
                .help("Bookmarks and history")
            Button { model.privateBrowsing.toggle() } label: { Image(systemName: "eyeglasses") }
                .tint(model.privateBrowsing ? .purple : nil)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Private browsing")
                .help(model.privateBrowsing ? "Private browsing is on: new tabs remember nothing" : "Private browsing is off")

        }
        .font(.title3)
        .buttonStyle(.bordered)
    }

    /// Matches from bookmarks and history while typing in the address bar.
    private var suggestionsBar: some View {
        let items = library.suggestions(for: urlText)
        return Group {
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                model.navigate(to: item.url.absoluteString)
                                urlFocused = false
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title.isEmpty ? (item.url.host ?? "") : item.title).lineLimit(1)
                                        Text(item.url.host ?? item.url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                } icon: {
                                    Image(systemName: item.kind == .bookmark ? "star.fill" : "clock")
                                }
                                .frame(maxWidth: 260, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    /// Second row: page actions that don't need to crowd the URL bar.
    private var actionBar: some View {
        HStack(spacing: 8) {
            Button { model.fillScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Fill monitor with the video")
            Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out")
            Button { model.resetZoom() } label: {
                Text("\(Int((model.pageZoom * 100).rounded()))%").font(.footnote.monospacedDigit()).frame(minWidth: 44)
            }
            .help("Reset zoom")
            Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in")
            RoutePickerView()
                .frame(width: 32, height: 32)
                .help("Audio output")
            Button { dimmer.toggle() } label: {
                Image(systemName: dimmer.isDimmed ? "sun.max.fill" : "moon.fill")
            }
            .disabled(!model.externalDisplayConnected)
            .help("Dim iPad screen")
        }
        .buttonStyle(.bordered)
    }

    private var tabsMenu: some View {
        Menu {
            ForEach(model.tabs) { tab in
                Button {
                    model.select(tab)
                } label: {
                    Label {
                        Text(tab.displayTitle)
                    } icon: {
                        Image(systemName: tab.id == model.activeTabID ? "checkmark.circle.fill" : (tab.isIncognito ? "eyeglasses" : "globe"))
                    }
                }
            }
            Divider()
            if let tab = model.activeTab {
                Button(role: .destructive) { model.closeTab(tab) } label: {
                    Label("Close current tab", systemImage: "xmark")
                }
            }
            Toggle("Force iPad speaker (fallback)", isOn: Binding(
                get: { forceSpeaker },
                set: { on in forceSpeaker = on; AudioManager.shared.forceBuiltInSpeaker(on) }
            ))
        } label: {
            Label("\(model.tabs.count)", systemImage: "square.on.square")
        }
    }

    // MARK: Status

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.activeTab?.isIncognito == true {
                Label("Private", systemImage: "eyeglasses").foregroundStyle(.purple)
            }
            if model.externalDisplayConnected {
                Label(monitorLabel, systemImage: "display")
                    .foregroundStyle(.green)
            } else {
                Label("No monitor detected (iOS reports \(screenCount) screen\(screenCount == 1 ? "" : "s")). Connect HDMI, or use the preview below.",
                      systemImage: "display.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                    .onReceive(NotificationCenter.default.publisher(for: UIScreen.didConnectNotification)) { _ in screenCount = UIScreen.screens.count }
                    .onReceive(NotificationCenter.default.publisher(for: UIScreen.didDisconnectNotification)) { _ in screenCount = UIScreen.screens.count }
                Picker("", selection: $previewMode) {
                    ForEach(PreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Spacer()

            if let popup = model.blockedPopupURL {
                Button {
                    model.openBlockedPopup()
                } label: {
                    Label("Open popup: \(popup.host ?? popup.absoluteString)", systemImage: "rectangle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                Button { model.blockedPopupURL = nil } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
            }

            if let message = model.lastMessage {
                Text(message)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Button { model.lastMessage = nil } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
            }
        }
        .font(.footnote)
    }

    private var monitorLabel: String {
        if let size = model.monitorSize {
            return "Monitor connected · \(Int(size.width))×\(Int(size.height)) pt"
        }
        return "Monitor connected"
    }

    // MARK: Main area

    @ViewBuilder
    private var mainArea: some View {
        if model.externalDisplayConnected || previewMode == .trackpad {
            ZStack {
                TrackpadView()
                VStack(spacing: 6) {
                    Text("Trackpad")
                        .font(.headline)
                    Text("Drag to move · Tap to click · Two fingers to scroll · Two-finger tap to exit fullscreen")
                        .font(.footnote)
                }
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebPreview(webView: WKWebViewBox(value: model.activeTab?.webView))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Keyboard forwarding

    private var keyboardBar: some View {
        HStack(spacing: 8) {
            TextField("Type into the page (click a field on the monitor first)", text: $typedText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($typingFocused)
                .onChange(of: typedText) { old, new in
                    forwardTyping(old: old, new: new)
                }
                .onSubmit {
                    model.pressEnter()
                    resetTyped()
                    typingFocused = true
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Button { model.deleteBackward() } label: { Image(systemName: "delete.left") }
            Button { model.pressEnter(); resetTyped() } label: { Image(systemName: "return") }
            Button { model.escape(); resetTyped() } label: { Text("Esc") }
        }
        .buttonStyle(.bordered)
    }

    /// Diff the text field against its previous value and forward only the change.
    private func forwardTyping(old: String, new: String) {
        if suppressTypingDiff { return }
        if new.hasPrefix(old) {
            model.insertText(String(new.dropFirst(old.count)))
        } else if old.hasPrefix(new) {
            model.deleteBackward(old.count - new.count)
        } else {
            model.deleteBackward(old.count)
            model.insertText(new)
        }
    }

    private func resetTyped() {
        suppressTypingDiff = true
        typedText = ""
        DispatchQueue.main.async { suppressTypingDiff = false }
    }
}

#Preview {
    ControllerView()
}
