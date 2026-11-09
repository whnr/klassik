# A readable colour from any cover

Question: which methods take a colour from cover art and keep text on it readable at WCAG 2.2 AA? The answer feeds the cover wash of the player page (ADR 0015) and a possible per-cover tint for the timeline and the playing row.

Checked 2026-11-09. Material Color Utilities (MCU) at commit `194144d` [M1]. Android Palette from `androidx-main` [P1]. Timings come from MCU 0.3.0 in Node 20 on an Intel i7-8550U (2017 laptop CPU), on synthetic 128 × 128 covers.

## The contrast rule

- Contrast ratio = (L1 + 0.05) / (L2 + 0.05). L is relative luminance; L1 is the lighter colour. Do not round: 4.499:1 fails 4.5:1 [W1].
- Body text needs 4.5:1. Large text (18 pt, or 14 pt bold) needs 3:1 [W1]. Marks and controls need 3:1 [W2].
- WCAG measures text against the background colour that the text is drawn on. A background image without enough contrast is a listed failure [W1]. So text must sit on a flat colour that Klassik computes, not on the cover itself.
- CIE L\* (the "tone" in MCU) maps one-to-one to luminance Y. So the ratio of two colours is a function of their two tones only [M2]. Hue and chroma do not change it. This makes tone the control to clamp.
- MCU's rule of thumb: a tone difference of 40 gives at least 3:1, a difference of 50 gives at least 4.5:1 [M2].

## Methods

