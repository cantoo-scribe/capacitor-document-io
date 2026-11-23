import Capacitor
import Foundation

/// Holds the URL the system handed the app and keeps its security scope alive.
/// On iOS the permission lives on the original URL object, not on the path string.
enum DocumentStore {
    private static let bookmarksKey = "cantoo-document-io-bookmarks"

    private struct OpenDocument {
        let url: URL
        let startedAccess: Bool
    }

    private static var openDocuments: [String: OpenDocument] = [:]

    /// Called when iOS delivers a document URL. Retains that exact URL instance.
    @discardableResult
    static func retainFromSystem(_ url: URL) -> String {
        if let existing = lookup(url.absoluteString) {
            return canonical(existing.url)
        }

        let started = url.startAccessingSecurityScopedResource()
        retain(url, startedAccess: started)

        if url.isFileURL,
           let bookmark = try? url.bookmarkData(
               options: [],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            saveBookmark(bookmark, for: url)
        }

        return canonical(url)
    }

    static func prepare(urlString: String) -> String {
        if let existing = lookup(urlString) {
            return canonical(existing.url)
        }

        if let last = ApplicationDelegateProxy.shared.lastURL, matches(last, urlString) {
            return retainFromSystem(last)
        }

        if urlString.hasPrefix("content:") {
            return urlString
        }

        return retainFromSystem(fileURL(from: urlString))
    }

