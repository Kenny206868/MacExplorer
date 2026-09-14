# Native design review and regression gates

The macOS 26 captures at bbc559c were reviewed in light and dark matrices covering 44 views. The nested file-host appearance fix restores native table and file-label contrast; its independent SwiftUI/AppKit appearance test catches the state boundary that a nonblank bitmap alone missed. Gallery, all icon sizes, list/content, selection, empty/error, dialogs, transfers and preferences render their production SwiftUI implementations, not HTML mockups.

## Layout improvements from the captures

The original native split initialized auxiliary panes toward their maximum widths, leaving too little room for the default file columns. A narrow public NSSplitView adapter now sets initial positions from WorkspaceLayout's budget without replacing native dividers or their accessibility. At the default 1260-point workspace with Details enabled, the intended widths are 208-point sidebar, 780-point files and 270-point inspector. After initialization, user divider changes are not continuously overwritten; changing the pane configuration applies the relevant new initial budget.

The default Details columns are Name, Date modified, Kind and Size. Tags and Availability remain user-customizable columns, initially hidden. Existing persisted column choices retain their customization identifiers. The combined Details/Preview picker hides its redundant visual label while retaining the accessibility label. Both panes remain enabled in user preferences when a narrow window combines them into tabs.

Core tests check initial pane budgets over supported widths and all pane combinations. A native NSSplitView test verifies the actual initial positions and preservation of subsequent user resizing. The separate production-layout matrix still checks 36 native width/pane configurations for missing geometry, content-area minimums, overlap and overflow. Archive browsing adds two native captures for a total of 46 per platform.

## Validation scope

A green visual job means the declared capture matrix, native integration assertions, dimensions, opaque compositing and nonblank checks passed. It is not a pixel-baseline approval, proof of every dynamic workflow, or a completed VoiceOver audit. The downloaded PNG galleries and exact commit/toolchain manifests support review of those additional properties. Do not conflate successful captures from one commit with the build status of a later commit.

Public API references: https://developer.apple.com/documentation/appkit/nssplitview/setposition(_:ofdividerat:) and https://developer.apple.com/documentation/swiftui/tablecolumncontent/defaultvisibility(_:)
