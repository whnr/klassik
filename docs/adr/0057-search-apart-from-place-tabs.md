# 0057. Search stays apart from the place tabs

Decided by Flo, 2026-11-18. Bead: sz-rs30.1.115.
Replaces the standard Search tab constraint in [0029](0029-search-at-the-top.md).
Refines the separate Search button of [0040](0040-settings-from-the-library.md).
The Performers page is replaced by [0069](0069-no-shuffle-and-no-performer-list.md).

## Context

The system draws Search apart only when `UISearchTab.automaticallyActivatesSearch` is true.
ADR 0029 chose a standard tab to keep the search field at the top.
Flo chose to keep Search apart from Library and Chronology.

## Decision

- Keep the native Search tab apart, with `automaticallyActivatesSearch` enabled.
- Keep the search field at the top, as ADR 0029 requires.
- The Search tracer checks keyboard activation on the phone when it adds the root search field.

## Consequences

The current Search root has no field and opens no keyboard.
The Performers page has its own search field within the Search stack.
The native Library symbol appears filled in both selection states; selection color and glass show the active tab.
The specimen approximates native tab symbols and glass, as [0041](0041-native-tabs-and-display-corners.md) explains.
