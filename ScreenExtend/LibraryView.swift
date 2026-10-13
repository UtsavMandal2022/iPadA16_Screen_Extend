import SwiftUI

/// Bookmarks and history sheet.
struct LibraryView: View {
    @ObservedObject var library = LibraryStore.shared
    @ObservedObject var model = BrowserModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var section: Section = .bookmarks
    @State private var search = ""
    @State private var confirmClearHistory = false
    @State private var confirmClearData = false
    @State private var clearedMessage: String?

    enum Section: String, CaseIterable { case bookmarks = "Bookmarks", history = "History" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if section == .bookmarks { bookmarksList } else { historyList }
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmClearHistory = true } label: {
                            Label("Clear history", systemImage: "clock.arrow.circlepath")
                        }
                        Button(role: .destructive) { confirmClearData = true } label: {
                            Label("Clear cookies & site data", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Clear all browsing history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) {
                    library.clearHistory()
                    clearedMessage = "History cleared."
                }
            }
            .confirmationDialog("Clear cookies, cache and site data for normal tabs? You will be signed out of websites.",
                                isPresented: $confirmClearData, titleVisibility: .visible) {
                Button("Clear site data", role: .destructive) {
                    Task {
                        await library.clearWebsiteData()
                        clearedMessage = "Cookies and site data cleared."
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let clearedMessage {
                    Text(clearedMessage)
                        .font(.footnote)
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                        .task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            self.clearedMessage = nil
                        }
                }
            }
        }
    }

    // MARK: Bookmarks

    private var filteredBookmarks: [Bookmark] {
        let q = search.lowercased()
        return q.isEmpty ? library.bookmarks
            : library.bookmarks.filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
    }

    @ViewBuilder
    private var bookmarksList: some View {
        if filteredBookmarks.isEmpty {
            ContentUnavailableView("No bookmarks", systemImage: "star",
                                   description: Text("Tap the star in the toolbar to bookmark the current page."))
        } else {
            List {
                ForEach(filteredBookmarks) { bookmark in
                    Button { open(bookmark.url) } label: {
                        row(title: bookmark.title, url: bookmark.url, icon: "star.fill", date: nil)
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.removeBookmark(bookmark) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: History

    private var filteredHistory: [HistoryEntry] {
        let q = search.lowercased()
        return q.isEmpty ? library.history
            : library.history.filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
    }

    @ViewBuilder
    private var historyList: some View {
        if filteredHistory.isEmpty {
            ContentUnavailableView(
                "No history",
                systemImage: "clock",
                description: Text(model.privateBrowsing
                                  ? "Private browsing is on, so pages are not recorded. Turn it off in the toolbar to keep history."
                                  : "Pages you visit in normal tabs will appear here.")
            )
        } else {
            List {
                ForEach(filteredHistory) { entry in
                    Button { open(entry.url) } label: {
                        row(title: entry.title, url: entry.url, icon: "clock", date: entry.date)
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.removeHistory(entry) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Shared

    private func row(title: String, url: URL, icon: String, date: Date?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? (url.host ?? url.absoluteString) : title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(url.absoluteString)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date {
                Text(date, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func open(_ url: URL) {
        model.navigate(to: url.absoluteString)
        dismiss()
    }
}
