# Native design review and regression gates

## Reference and review

The original `Design/index.html` is the visual reference. Review of the prior native captures showed that default NSSplitView expansion, Table zebra rows, clipped columns and weak tab contrast did not implement that design. The source now uses semantic reference colors and explicit SwiftUI pane allocation, real-row Details rendering, custom headers, card/row states, compact Home cards and a redesigned inspector. See `DESIGN-IMPLEMENTATION.md` for the palette and dimensions.

The original one-time `InitialPaneSizing` adapter has been removed because the production workspace no longer uses NSSplitView. Its test is replaced by `PaneResizeRestorationTests`, exercising an actual native window containing the production SwiftUI workspace through narrow/wide resize transitions. The test verifies that a narrow viewport clamps auxiliary width and widening restores the original 211/254-point intent. The separate 36-configuration layout matrix remains in place, alongside exhaustive core pane and column budgets.

`DesignReferenceTests` adds populated Home, Details and This Mac captures with real fixture files and a generated PDF. It checks the actual 211/793/254 default pane geometry, chrome heights, sampled light/dark surfaces, selected-row colors and absence of empty zebra rows. These six references bring the matrix to 52 captures per platform. Existing all-view-mode, grouped, narrow-pane, empty/error, dialog, transfer, settings and archive captures remain mandatory.

## Validation scope

The pipeline checks coverage, dimensions, opaque compositing, reference geometry and sampled palette contracts. Review the PNG gallery for typography, clipping, alignment and interaction states; a passing sampled palette assertion is not proof of pixel-perfect equivalence, complete feature parity, or a completed VoiceOver audit. Every published alpha includes screenshot galleries and the native app from the same successful commit.
