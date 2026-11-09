# Colours for colour-blind listeners

Question: which Klassik colours stay apart for listeners with a colour-vision deficiency (CVD)? Bead: sz-rs30.1.83.19.16. Checked 2026-11-09.

Contrast is solved: WCAG AA in the standard palette, AAA with Increase Contrast. This note checks hue and chroma only. The values come from `palette-*.css` on branch `prototypes` (round 22, written by `palette.py`).

## Answer

- Favourite set and not set stay apart for all simulated deficiencies. The worst case is claret under deuteranopia: CIEDE2000 9.6.
- The two actions on the leading swipe side (Play Next, Add to Queue) stay apart everywhere.
- The two actions on the trailing side (Download, Reference) collapse for green under tritanopia (2.3). They are weak for plum under deuteranopia (5.9) and claret under protanopia (9.8).
- Play Next and Download are always weak for red-green CVD (5.2 to 8.7). They are on opposite sides, so the listener does not see them together.
- Oxblood and claret are near twins for everyone (9.2) and the same for tritans (0.9).
- The oxblood favourite is close to system red for everyone (5.4 to 9.0). Green collapses towards red only under full protanopia.
- Only one accent is active at a time. A red-green collapse between accent options therefore hides no information.

## Who is affected

- Red-green CVD affects about 1 in 12 men and 1 in 200 women of Northern European descent [P1]. IBM gives 8 % of men and 0.4 % of women [D4].
- Blue-yellow (tritan) CVD affects fewer than 1 in 10,000 people. It affects men and women equally [P1].

## Method

- Protan and deutan: Machado, Oliveira and Fernandes 2009 matrices at severity 0.6 and 1.0 [S1]. The matrices apply to linear RGB, as in DaltonLens [S2].
- Tritan: Brettel, Viénot and Mollon 1997 at severity 1.0, with the DaltonLens sRGB parameters [S2][S3]. DaltonLens calls Brettel "the most solid and basically only valid choice" for tritanopia. Machado does not model tritanopia well [S2].
- Difference: CIEDE2000 (ΔE00) in CIELAB D65. The script also gives OKLab ΔE and OKLab ΔL. The ΔE00 code passes the Sharma test pair (2.0425).
- Each cell is the worst value over all eight palette modes: three papers and dark, each in normal and high contrast.
- Thresholds, chosen for this note: below 5 is **collapsed** (bold). From 5 to 10 is *weak* (italic). 10 or more holds. A small mark beside text needs more difference than a full-width swipe button.
- Script: [`colour-vision-sim.py`](colour-vision-sim.py). Run it with a mode and the path of the palette files.

## Results (ΔE00, worst over all modes)

"Worst ΔL" is the smallest OKLab lightness difference over all simulations, times 100.