| Method | How it picks the colour | Grey, dark, pale, multi-coloured cover | Contrast guarantee for text | Cost on device | Licence |
| --- | --- | --- | --- | --- | --- |
| Apple Music API and MusicKit `Artwork` | Apple's server computes it. `bgColor` is "the average background color of the image" [A1]. MusicKit gives `backgroundColor` and `primaryTextColor` to `quaternaryTextColor` [A2]. | Unknown: Apple publishes no method. | Apple supplies four text colours for each background [A1]. Apple states no ratio. | None on device. | Only for Apple Music catalogue items. OpenSubsonic `getCoverArt` returns image bytes only, with no colour field [O1]. Not usable for Klassik. |
| Apple Music player background (iOS app) | Not documented. Apple publishes no API or method for it. | Unknown. | Unknown. | n/a | Not available to apps. |
| `MPMediaItemArtwork` | Holds an image only [A3]. The lock screen picks its own colours, and the app cannot read them. | n/a | n/a | n/a | System. |
| Image Playground, visual intelligence | They generate images or answer visual searches [A7][A8]. Neither returns colours from an image. | n/a | n/a | n/a | System. |
| SwiftUI and UIKit (iOS 26, iOS 27) | No public API returns a colour from an image. "What's new in SwiftUI" (WWDC26) names none [A6]. | n/a | n/a | n/a | System. |
| Core Image `CIAreaAverage` | Mean of all pixels, as a 1 × 1 image [A4]. | A painting with dark and pale parts averages to a muddy mid-grey-brown. A multi-coloured cover averages to grey. | None. | One GPU pass. Sub-millisecond on a small image. | System, iOS 14+. |
| Core Image `CIKMeans` | k-means clustering. Output: `count` × 1 image; RGB is a cluster centre, alpha is its weight. `count` default 8, max 128. `passes` default 5, max 20. `perceptual` switches to a perceptual colour space [A5]. | Gives the main clusters with their weights. It does not rank them. Klassik must score them (as MCU does) and handle grey. | None. | GPU. Small for a 64 × 64 input. | System, iOS 14+ [A5]. No dependency. |
| MCU `QuantizerCelebi` + `Score` | Wu quantizer, then WSMeans (weighted k-means) [M1][M3]. Resize to 128 × 128 first; `maxColors` 128 [M4]. `Score` adds each hue's share within a 30° window. It drops colours with chroma below 5 or hue share at or below 1 %. Score = share × 70 + (chroma − 48) × 0.1 below 48 or × 0.3 above. It then keeps up to 4 colours at least 90° apart, down to 15° [M5]. | Grey: every colour drops out, and `Score` returns Google Blue `#4285F4` [M5]. Test: a grey photo gave `#4285F4`. Klassik must detect this case. Dark oil: gave brown `#40281A` (T19, C16), then oxblood `#661702` (T22, C52). Pale fresco: gave ochre `#DAC3A7` (T80, C14), then blue-grey (T66). Multi-coloured: four colours 90° apart; red first. `DislikeAnalyzer` lifts dark yellow-green (hue 90–111, chroma > 16, tone < 65) to tone 70 [M6]. That moves olive tones of oil paintings. | The extraction gives none. The `Contrast` module solves tone for a ratio: `darker(tone, ratio)` and `lighter(tone, ratio)` return −1 if no tone reaches it [M7]. `DynamicScheme` guarantees 4.5:1 for all text and 3:1 for required marks at default contrast [M2]. | Warm: 40 ms per cover in JavaScript on the 2017 CPU. Cold first run: 100–150 ms. Run off the main thread and cache by cover ID. | Apache-2.0, same as Klassik [M1]. A Swift port lives in `swift/` [M1]. The repository root has no `Package.swift`, so SwiftPM cannot add it. Klassik would copy about 2,900 lines (Hct, Quantize, Score, Contrast, Utils). `Hct` is a non-`Sendable` class, so Swift 6 needs small changes. |
| Android Palette (androidx) | Resize to 112 × 112. A median-cut variant splits RGB boxes by colour volume, not by population, to find distinct colours [P1][P2]. Up to 16 colours. Six targets (Vibrant, Muted, each Light/normal/Dark) by HSL lightness and saturation. Weights: saturation 0.24, lightness 0.52, population 0.24 [P3]. | The default filter drops near-black (HSL L ≤ 0.05), near-white (L ≥ 0.95) and hue 10–37° with saturation ≤ 0.82 [P1]. That hue band is skin, and also the browns and ochres of old-master oils. A dark oil can lose its main colour. Grey: targets stay empty. | Each swatch gives title text (3:1) and body text (4.5:1) colours. It tries white with the lowest alpha that passes, then black [P1]. Text on the swatch passes. The swatch itself is not moved. | Small: 112 × 112 pixels, one pass. | Apache-2.0 [P1]. Java, Android only; a port is needed. |
| OKLab / OKLCH tone clamp | Not an extractor. Convert the picked colour to OKLCH, keep hue, set lightness L, reduce chroma until it is in sRGB. | Works on any input. A grey stays grey, so a fallback is still needed. | Only if Klassik computes the WCAG ratio for each step. OKLab L predicts perceived lightness [K1]. It is not luminance Y, so equal L does not give equal ratio. | Microseconds. | Reference code public domain or MIT [K1]. |
| CSS `contrast-color()` | Returns white or black, whichever gives more contrast. The spec leaves the algorithm to the browser. It warns against the plain WCAG 2.1 ratio but asks for at least AA large text (3:1) [K2]. | Works on any background. | 3:1 only. | n/a | Web only. Shows that a black-or-white flip alone fails 4.5:1 body text. |
| Color Thief (JS) | Median-cut quantizer. 3.x adds OKLCH quantization and WCAG contrast helpers: `contrast.white`, `contrast.black`, `textColor` [L1]. | Gives the main colours. No special grey handling stated. | Picks black or white text by WCAG ratio [L1]. | Small. | MIT [L1]. JS only. |
| node-vibrant (JS) | Port of Android Palette [L2]. | As Palette. | As Palette. | Small. | MIT [L2]. JS only. |
| fast-average-color (JS) | Average, with options for dominant colour [L3]. | As `CIAreaAverage`. | None. | Very small. | MIT [L3]. |
| UIImageColors (Swift) | "iTunes style": background = most common colour on the image edge; then primary, secondary and detail colours [L4]. | Picks text colours of the opposite darkness. | Its `isContrasting` needs only 1.6:1, on gamma-encoded values [L5]. Fails WCAG. | Small. | MIT. Archived [L4]. |
| DominantColor (Swift) | k-means in CIELAB, CIE94 distance by default [L6]. | Gives clusters; no ranking for theme use. | None. | Small. | MIT [L6]. Few updates since 2023. |

## Tone clamps for Klassik's palette

Values from MCU `Contrast` [M7]. Tone is CIE L\*.

| Background | Text or mark | Needed tone of the foreground |
| --- | --- | --- |
| Ivory paper, T96 | Body text 4.5:1 | T46.7 or darker |
| Ivory paper, T96 | Mark 3:1 | T58.3 or darker |
| Near-black, T8 | Body text 4.5:1 | T53.9 or lighter |
| Near-black, T8 | Mark 3:1 | T42.6 or lighter |
| Day wash, T88 | Secondary text 4.5:1 | T41.0 or darker |
| Night wash, T18 | Secondary text 4.5:1 | T61.0 or lighter |

- Ink T8 on a day wash of T90 gives 13.8:1. Ink T92 on a night wash of T14 gives 12.7:1. A wash near the paper tone keeps the fixed ink colours.
- One tint tone cannot serve day and night. A tint needs ≤ T46.7 on ivory and ≥ T53.9 on near-black. So Klassik computes two tints from one hue.
- Accents oxblood, bottle green, bronze and plum must meet the same tones. The token file holds them, with high-contrast values (ADR 0021).
- A cover colour computed at run time has no asset-catalog high-contrast value. With Increase Contrast on (`colorSchemeContrast == .increased`), raise the target to 7:1, or use the fixed palette.

