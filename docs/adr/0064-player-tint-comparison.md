# 0064. Compare stronger player tints

Date: 2026-11-19. Decided by Flo in the 0.15.0 feedback. Bead: sz-kaqj.4.
Temporarily extends the player ground rule of [0034](0034-colour.md).

## Context

Flo wants stronger tint behind the cover. He wants to compare 2× and 3× before choosing.

## Decision

- Settings offers Player Tint choices of 1×, 2×, and 3×. The default is 2×.
- The multiplier increases cover chroma. Lightness decreases slightly so gamut mapping keeps the choices distinct.
- Each step reduces lightness by 0.03 by day and 0.01 at night.
- The fade keeps its height and stops. Text keeps its contrast targets.
- Remove the comparison control after Flo chooses.

## Consequences

The 1× choice preserves the original ground. Stronger choices remain temporary.
