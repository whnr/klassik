# 0041. Native tabs and the display corner

Decided by Flo in the build 46 feedback, 2026-11-14.
Beads: sz-rs30.1.105.4.4, sz-rs30.1.105.4.7 and sz-rs30.1.105.2.1.
This replaces the custom-tab fallback in [0028](0028-mini-player-pill.md).

## Context

Custom tab buttons do not provide the system glass selector or its drag behavior.
The straight mini player strip does not follow the display corner.

## Decision

- Use the native tab controller and reserve space beside its bar for the mini player.
- A first tab tap restores its stack. A second tap returns to that place's root.
- Follow the display corner with system concentric geometry. Keep the strip eight points wide.
- End the strip horizontally. The bend belongs to the mini player and does not scrub.
- Keep the square cover above the corner. Apply the same rules on either screen edge.

## Consequences

Each place keeps its NavigationStack and system Back controls.
The specimen approximates glass and display corners. The installed app remains their acceptance check.
The deferred interactive swipes remain on sz-rs30.1.105.4.2 and sz-rs30.1.105.4.3.
