# Native design implementation

## Source of truth

`Design/index.html` is the original interactive design, not the system's default Table/List appearance. Native chrome uses the same semantic light/dark colors: canvas #FFFFFF/#202228, chrome #F7F7F9/#292B33, sidebar #F3F4F7/#25272F, text #20232A/#F0F1F6, secondary #78808C/#9399A7, separators #E5E7EB/#393C46, selection #E4F0FF/#153E6D. Native controls retain the user's system accent, high-contrast behavior, standard menus, Quick Look, sharing and filesystem integrations.

## Review findings and corrections

The previous captures did not meet the design despite passing nonblank-image checks. NSSplitView expanded the sidebar to 264 and inspector to 380 points, leaving important file columns outside the viewport. The native table drew empty alternating rows; title and command bars lost their surface hierarchy; selection relied on window focus. These are design defects, not proof of quality from a green build.

Default native geometry now explicitly follows the prototype: 211-point sidebar, 254-point inspector, 48-point tabs, 54-point commands, 54-point address, 30-point status. A SwiftUI split handle retains user resize intent separately from responsive clamping. At compact widths Details and Preview combine without losing preferences. The file surface is always the remaining width. No decorative HTML/browser host is used by the app.

Implementation is verified with actual SwiftUI view captures, geometry assertions, palette samples, populated fixtures and a human/visual review of the resulting PNGs. Image-size/nonblank checks remain useful infrastructure checks, but do not establish design parity. Native integrations and file data are real; only test fixture directories contain synthetic documents.
