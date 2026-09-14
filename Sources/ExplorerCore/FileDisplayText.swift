import Foundation

/// Compact labels do not replace filesystem metadata. Full native descriptions
/// remain available to Properties, tooltips, export and accessibility clients.
public extension FileEntry {
    var compactSizeText: String {
        if isDirectory { return "—" }
        if size < 1024 { return "\(max(0, size)) B" }
        return sizeText
    }
    var conciseKind: String {
        if isSymbolicLink { return "Symbolic link" }
        if canBrowse { return "Folder" }
        switch extensionName {
        case "md", "markdown": return "Markdown"
        case "csv", "tsv": return "Delimited text"
        case "txt", "log": return "Text document"
        case "pdf": return "PDF document"
        case "json": return "JSON document"
        case "xml": return "XML document"
        case "zip": return "ZIP archive"
        case "png": return "PNG image"
        case "jpg", "jpeg": return "JPEG image"
        case "heic": return "HEIF image"
        default: return kind
        }
    }
}