## Recommendation

1. **Pick with `CIKMeans`, score like MCU, clamp tone in CIE LCh.** No dependency.
   - Downscale the cover to 64 × 64. Run `CIKMeans` with `count` 8, `perceptual` on.
   - Score each cluster: weight × 70 + chroma term, as MCU `Score` [M5]. Drop chroma below 5.
   - No cluster left (a grey photo, a pencil drawing): use Klassik's tint. ADR 0015 asks for this.
   - Wash: same hue, tone T88–92 by day and T12–18 by night, chroma capped low (about 8–16). The page keeps its fixed ink.
   - Tint for timeline and playing row: same hue, tone clamped to ≤ T46 by day and ≥ T54 by night, so it passes 4.5:1 as text and 3:1 as a mark.
   - Bring each colour into sRGB by lowering chroma at fixed hue and tone. Then check the final pair with the WCAG formula [W1]. Step the tone until it passes.
   - Cache by cover ID. Test with fixture covers from `scripts/fixtures.py`: grey, dark, pale and multi-coloured.
2. **Fallback: copy MCU's Swift port** (Apache-2.0) if the `CIKMeans` picks look wrong on real covers. Its HCT solver keeps hue and chroma while it sets tone, and `Contrast` gives exact tones. Handle the Google Blue fallback and `DislikeAnalyzer` (olive tones) yourself.

Do not use Android Palette's default filter: it drops the browns and ochres of oil paintings. Do not put text on the cover or on `CIAreaAverage` without a clamp.

## Sources

- [W1] W3C, Understanding SC 1.4.3 Contrast (Minimum), WCAG 2.2. https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- [W2] W3C, Understanding SC 1.4.11 Non-text Contrast, WCAG 2.2. https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- [A1] Apple, Apple Music API, `Artwork` object. https://developer.apple.com/documentation/applemusicapi/artwork
- [A2] Apple, MusicKit, `Artwork` (`backgroundColor`, `primaryTextColor` …). https://developer.apple.com/documentation/musickit/artwork
- [A3] Apple, `MPMediaItemArtwork`. https://developer.apple.com/documentation/mediaplayer/mpmediaitemartwork
- [A4] Apple, `CIFilter.areaAverage()`. https://developer.apple.com/documentation/coreimage/cifilter-swift.class/areaaverage()
- [A5] Apple, `CIFilter.kMeans()`. https://developer.apple.com/documentation/coreimage/cifilter-swift.class/kmeans()
- [A6] Apple, WWDC26 session 269, What's new in SwiftUI. https://developer.apple.com/videos/play/wwdc2026/269
- [A7] Apple, Image Playground. https://developer.apple.com/documentation/imageplayground
- [A8] Apple, Visual Intelligence. https://developer.apple.com/documentation/visualintelligence
- [O1] OpenSubsonic, `getCoverArt`. https://opensubsonic.netlify.app/docs/endpoints/getcoverart/
- [M1] material-foundation/material-color-utilities, README and `LICENSE`. https://github.com/material-foundation/material-color-utilities
- [M2] MCU, `concepts/contrast_for_accessibility.md`.
- [M3] MCU, `typescript/quantize/quantizer_celebi.ts`.
- [M4] MCU, `dev_guide/extracting_colors.md`.
- [M5] MCU, `typescript/score/score.ts`.
- [M6] MCU, `typescript/dislike/dislike_analyzer.ts`.
- [M7] MCU, `typescript/contrast/contrast.ts`.
- [P1] AndroidX, `palette/.../Palette.java`. https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/palette/palette/src/main/java/androidx/palette/graphics/Palette.java
- [P2] AndroidX, `ColorCutQuantizer.java`, same directory.
- [P3] AndroidX, `Target.java`, same directory.
- [K1] Björn Ottosson, A perceptual color space for image processing. https://bottosson.github.io/posts/oklab/
- [K2] W3C, CSS Color Module Level 5, `contrast-color()`. https://drafts.csswg.org/css-color-5/#contrast-color
- [L1] lokesh/color-thief, README; npm `colorthief` 3.5.0, MIT. https://github.com/lokesh/color-thief
- [L2] Vibrant-Colors/node-vibrant; npm `node-vibrant` 4.0.4, MIT. https://github.com/Vibrant-Colors/node-vibrant
- [L3] fast-average-color, MIT. https://github.com/fast-average-color/fast-average-color
- [L4] jathu/UIImageColors, README, MIT, archived. https://github.com/jathu/UIImageColors
- [L5] UIImageColors, `UIImageColors/Sources/UIImageColors.swift`, `isContrasting`.
- [L6] indragiek/DominantColor, README, MIT. https://github.com/indragiek/DominantColor
