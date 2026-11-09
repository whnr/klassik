# 0033. The engraved fermata, strong when set and quiet when not

Date: 2026-11-09. Decided by Flo after specimen round 22 on the phone. Beads: sz-rs30.1.83.23, sz-rs30.1.83.19.1. Replaces the drawing and the not-set colour of [0032](0032-fermata-mark.md).

## Context

The 2:1 solid arc of ADR 0032 was hard to recognise. Flo found an engraved fermata on the Wikipedia page for the fermata, closer to his intent. On the phone, the not-set mark in secondary grey was as light as the set mark in dark mode. The two states looked the same. Round 22 showed three engraved drawings and a quiet grey for the not-set state.

## Decision

- **Drawing.** An engraved arc over a dot, drawn by Klassik after the shape of an engraved score. On a 17 × 10.5 grid: the outer edge is a half ellipse, 8.5 by 10.5. The inner edge is a half ellipse, 7.8 by 7.9. So the stroke is 2.6 thick at the top and 0.7 at the feet. The dot has radius 2.4. Its bottom sits 0.2 above the baseline.
- **Size.** The arc is 0.64 em high, as in ADR 0032. It is 1.62 times as wide as high. It scales with the text that it follows.
- **Set.** The favourite colour: the accent at its strongest chroma that reaches 4.5:1 by day and 6.5:1 at night, 7:1 and 9:1 with Increase Contrast.
- **Not set.** The same drawing in a quiet neutral grey at 3:1, 4.5:1 with Increase Contrast. Never secondary text colour, never an outline.
- **Differentiate Without Color** changes nothing. The two states differ in lightness, and the colour-vision research (sz-rs30.1.83.19.16) found them distinct for protan, deutan and tritan vision. The VoiceOver label carries the state.
- Placement and weight stay as ADR 0032 says: feet on the text baseline, a quarter em after the last word, one weight for all text.

## Consequences

- The custom SF Symbol takes the new drawing. Its template draws the arc below the cap-height guide.
- The token file gets a colour role for the not-set mark.
- The specimen loses the fermata board and the size ladder.
