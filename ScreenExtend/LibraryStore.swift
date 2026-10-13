import Foundation
import WebKit
import Combine

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var title: String
    var date: Date
}

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var title: String
    var date: Date
}

struct Suggestion: Identifiable, Hashable {
    enum Kind { case bookmark, history }
    var id: String { url.absoluteString }
    let url: URL
    let title: String
    let kind: Kind
}

/// Bookmarks and browsing history, stored as JSON in Application Support.
/// History is only recorded for non-private tabs (see BrowserModel).
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var history: [HistoryEntry] = []   // newest first
    @Published private(set) var bookmarks: [Bookmark] = []     // newest first

    private let maxHistory = 3000
    private let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private var bookmarksURL: URL { directory.appendingPathComponent("bookmarks.json") }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("ScreenExtend", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        history = load(historyURL) ?? []
        bookmarks = load(bookmarksURL) ?? []
    }

    // MARK: History

    func record(url: URL, title: String) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        // Same page reloaded within a minute: just refresh the entry.
        if let first = history.first, first.url == url, Date().timeIntervalSince(first.date) < 60 {
            history[0].date = Date()
            if !title.isEmpty { history[0].title = title }
        } else {
            history.insert(HistoryEntry(url: url, title: title, date: Date()), at: 0)
            if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        }
        save(history, to: historyURL)
    }

    func updateTitle(for url: URL, title: String) {
        guard !title.isEmpty, let index = history.firstIndex(where: { $0.url == url }) else { return }
        if history[index].title != title {
            history[index].title = title
            save(history, to: historyURL)
        }
    }

    func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        save(history, to: historyURL)
    }

    func clearHistory() {
        history = []
        save(history, to: historyURL)
    }

    /// Wipes cookies, cache, local storage and everything else WebKit keeps for normal tabs.
    func clearWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    // MARK: Bookmarks

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    /// Returns true if the page is now bookmarked.
    @discardableResult
    func toggleBookmark(url: URL, title: String) -> Bool {
        if let index = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: index)
            save(bookmarks, to: bookmarksURL)
            return false
        }
        let name = title.isEmpty ? (url.host ?? url.absoluteString) : title
        bookmarks.insert(Bookmark(url: url, title: name, date: Date()), at: 0)
        save(bookmarks, to: bookmarksURL)
        return true
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save(bookmarks, to: bookmarksURL)
    }

    func renameBookmark(_ bookmark: Bookmark, to title: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].title = title
        save(bookmarks, to: bookmarksURL)
    }

    // MARK: Address bar suggestions

    func suggestions(for query: String, limit: Int = 6) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<URL>()
        var result: [Suggestion] = []
        for b in bookmarks where matches(q, b.title, b.url) && seen.insert(b.url).inserted {
            result.append(Suggestion(url: b.url, title: b.title, kind: .bookmark))
            if result.count >= limit { return result }
        }
        for h in history where matches(q, h.title, h.url) && seen.insert(h.url).inserted {
            result.append(Suggestion(url: h.url, title: h.title, kind: .history))
            if result.count >= limit { return result }
        }
        return result
    }

    private func matches(_ q: String, _ title: String, _ url: URL) -> Bool {
        title.lowercased().contains(q) || url.absoluteString.lowercased().contains(q)
    }

    // MARK: Persistence

    private func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
