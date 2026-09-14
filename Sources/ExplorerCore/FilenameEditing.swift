import Foundation

public enum FilenameEditing {
    /// Native field editors use UTF-16 ranges. Preserve the final extension
    /// when initially selecting a regular file's name, including Unicode names.
    public static func initialSelection(_ name: String, isDirectory: Bool) -> NSRange {
        let value = name as NSString
        let suffix = value.pathExtension as NSString
        let length = !isDirectory && suffix.length > 0 ? max(0, value.length - suffix.length - 1) : value.length
        return NSRange(location: 0, length: length)
    }
}