| Group | Pair | Normal | Protan 0.6 | Protan 1.0 | Deutan 0.6 | Deutan 1.0 | Tritan 1.0 | Worst ΔL |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| accent tint | oxblood vs claret | *9.2* | 11.8 | 12.1 | 10.5 | *8.3* | **0.9** | 0.0 |
| accent tint | oxblood vs green | 47.9 | 19.6 | *5.3* | 16.9 | *7.6* | 41.6 | 2.2 |
| accent tint | oxblood vs plum | 16.8 | 20.7 | 22.4 | 22.1 | 21.9 | *5.1* | 0.1 |
| accent tint | claret vs green | 52.4 | 26.4 | 15.3 | 20.6 | **2.8** | 40.9 | 2.2 |
| accent tint | claret vs plum | *8.1* | *9.3* | *8.9* | 11.1 | 13.3 | **4.3** | 0.1 |
| accent tint | green vs plum | 52.8 | 31.7 | 25.4 | 26.3 | 14.7 | 38.9 | 1.6 |
| favourite on/off | oxblood | 27.6 | 20.9 | 17.2 | 20.6 | 19.0 | 26.8 | 6.3 |
| favourite on/off | claret | 27.7 | 20.3 | 15.0 | 17.7 | *9.6* | 26.4 | 6.6 |
| favourite on/off | green | 24.9 | 14.3 | 12.2 | 14.5 | 12.3 | 23.5 | 8.6 |
| favourite on/off | plum | 28.7 | 23.6 | 20.9 | 23.7 | 16.4 | 24.8 | 7.3 |
| swipe, leading | Play Next vs Add to Queue (all accents) | 40.5 | 43.2 | 44.0 | 44.2 | 45.2 | 31.0 | 0.1 |
| swipe, trailing | oxblood: Download vs Reference | 55.9 | 32.2 | 29.5 | 35.4 | 38.9 | 55.2 | 2.9 |
| swipe, trailing | claret: Download vs Reference | 53.7 | 27.2 | *9.8* | 26.7 | 27.0 | 54.0 | 3.0 |
| swipe, trailing | green: Download vs Reference | 23.2 | 25.7 | 25.3 | 24.9 | 24.1 | **2.3** | 0.0 |
| swipe, trailing | plum: Download vs Reference | 43.8 | 17.1 | 10.6 | 19.2 | *5.9* | 50.4 | 2.5 |
| swipe, across | Play Next vs Download (all accents) | 22.5 | *6.8* | *8.7* | *5.5* | *5.2* | 10.3 | 0.4 |
| swipe, across | Add to Queue vs Download (all accents) | 38.9 | 36.2 | 34.1 | 39.1 | 38.2 | 45.5 | 1.3 |
| swipe, across | oxblood: Add to Queue vs Reference | 21.0 | 13.7 | *7.6* | *7.7* | **2.6** | 11.8 | 1.5 |
| swipe, across | green: Add to Queue vs Reference | 38.8 | 14.5 | *7.9* | 16.0 | 12.3 | 42.2 | 1.7 |
| swipe, across | plum: Add to Queue vs Reference | 40.2 | 43.1 | 41.9 | 38.8 | 33.2 | *6.8* | 0.4 |
| swipe, across | plum: Play Next vs Reference | 22.1 | 14.0 | *5.8* | 16.0 | 11.0 | 33.2 | 1.9 |
| swipe, across | green: Play Next vs Reference | 38.0 | 36.2 | 35.4 | 32.9 | 30.6 | *8.0* | 0.1 |
| vs system red | oxblood tint | 13.6 | 14.4 | 15.2 | 12.5 | 12.2 | 12.1 | 1.7 |
| vs system red | oxblood favourite | *6.9* | *8.2* | *9.0* | *6.3* | *5.9* | *5.4* | 3.5 |
| vs system red | claret tint | 20.1 | 24.4 | 25.1 | 21.5 | 19.5 | 12.9 | 1.7 |
| vs system red | claret favourite | 18.6 | 25.5 | 26.4 | 20.1 | 16.0 | *6.2* | 3.3 |
| vs system red | green tint | 59.6 | 26.8 | 12.4 | 23.5 | 18.5 | 50.9 | 0.0 |
| vs system red | green favourite | 64.9 | 25.8 | *7.4* | 23.7 | 14.6 | 55.9 | 0.5 |
| vs system red | plum tint | 27.2 | 33.1 | 35.2 | 33.7 | 32.0 | 16.5 | 1.2 |
| vs system red | plum favourite | 28.8 | 38.7 | 41.7 | 39.3 | 36.8 | *9.3* | 3.7 |

Other "across" pairs hold (10 or more) in every simulation.

Notes on the results:

- The swipe colours share one lightness by design (OKLab L 0.55 to 0.59, white label 4.6:1). So a simulation that removes one hue axis leaves almost no difference. Worst ΔL is 0 to 3.
- Favourite set and not set differ by chroma and by lightness. OKLab ΔL is 6 or more in every simulation. Their luminance contrast to each other is only 1.3:1 to 2.2:1. In grey scale or for a listener with monochromacy, the two states are close.
- Under simulated protanopia the favourite keeps 3.8:1 or more against the paper. This is above the 3:1 for non-text marks [W2].

## How iOS and design systems handle CVD

- Apple, Accessibility: "Convey information with more than color alone." People with CVD "may have particular difficulty with pairings such as red-green and blue-orange." Apple asks for "distinct shapes or icons, in addition to color" [A1].
- Apple, Color: "Avoid relying solely on color to differentiate between objects, indicate interactivity, or communicate essential information." Use "text labels or glyph shapes to identify objects or states" [A2].
- Apple asks for light, dark and increased-contrast variants of each custom colour. The increased-contrast variant must give "a significantly higher amount of visual differentiation" [A2].
- Differentiate Without Color is a system setting. SwiftUI reads it as `accessibilityDifferentiateWithoutColor`. When it is true, "UI should not convey information using color alone and instead should use shapes or glyphs" [A3]. UIKit has `UIAccessibility.shouldDifferentiateWithoutColor` [A4].
- WCAG 1.4.1 (level A): colour is not "the only visual means of conveying information, indicating an action, prompting a response, or distinguishing a visual element" [W1]. Technique G183 accepts 3:1 luminance contrast between a link and the text around it [W1].
- WCAG 1.4.11: a visual cue for a component state needs 3:1 against adjacent colours. IBM Carbon applies the same rule [W2][D3].
- Okabe and Ito: "Do not convey information in color only." Combine colour with "different shapes, positions, line types". Two warm or two cool colours need a clear difference in brightness or saturation. Use vermilion for red, because protanopes can see it [D1].
- Google Material: "Start with grayscale! This removes hue from the equation." Google builds colour pairs on tone (lightness), not on hue [D2].
- IBM Carbon: "Don't rely on color alone to convey meaning." Check designs with a CVD simulator [D3].