    static func read(at path: String) throws -> Data {
        try withAccessibleURL(for: path) { url in
            var coordinationError: NSError?
            var fileData: Data?
            var readError: Error?

            NSFileCoordinator().coordinate(
                readingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    fileData = try Data(contentsOf: coordinatedURL)
                } catch {
                    readError = error
                }
            }

            if let coordinationError { throw coordinationError }
            if let readError { throw readError }
            guard let fileData else {
                throw documentError("Failed to read \(path)")
            }
            return fileData
        }
    }

    static func write(at path: String, data: Data) throws {
        try withAccessibleURL(for: path) { url in
            var coordinationError: NSError?
            var writeError: Error?

            // In-place overwrite. .forReplacing + .atomic creates a sibling file the
            // File Provider grant does not allow, so the original disappears.
            NSFileCoordinator().coordinate(
                writingItemAt: url,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL)
                } catch {
                    writeError = error
                }
            }

            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
        }
    }

    static func release(path: String) {
        guard let document = lookup(path) else { return }
        if document.startedAccess {
            document.url.stopAccessingSecurityScopedResource()
        }
        for key in keys(for: document.url) + [path] {
            openDocuments.removeValue(forKey: key)
        }
        removeBookmark(for: document.url)
    }

    private static func withAccessibleURL<T>(
        for path: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        if let document = lookup(path) {
            return try body(document.url)
        }

        if path.hasPrefix("content:") {
            guard let url = URL(string: path) else {
                throw documentError("Invalid URI \(path)")
            }
            return try body(url)
        }

        let parsed = fileURL(from: path)
        if let bookmark = bookmark(for: path, fileURL: parsed) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if url.startAccessingSecurityScopedResource() {
                retain(url, startedAccess: true)
                if isStale, let refreshed = try? url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    saveBookmark(refreshed, for: url)
                }
                return try body(url)
            }
        }

        return try body(parsed)
    }

    private static func retain(_ url: URL, startedAccess: Bool) {
        let document = OpenDocument(url: url, startedAccess: startedAccess)
        for key in keys(for: url) {
            openDocuments[key] = document
        }
    }

    private static func lookup(_ path: String) -> OpenDocument? {
        if let document = openDocuments[path] {
            return document
        }
        if path.hasPrefix("content:") {
            return nil
        }
        let parsed = fileURL(from: path)
        for key in keys(for: parsed) {
            if let document = openDocuments[key] {
                return document
            }
        }
        return nil
    }

    private static func matches(_ url: URL, _ path: String) -> Bool {
        if url.absoluteString == path || url.path == path {
            return true
        }
        let keys = Set(keys(for: url))
        if keys.contains(path) {
            return true
        }
        if path.hasPrefix("content:") {
            return false
        }
        return !keys.isDisjoint(with: keys(for: fileURL(from: path)))
    }

    private static func canonical(_ url: URL) -> String {
        if url.isFileURL {
            return url.standardizedFileURL.absoluteString
        }
        return url.absoluteString
    }

    private static func keys(for url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        var keys = [
            url.absoluteString,
            url.path,
            standardized.absoluteString,
            standardized.path,
        ]
        if let decoded = url.absoluteString.removingPercentEncoding {
            keys.append(decoded)
        }
        if let decoded = standardized.absoluteString.removingPercentEncoding {
            keys.append(decoded)
        }
        return keys
    }

    private static func fileURL(from path: String) -> URL {
        if path.hasPrefix("file://") {
            let raw = String(path.dropFirst("file://".count))
            let filesystemPath = raw.removingPercentEncoding ?? raw
            return URL(fileURLWithPath: filesystemPath).standardizedFileURL
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        if let url = URL(string: path), url.isFileURL {
            return url.standardizedFileURL
        }
        return URL(fileURLWithPath: path)
    }

    private static func bookmark(for path: String, fileURL: URL) -> Data? {
        let bookmarks = loadBookmarks()
        let candidates = [path, fileURL.path, fileURL.absoluteString] + keys(for: fileURL)
        for key in candidates {
            if let bookmark = bookmarks[key] {
                return bookmark
            }
        }
        return nil
    }

    private static func saveBookmark(_ bookmark: Data, for url: URL) {
        var bookmarks = loadBookmarksBase64()
        let encoded = bookmark.base64EncodedString()
        for key in keys(for: url) {
            bookmarks[key] = encoded
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private static func removeBookmark(for url: URL) {
        var bookmarks = loadBookmarksBase64()
        for key in keys(for: url) {
            bookmarks.removeValue(forKey: key)
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private static func loadBookmarksBase64() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: String]) ?? [:]
    }

    private static func loadBookmarks() -> [String: Data] {
        var result: [String: Data] = [:]
        for (key, value) in loadBookmarksBase64() {
            if let data = Data(base64Encoded: value) {
                result[key] = data
            }
        }
        return result
    }

    private static func documentError(_ message: String) -> NSError {
        NSError(domain: "DocumentIo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@objc(DocumentIoPlugin)
public class DocumentIoPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DocumentIoPlugin"
    public let jsName = "DocumentIo"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "prepareOpenedDocument", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "release", returnType: CAPPluginReturnPromise),
    ]

    private var openURLObserver: NSObjectProtocol?

    @objc override public func load() {
        if let last = ApplicationDelegateProxy.shared.lastURL {
            DocumentStore.retainFromSystem(last)
        }

        openURLObserver = NotificationCenter.default.addObserver(
            forName: .capacitorOpenURL,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let object = notification.object as? [String: Any],
                let url = object["url"] as? URL
            else {
                return
            }
            DocumentStore.retainFromSystem(url)
        }
    }

    deinit {
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
    }

    @objc func prepareOpenedDocument(_ call: CAPPluginCall) {
        guard let url = call.getString("url"), !url.isEmpty else {
            call.reject("url is required")
            return
        }
        call.resolve(["uri": DocumentStore.prepare(urlString: url)])
    }

    @objc func read(_ call: CAPPluginCall) {
        guard let uri = call.getString("uri"), !uri.isEmpty else {
            call.reject("uri is required")
            return
        }
        do {
            let data = try DocumentStore.read(at: uri)
            call.resolve(["data": data.base64EncodedString()])
        } catch {
            call.reject("Failed to read document: \(error.localizedDescription)")
        }
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let uri = call.getString("uri"), !uri.isEmpty else {
            call.reject("uri is required")
            return
        }
        guard let base64 = call.getString("data"), let data = Data(base64Encoded: base64) else {
            call.reject("data must be valid base64")
            return
        }
        do {
            try DocumentStore.write(at: uri, data: data)
            call.resolve()
        } catch {
            call.reject("Failed to write document: \(error.localizedDescription)")
        }
    }

    @objc func release(_ call: CAPPluginCall) {
        guard let uri = call.getString("uri"), !uri.isEmpty else {
            call.reject("uri is required")
            return
        }
        DocumentStore.release(path: uri)
        call.resolve()
    }
}
