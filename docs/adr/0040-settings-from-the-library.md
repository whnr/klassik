# 0040. Settings opens from the Library toolbar

Date: 2026-11-13. Decided by Flo in the 0.12.0 device notes. Bead: sz-rs30.1.105.32.
Replaces Settings as a tab in [0038](0038-standard-tabs-and-the-cross-tab-back.md).

## Context

The mini player narrows the tab capsule. The Chronology label does not fit its selected chip.
Flo requests a cog in the Library toolbar instead of the Settings tab.

## Decision

- Library, Chronology and Search remain places, each with its own stack.
- The Library root shows a Settings cog in its trailing toolbar.
- The cog pushes Settings onto the Library stack. The system Back button returns to Library.
- Library and Chronology share the tab capsule. Search keeps its separate button.

## Consequences

Settings has the system back swipe and no cross-tab arrow.
Its controls and technical pages keep their behaviour.
The tab capsule gives Chronology more width while music plays.
