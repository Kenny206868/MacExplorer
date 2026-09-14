# Searchable native commands

Press **Command–Shift–P** or **Control–Shift–P**, or use Help → Search Commands. The palette is a native SwiftUI sheet with a searchable command catalog, real availability reasons, visible shortcuts, keyboard selection, and an explicit Run action. Type tasks such as `new folder`, `split`, `tags`, or `hidden`. This is not a shell and does not evaluate arbitrary input.

The immutable index normalizes case, diacritics and full-width characters once, matches every query token, ranks title prefixes and word boundaries ahead of aliases/fuzzy subsequences, and bounds queries to 256 characters and 12 tokens. Original catalog order breaks ties. Disabled operations stay discoverable with explanations.

## Dismissal and file safety

Commands are captured against the originating pane, tab and location. File actions additionally capture the actual selection and file fingerprints; Paste captures the clipboard generation. Commands are consumed once from SwiftUI's real `onDismiss` callback. There is no fixed-duration animation sleep. A changed selection, tab, location, clipboard, or file stops the command. Closed windows discard pending actions. Destructive commands reuse the existing Trash/permanent-delete confirmations, and cross-pane moves retain their destination confirmation.

The touch file-actions panel now uses the same dismissal coordinator instead of a 250 ms delay. Menus and the global keyboard router keep the same modal scope. The search field retains native text editing, VoiceOver chords are not intercepted, and opening the palette during IME marked-text composition is ignored.

## Evidence

`CommandSearchTests` covers ranking, token conjunction, aliases, Unicode, stability, duplicate identifiers and input limits. Native tests cover command availability, idempotent dismissal, stale owner/file rejection, and keyboard routing. Eight light/dark captures cover default, filtered, disabled and empty results, asserting actual native field-editor focus. These are added to the existing 78-view contract, giving 86 captures per platform.

Implementation references: Apple SwiftUI `onKeyPress(_:phases:action:)` and `sheet(item:onDismiss:content:)`; no third-party UI framework is used. Hardware and full assistive-technology evaluation remain separate from headless render/state tests.
