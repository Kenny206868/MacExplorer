import Foundation
import AppKit

/// Opening a provider-backed directory can block. Watch descriptors are opened,
/// installed and closed on a dedicated queue, never from a SwiftUI update.
@MainActor final class DirectoryWatcher {
    private let backend = DirectoryWatchBackend()
    private var url: URL?
    private var generation: UInt64 = 0
    func watch(_ url: URL, changed: @escaping @MainActor () -> Void) {
        guard self.url != url else { return }
        self.url = url; generation &+= 1; let expected = generation
        backend.watch(url) { [weak self] invalidated in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                if invalidated { self.url = nil }
                changed()
            }
        }
    }
    func stop() { generation &+= 1; url = nil; backend.stop() }
    deinit { backend.stop() }
}
private final class DirectoryWatchBackend: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MacExplorer.directory-watch", qos: .utility)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var source: DispatchSourceFileSystemObject?
    private func advance() -> UInt64 { lock.lock(); defer { lock.unlock() }; generation &+= 1; return generation }
    private func matches(_ token: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == token }
    func watch(_ url: URL, changed: @escaping @Sendable (Bool) -> Void) {
        let token = advance()
        queue.async { [self] in
            source?.cancel(); source = nil
            guard matches(token) else { return }
            let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { if matches(token) { changed(true) }; return }
            guard matches(token) else { close(descriptor); return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke], queue: queue)
            source.setEventHandler { [weak self] in
                guard let self, self.matches(token), let source = self.source else { return }
                let invalidated = !source.data.intersection([.delete, .rename, .revoke]).isEmpty
                if invalidated { source.cancel(); self.source = nil }
                changed(invalidated)
            }
            source.setCancelHandler { close(descriptor) }; self.source = source; source.resume()
        }
    }
    func stop() { _ = advance(); queue.async { [self] in source?.cancel(); source = nil } }
}
