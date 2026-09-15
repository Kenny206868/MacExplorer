import Foundation

public enum LocationAddressError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum LocationAddress: Equatable, Sendable {
    case file(URL), server(URL)

    /// No shell expansion, user lookup or launch. Percent escapes are decoded
    /// only for explicit file: URLs, never for a plain filesystem path.
    public static func parse(_ input: String, relativeTo base: URL, home: URL) throws -> Self {
        guard base.isFileURL, home.isFileURL else { throw LocationAddressError.invalid("Choose a local base folder.") }
        let text = try draftText(input)
        if text.lowercased().hasPrefix("file:") || text.contains("://") {
            guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
                  let url = parts.url, parts.user == nil, parts.password == nil else {
                throw LocationAddressError.invalid("Use a valid file or server URL without embedded credentials.")
            }
            if scheme == "file" {
                guard parts.host == nil || parts.host == "" || parts.host?.lowercased() == "localhost",
                      parts.port == nil, parts.query == nil, parts.fragment == nil,
                      let path = parts.percentEncodedPath.removingPercentEncoding, path.hasPrefix("/"),
                      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw LocationAddressError.invalid("Use a local file URL without a query or fragment.")
                }
                return .file(lexicalFileURL(path))
            }
            guard ["smb", "afp", "nfs", "https"].contains(scheme), parts.host?.isEmpty == false else {
                throw LocationAddressError.invalid("Supported server routes are SMB, AFP, NFS and HTTPS WebDAV.")
            }
            return .server(url)
        }
        if text == "~" { return .file(lexicalFileURL(home.path)) }
        if text.hasPrefix("~/") { return .file(lexicalFileURL(home.path + "/" + text.dropFirst(2))) }
        if text.hasPrefix("~") { throw LocationAddressError.invalid("Use ~ for your home folder or enter an absolute path.") }
        return .file(lexicalFileURL(text.hasPrefix("/") ? text : base.path + "/" + text))
    }

    static func draftText(_ input: String) throws -> String {
        guard input.utf8.count <= 32_768,
              !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LocationAddressError.invalid("Enter a path without control characters (maximum 32 KiB).")
        }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, let first = text.first, (first == "\"" || first == "'"), text.last == first {
            text.removeFirst(); text.removeLast()
        }
        guard !text.isEmpty else { throw LocationAddressError.invalid("Enter a folder path.") }
        return text
    }

    /// Pure lexical normalization: never consult the filesystem, resolve links,
    /// or rewrite /private aliases while a text field is typing on MainActor.
    /// Parent components have logical-path semantics, including above symlinks.
    private static func lexicalFileURL(_ path: String) -> URL {
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(component)
            }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"), isDirectory: false)
    }
}
public struct PathSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public var insertion: String { url.path == "/" ? "/" : url.path + "/" }
    public init(url: URL) { self.url = url; title = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent }
}
public struct PathSuggestions: Sendable {
    public let items: [PathSuggestion]
    public let truncated: Bool
    public init(items: [PathSuggestion] = [], truncated: Bool = false) { self.items = items; self.truncated = truncated }
}
public enum PathResolution: Equatable, Sendable {
    case folder(URL), file(URL), server(URL)
}

/// Dedicated bounded lanes keep completion/navigation independent of large
/// listings and checksums. Cancellation releases the awaiting task promptly;
/// a blocked filesystem call cannot itself be forcibly interrupted.
public final class PathAddressService: @unchecked Sendable {
    public static let shared = PathAddressService()
    private let completionLane = FileReadExecutor(name: "path-completion", concurrency: 2, quality: .userInitiated)
    private let navigationLane = FileReadExecutor(name: "path-navigation", concurrency: 2, quality: .userInitiated)
    private let lock = NSLock()
    private struct Cached { let time: TimeInterval; let folders: [URL]; let truncated: Bool }
    private var cache: [String: Cached] = [:]
    private let scanLimit: Int
    private let folderLimit: Int
    private let scanTimeBudget: TimeInterval
    private let clock: @Sendable () -> TimeInterval
    public convenience init() { self.init(scanLimit: 4096, folderLimit: 512, scanTimeBudget: 0.15) }
    /// Inject budgets and a monotonic clock for deterministic limit tests.
    /// The production initializer always uses the bounded defaults above.
    init(scanLimit: Int, folderLimit: Int, scanTimeBudget: TimeInterval,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.scanLimit = max(1, min(4096, scanLimit)); self.folderLimit = max(1, min(512, folderLimit))
        self.scanTimeBudget = scanTimeBudget.isFinite ? max(0.001, min(30, scanTimeBudget)) : 0.15
        self.clock = clock
    }
    public func resolve(_ text: String, base: URL, home: URL) async throws -> PathResolution {
        let address = try LocationAddress.parse(text, relativeTo: base, home: home)
        return try await navigationLane.run { cancellation in
            try cancellation.check()
            switch address {
            case .server(let url): return .server(url)
            case .file(let url):
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey])
                try cancellation.check()
                if values.isDirectory == true && values.isPackage != true { return .folder(url) }
                return .file(url)
            }
        }
    }
    public func suggestions(_ text: String, base: URL, home: URL, showHidden: Bool) async throws -> PathSuggestions {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return PathSuggestions() }
        let trimmed = try LocationAddress.draftText(text)
        guard case .file(let resolved) = try LocationAddress.parse(text, relativeTo: base, home: home) else { return PathSuggestions() }
        let hasTrailingSlash = trimmed.hasSuffix("/") || trimmed == "~"
        let directory = trimmed == "." ? base : hasTrailingSlash ? resolved : resolved.deletingLastPathComponent()
        let prefix = trimmed == "." ? "." : hasTrailingSlash ? "" : resolved.lastPathComponent
        return try await completionLane.run { [self] cancellation in
            let listing = try folders(in: directory, cancellation: cancellation)
            try cancellation.check()
            let matches = listing.folders.filter {
                (showHidden || prefix.hasPrefix(".") || !$0.lastPathComponent.hasPrefix(".")) &&
                (prefix.isEmpty || $0.lastPathComponent.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil)
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return PathSuggestions(items: matches.prefix(12).map(PathSuggestion.init), truncated: listing.truncated || matches.count > 12)
        }
    }
    private func folders(in directory: URL, cancellation: FileReadCancellation) throws -> Cached {
        let now = clock(), key = directory.path
        lock.lock(); let cached = cache[key]; lock.unlock()
        if let cached, now >= cached.time, now - cached.time < 1.5 { return cached }
        var failed: Error?
        guard let iterator = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants],
            errorHandler: { _, error in failed = error; return false }) else {
            throw LocationAddressError.invalid("This folder is unavailable for completion.")
        }
        var folders: [URL] = [], count = 0, truncated = false
        while let url = iterator.nextObject() as? URL {
            try cancellation.check(); count += 1
            if count > scanLimit || folders.count >= folderLimit || clock() - now > scanTimeBudget { truncated = true; break }
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
               values.isDirectory == true && values.isPackage != true { folders.append(url) }
        }
        if let failed { throw failed }
        try cancellation.check()
        let result = Cached(time: clock(), folders: folders, truncated: truncated)
        lock.lock()
        if cache.count >= 16, let oldest = cache.min(by: { $0.value.time < $1.value.time })?.key { cache.removeValue(forKey: oldest) }
        cache[key] = result; lock.unlock()
        return result
    }
}
