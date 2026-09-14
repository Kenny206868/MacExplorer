# Native dual-pane review

The original interactive palette and chrome remain the reference. Dual-pane browsing adds independent file surfaces rather than duplicating one tab's state. Both selections remain visible; an accent line, numbered pane badge and Active label identify where shared commands apply. Narrow windows stack panes without changing saved orientation.

`DualPaneSnapshotTests` renders twelve populated pane configurations (six in each theme) plus four touch-action/keyboard-help captures. It asserts actual native pane containment, non-overlap, divider spacing, preserved selection and saved orientation. This extends mandatory capture coverage from 52 to 68 per platform. The review gallery places dual-pane captures first and includes a filter.

`KeyboardRoutingTests` uses real AppKit windows, NSEvent instances and NSTextView first responders. It checks arrows, range extension, focus-only navigation, Tab switching, Home/End, Page Down, incremental search, F6 focus cycling, editor Select All, modal ownership and suppression of file deletion while editing text. No global events or accessibility-control permissions are required.

`FileInputContractTests` tests modifier-free selection for all nine presentations, native drag preparation from an inactive pane, long-press ownership and 44-point touch density. Device-driver, physical gesture, cross-application drag and complete assistive-technology validation are separate from these automated tests.

The alpha assembler uses the same explicit capture contract as CI. It rejects incomplete/duplicate view manifests, nonfinite render metrics, unexpected dimensions, incorrect image hashes, mismatched commits and unchecked native distributions. Palette tests remain sampling tests; inspect the PNGs for typography and fine layout instead of treating a passing sample as visual certification.
