# 0065. Keep feedback controls visible and useful

Date: 2026-11-20. Decided by Flo in 0.16.1 feedback. Beads: sz-rs30.1.131.10, sz-rs30.1.131.11, sz-rs30.1.131.12. Replaces the slider choices of [0064](0064-player-tint-comparison.md). Replaces the ground exception of [0034](0034-colour.md).

## Context

The unselected fermata disappears on grey grounds. The Chronology link does nothing within its own stack.
Flo wants more temporary tint choices.

## Decision

- The unselected fermata reaches 3:1 on every ground, or 4.5:1 with Increase Contrast.
- A named picture that has not loaded shows the opaque elevated ground, not a translucent fill.
- The picture scrim protects both favourite states. The player mark uses the colours solved for its wash.
- Player Tint uses a slider from 0 to 5 in 0.5 steps. The default is 3.
- The comparison stays temporary. The fade keeps its height and stops.
- The composer button returns to the Chronology chart from its stack. Its label reads Back to Chronology there.

## Consequences

The palette checker allows no grey-ground contrast exceptions. Other page stacks stay available when the listener opens the chart.
