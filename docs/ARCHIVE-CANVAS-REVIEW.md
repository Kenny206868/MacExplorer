# Archive canvas visual review

Review of the complete native light/dark capture gallery found that the new virtual archive Table had inherited AppKit's alternating background, drawing striped empty rows below the actual members. The older archive browser already disabled this treatment; the virtual location now applies the same SwiftUI setting.

`ArchiveCanvasTests` hosts the production archive view with real ZIP contents, checks that its native table disables alternating backgrounds and verifies that selecting an archive member still selects the native row. The existing root/folder screenshot matrix remains mandatory in both appearances. This is a visual correction, not a replacement of native selection, keyboard behavior or indexed archive loading.