Common rule of all sources: colour is a second channel. Shape, icon, text or lightness carries the meaning.

## Recommendations

### Accent switch

1. Keep the switch. One accent is active at a time. A red-green collapse between two options hides no information in the app.
2. Give each option a name in Settings, not only a swatch. A deuteranope sees claret and bottle green as nearly the same colour (2.8).
3. Drop oxblood or claret, or move one of them. They differ by 9.2 for normal vision and by 0.9 for tritans. Both differ from plum by less than 10 for tritans. A fourth option with a different lightness or a blue hue gives a real choice.
4. Keep the oxblood favourite away from system red. It sits 5.4 to 9.0 from system red for everyone. An error must never depend on red alone. Show an icon and text with each error, as Apple asks [A1].

### Swipe colours

1. Keep an icon and a label on each action, as the prototype does. With them, the swipe colours meet WCAG 1.4.1, because colour is not the only cue.
2. Give the two actions on each side different lightness. White labels allow only darker steps. Make Add to Queue and Reference darker by OKLab ΔL 0.12. Their white labels then reach 7.5:1 or more. In the faint paper mode, the worst trailing pair rises to 13.1 for green and 9.7 for plum. The leading pair rises to 34.0. Run the check again in `palette.py` for all modes.
3. Keep Reference in the favourite hue only when the lightness step separates it from Download. For green, the teal Download and the green Reference are the same colour for tritans without the step.
4. Play Next and Download stay weak for red-green CVD. This is acceptable, because they never show at the same time.

### Favourite on and off

1. For red-green and tritan CVD, the two states stay apart (9.6 or more). They differ in chroma and lightness.
2. They still differ only in colour. WCAG 1.4.1 and Apple both ask for a second cue [W1][A1]. The luminance contrast between the states is 1.3:1 to 2.2:1, below the 3:1 of G183.
3. Read `accessibilityDifferentiateWithoutColor`. When it is on, change the shape of one state, for example a not-set mark as an outline. **This departs from ADR 0032** ("No outline"). Flo must decide before any change.
4. The VoiceOver label already carries the state (ADR 0032). This covers VoiceOver users, not sighted listeners with CVD.

## Sources

- [S1] Machado, Oliveira, Fernandes: "A Physiologically-based Model for Simulation of Color Vision Deficiency", IEEE TVCG 15(6), 2009. Matrices: https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
- [S2] DaltonLens, review of open-source CVD simulations: https://daltonlens.org/opensource-cvd-simulation/ and source https://github.com/DaltonLens/DaltonLens-Python/blob/master/daltonlens/simulate.py
- [S3] Brettel, Viénot, Mollon 1997, parameters in libDaltonLens: https://github.com/DaltonLens/libDaltonLens/blob/master/libDaltonLens.c
- [P1] MedlinePlus Genetics, Color vision deficiency: https://medlineplus.gov/genetics/condition/color-vision-deficiency/
- [A1] Apple HIG, Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- [A2] Apple HIG, Color: https://developer.apple.com/design/human-interface-guidelines/color
- [A3] SwiftUI `accessibilityDifferentiateWithoutColor`: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor
- [A4] UIKit `shouldDifferentiateWithoutColor`: https://developer.apple.com/documentation/uikit/uiaccessibility/shoulddifferentiatewithoutcolor
- [W1] W3C, Understanding SC 1.4.1 Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
- [W2] W3C, Understanding SC 1.4.11 Non-text Contrast: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- [D1] Okabe and Ito, Color Universal Design: https://jfly.uni-koeln.de/color/
- [D2] Google codelab, Designing with accessible colors (Material 3): https://codelabs.developers.google.com/color-contrast-accessibility
- [D3] IBM Carbon, Accessibility and color: https://carbondesignsystem.com/guidelines/accessibility/color
- [D4] IBM Carbon, Accessibility overview: https://carbondesignsystem.com/guidelines/accessibility/overview/
