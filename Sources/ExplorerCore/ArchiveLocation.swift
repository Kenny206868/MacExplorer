import Foundation

extension Location {
    public var archiveSource: URL? { if case .archive(let source, _) = self { return source }; return nil }
    public var isArchive: Bool { archiveSource != nil }
    public var archiveFolder: String? { if case .archive(_, let folder) = self { return folder }; return nil }
    public var displayPath: String {
        if case .archive(let source, let folder) = self { return source.path + " ▸ /" + folder }
        return directory?.path ?? title
    }
}
