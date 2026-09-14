import Foundation

public enum PromisedImportFile {
    /// A receiver may supply only a direct child of our private inbox. Reject
    /// absolute escapes, root links, special files and a substituted inbox.
    public static func validate(_ url: URL, in inbox: URL, expectedInbox: FileFingerprint? = nil) throws {
        guard url.isFileURL, inbox.isFileURL,
              expectedInbox?.matchesIdentity(inbox) != false,
              try FileManager.default.attributesOfItem(atPath: inbox.path)[.type] as? FileAttributeType == .typeDirectory,
              url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().path == inbox.resolvingSymlinksInPath().path,
              let kind = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType,
              kind == .typeRegular || kind == .typeDirectory else {
            throw ExplorerError.message("The source application returned a file outside its promised inbox or an unsupported filesystem object.")
        }
    }
}
