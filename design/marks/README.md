# Marks

`fermata.svg` is the favourite mark: an engraved arc over a dot, Klassik's own drawing after the shape of an engraved score. It is the master for the custom SF Symbol. The path fills with `currentColor`, so the colour comes from the favourite or favourite-off token.

- **Grid.** 17 × 10.5. The outer edge is a half ellipse, 8.5 by 10.5. The inner edge is a half ellipse, 7.8 by 7.9, so the stroke is 2.6 thick at the top and 0.7 at the feet. The dot has radius 2.4; its bottom sits 0.2 above the baseline. The feet sit on the bottom edge of the view box, the baseline.
- **Size.** The arc is 0.64 em high and 1.62 times as wide as high. It scales with the text that it follows. The SF Symbol template draws the arc below the cap-height guide.
- **Placement.** The feet sit on the text baseline, a quarter em after the last word. One weight for all text: the arc does not grow heavier beside bold text or with Bold Text on.
- **States.** Set is the favourite colour; not set is a quiet neutral grey, never secondary text colour and never an outline. The contrast targets are in [tokens.md](../specimen/tokens.md).
