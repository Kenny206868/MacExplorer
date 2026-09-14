import Foundation
import Darwin

public struct NativeCopyProgress: Sendable {
    /// Bytes reported by copyfile's data callback, not disk-controller I/O.
    public let writtenBytes: Int64
    /// Includes successfully cloned logical file content.
    public let logicalBytes: Int64
    public let clonedFiles: Int
    public let path: String
}

/// Public macOS copyfile API: preserves ACLs, xattrs and file metadata without
/// following symlinks. The caller owns destination staging and error cleanup.
public enum NativeFileCopy {
    @discardableResult public static func copy(
        from source: URL, to destination: URL, control: OperationControl,
        allowClone: Bool = true,
        progress: @escaping @Sendable (NativeCopyProgress) -> Void = { _ in }
    ) throws -> NativeCopyProgress {
        try control.checkpoint()
        guard source.isFileURL, destination.isFileURL else {
            throw ExplorerError.message("Native copy requires filesystem URLs.")
        }
        guard !FileNames.exists(destination) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST), userInfo: [NSFilePathErrorKey: destination.path])
        }
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }
        let context = CopyContext(control: control, path: source.path, progress: progress)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), pointer) == 0,
              copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyCallback, to: UnsafeRawPointer.self)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW | COPYFILE_DATA_SPARSE)
            | (allowClone ? copyfile_flags_t(COPYFILE_CLONE) : 0)
        let status: Int32 = withExtendedLifetime(context) {
            source.withUnsafeFileSystemRepresentation { sourcePath in
                destination.withUnsafeFileSystemRepresentation { destinationPath in
                    copyfile(sourcePath, destinationPath, state, flags)
                }
            }
        }
        let code = errno
        if let failure = context.failure { throw failure }
        guard status == 0 else {
            if control.isCancelled || code == ECANCELED { throw CancellationError() }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code == 0 ? EIO : code),
                          userInfo: [NSFilePathErrorKey: context.path])
        }
        // Cloning has no data callbacks. Account for a single-file clone even
        // when the OS omits recursive notifications on that fast path.
        var wasCloned = false
        if copyfile_state_get(state, UInt32(COPYFILE_STATE_WAS_CLONED), &wasCloned) == 0, wasCloned, context.clonedFiles == 0 {
            context.clonedFiles = 1
            context.logicalBytes = max(context.logicalBytes, regularFileSize(source.path))
        }
        try control.checkpoint() // A cancellation after cloning still prevents installation.
        context.emit(force: true)
        return context.snapshot
    }

    private static func regularFileSize(_ path: String) -> Int64 {
        var value = stat()
        guard path.withCString({ lstat($0, &value) }) == 0,
              value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return 0 }
        return max(0, value.st_size)
    }
    private static let copyCallback: copyfile_callback_t = { what, stage, state, source, _, opaque in
        guard let opaque else { return Int32(COPYFILE_QUIT) }
        let context = Unmanaged<CopyContext>.fromOpaque(opaque).takeUnretainedValue()
        if stage == COPYFILE_ERR {
            let code = errno
            context.failure = NSError(domain: NSPOSIXErrorDomain, code: Int(code == 0 ? EIO : code),
                                      userInfo: [NSFilePathErrorKey: source.map { String(cString: $0) } ?? context.path])
            return Int32(COPYFILE_QUIT) // Never retry a failing write indefinitely.
        }
        do { try context.control.checkpoint() }
        catch { context.failure = error; return Int32(COPYFILE_QUIT) }
        if let source { context.path = String(cString: source) }
        if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_START {
            context.fileBase = context.logicalBytes; context.fileCopied = 0
        }
        if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state {
            var copied: off_t = 0
            if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                context.writtenBytes = saturatingAdd(context.writtenBytes, max(0, copied - context.fileCopied))
                context.fileCopied = max(context.fileCopied, copied)
                context.logicalBytes = max(context.logicalBytes, saturatingAdd(context.fileBase, copied))
            }
        }
        if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
            context.logicalBytes = max(context.logicalBytes, saturatingAdd(context.fileBase, regularFileSize(context.path)))
            var cloned = false
            if let state, copyfile_state_get(state, UInt32(COPYFILE_STATE_WAS_CLONED), &cloned) == 0, cloned { context.clonedFiles += 1 }
        }
        context.emit(force: false)
        return Int32(COPYFILE_CONTINUE)
    }
    private static func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
        let (sum, overflow) = a.addingReportingOverflow(max(0, b))
        return overflow ? Int64.max : sum
    }
    /// Confined to the synchronous copyfile invocation; never shared across calls.
    private final class CopyContext {
        let control: OperationControl
        let progress: @Sendable (NativeCopyProgress) -> Void
        var path: String
        var writtenBytes: Int64 = 0, logicalBytes: Int64 = 0, fileBase: Int64 = 0, fileCopied: Int64 = 0
        var clonedFiles = 0
        var failure: Error?
        var lastEmission: TimeInterval = -.infinity
        init(control: OperationControl, path: String, progress: @escaping @Sendable (NativeCopyProgress) -> Void) {
            self.control = control; self.path = path; self.progress = progress
        }
        var snapshot: NativeCopyProgress { NativeCopyProgress(writtenBytes: writtenBytes, logicalBytes: logicalBytes, clonedFiles: clonedFiles, path: path) }
        func emit(force: Bool) {
            let now = ProcessInfo.processInfo.systemUptime
            guard force || now - lastEmission >= 0.1 else { return }
            lastEmission = now; progress(snapshot)
        }
    }
}
