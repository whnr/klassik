# Display typefaces for work titles

Question: which typefaces can set work titles and page titles beside SF Pro? Example titles: "Symphony No. 5 in C minor, Op. 67" and "Kinderszenen, Op. 15: Nr. 7 Träumerei". This list adds twelve faces to the known five: New York, Source Serif 4, EB Garamond, Cormorant Garamond and Newsreader.

Checked 2026-11-08.

## Method

- Licence, designer, date and upstream repository come from the `METADATA.pb` of each family in the `google/fonts` repository [GF1], or from the upstream repository [J1].
- Dates and axes come from the Google Fonts family metadata [GF2].
- Glyph coverage, OpenType features, axes and digit widths come from fontTools 4.67 on the full TTF files [GF1][J2].
- The coverage test string is `čřěëñøåőűłżß ŠŽĆąęœæÆŒŁ`. Every face below has all of these glyphs.
- "Tabular" means a `tnum` feature, or default digits of one width. "Small caps" means a `smcp` feature with drawn glyphs.
- Size is the upright file as the `google/fonts` repository ships it. The italic is a second file of about the same size.

## Prototype constraint: web subsets drop small caps

The Google Fonts CSS API and the Fontsource packages serve subset files. The `latin` subset of Poltawski Nowy keeps `tnum` and `lnum`, but drops `smcp` and `onum`. The `latin-ext` subset has no GSUB table at all [GF3]. Thus:

- Use the CSS URL for a quick look at the shapes.
- Use the full TTF (column "Full file") to test small caps, old-style figures and tabular figures. Bundle that file next to the prototype page.

The app bundles the full TTF, so this constraint applies only to the prototype.

## Candidates

| Face | Style | Added | Licence | Tabular | Small caps | opsz | Weights | Size | CSS URL | Full file |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Hedvig Letters Serif | Contemporary, slab-flavoured text serif | 2023 | OFL 1.1 | no | no | yes, 12–24 | 400 only, no italic | 122 kB | [css][c1] | [ttf][f1] |
| Wittgenstein | Classical book face | 2024 | OFL 1.1 | yes (default) | no | no | 400–900 | 106 kB | [css][c2] | [ttf][f2] |
| Ancizar Serif | Contemporary humanist text serif | 2025 | OFL 1.1 | yes | yes | no | 300–900 | 193 kB | [css][c3] | [ttf][f3] |
| Playfair (2.0) | Transitional / Didone with optical sizes | 2023 | OFL 1.1 | yes | yes | yes, 5–1200; also wdth | 300–900 | 1.78 MB | [css][c4] | [ttf][f4] |
| Bodoni Moda | Didone with optical sizes | 2020, v2.005 | OFL 1.1 | yes | yes | yes, 6–96 | 400–900 | 162 kB | [css][c5] | [ttf][f5] |
| Piazzolla | Contemporary, sharp old style | 2020, v2.005 | OFL 1.1 | yes | yes | yes, 8–30 | 100–900 | 625 kB | [css][c6] | [ttf][f6] |
| Literata | Contemporary book serif | 2018, v3.103 | OFL 1.1 | yes | yes | yes, 7–72 | 200–900 | 955 kB | [css][c7] | [ttf][f7] |
| Brygada 1918 | Old style revival (Polish, 1918) | 2021 | OFL 1.1 | yes | yes | no | 400–700 | 242 kB | [css][c8] | [ttf][f8] |
| Poltawski Nowy | Antykwa revival (Półtawski, 1928) | 2023 | OFL 1.1 | yes | yes | no | 400–700 | 415 kB | [css][c9] | [ttf][f9] |
| Ibarra Real Nova | Spanish Baroque old style (1780) | 2019 | OFL 1.1 | no | yes | no | 400–700 | 114 kB | [css][c10] | [ttf][f10] |
| Junicode 2 | Garamond-family old style, scholarly | v2.226, 2026-06 | OFL 1.1 | yes | yes | no; wdth 75–125 | 300–700 | 1.0 MB (woff2) | none | [woff2][f11] |
| Ysabeau | Humanist sans on a Garamond skeleton (foil) | 2023 | OFL 1.1 | yes | yes | no | 1–1000 | 432 kB | [css][c12] | [ttf][f12] |

The OFL 1.1 allows bundling and sale with software. The font files keep their own licence; the app code stays Apache-2.0. Ship `OFL.txt` with the app and do not use a Reserved Font Name for a modified file [OFL].

## Why each face fits

**Hedvig Letters Serif.** Kanon Foundry drew it with Alexander Örn and Tor Weibull for the brand Hedvig [GF1]. Its optical size axis covers exactly the 12–24 pt range of list rows. The forms are calm and modern, with short, firm serifs. It has one weight and no italic. Thus it cannot mark a movement in italic or a title in bold. The digits are proportional, so catalogue numbers do not align in a column.

**Wittgenstein.** Jörg Drees drew it as a book face in the German tradition [GF1]. The texture is even and dark enough for a phone screen. The default digits are tabular, so "Op. 67" and "BWV 1007" align without a feature switch. It has no small caps. It is the new face nearest to a classic German score title page.

**Ancizar Serif.** César Puertas and the Universidad Nacional de Colombia drew it as a university text face; Google Fonts added it in 2025 [GF1]. It has the full set: tabular and old-style figures, small caps, nine weights and italics. The italic is lively and suits movement names. It is sober and modern, not historical.

**Playfair 2.0.** Claus Eggers Sørensen extended Playfair to an optical size axis from 5 to 1200 and a width axis [GF2]. At opsz 17–34 the contrast drops, and the face reads like a transitional serif. At large sizes it becomes a high-contrast Didone for page titles. The width axis can fit a long title such as "Das wohltemperierte Klavier, BWV 846–893" on one line. Its cost is the file size: 1.78 MB for the upright.

**Bodoni Moda.** Owen Earl drew a Bodoni with an optical size axis from 6 to 96 [GF1]. The text sizes keep the Didone elegance and lose the hairlines that break on a phone. It has tabular figures and small caps. It suits a page title more than a dense list.

**Piazzolla.** Juan Pablo del Peral of Huerta Tipográfica drew it for dense text [GF1]. It has an optical size axis from 8 to 30, the exact range of the app. The forms are sharp and slightly angular, with energy but no kitsch. The full feature set is present. The name of an Argentine composer is a small bonus.

**Literata.** TypeTogether drew it for Google Play Books [GF1]. It is the most proven screen serif in this list, with optical sizes from 7 to 72. It is less individual than the others. It is the safe choice if the more distinctive faces fail on the device.

**Brygada 1918.** Capitalics revived a Polish typeface from 1918 [GF1]. It is a warm old style with a strong italic. It has tabular figures and small caps.

**Poltawski Nowy.** The same team revived Antykwa Półtawskiego, the Polish national typeface of 1928 [GF1]. It has a distinct, slightly calligraphic rhythm and high contrast. Titles look printed, not digital. It has the full feature set.

**Ibarra Real Nova.** José María Ribagorda and Octavio Pardo revived the type of the 1780 Ibarra "Don Quixote" [GF1]. It is the most bookish face here. It has small caps but proportional digits only. Use it for page titles, not for columns of numbers.

**Junicode 2.** Peter Baker drew it for medieval scholars; version 2.226 appeared in June 2026 [J1]. It is not on Google Fonts. It has the largest character set here, small caps and tabular figures. Its width axis (75–125) can condense a long title without a fake squeeze. Its file is the largest here. It is not on a CDN that an artifact page may load, so bundle the file.

**Ysabeau.** Christian Thalmann, the designer of Cormorant, drew a sans serif on a Garamond skeleton [GF1]. It is the foil: a title face that is not a serif but still classical. It pairs with Cormorant Garamond from the known list. Its weight axis runs from 1 to 1000, so it can match the weight of SF Pro exactly. Google Fonts also lists a variant, `Ysabeau Office` [GF2].

## Considered and left out

- Libertinus Serif (added 2025): the Google Fonts build has no GSUB table, so no small caps [GF1]. The upstream release has them [L1].
- Fraunces: the "wonky" forms read as playful, not classical.
- Redaction (added 2026-10): drawn for a project about court documents. The register is wrong for music.
- Castoro, Imbue, Hedvig: proportional digits. Hedvig stays in the table for its forms.
- Instrument Serif, Gloock: condensed display faces. Too narrow at 17 pt.
- Crimson Pro: no small caps. Vollkorn and Cardo: sturdy, but less elegant than the faces above.

## Sources

- [GF1] `google/fonts` repository, `ofl/<family>/METADATA.pb` and font files: <https://github.com/google/fonts/tree/main/ofl>
- [GF2] Google Fonts family metadata: <https://fonts.google.com/metadata/fonts>
- [GF3] Google Fonts CSS2 API with a Chrome user agent, and Fontsource `@fontsource-variable/poltawski-nowy@5.3.0`: <https://cdn.jsdelivr.net/npm/@fontsource-variable/poltawski-nowy@5.3.0/files/>
- [J1] Junicode releases and licence: <https://github.com/psb1558/Junicode-font/releases/tag/v2.226>
- [J2] Junicode web file (version 2.003, inspected): <https://github.com/psb1558/Junicode-font/tree/master/webfiles>
- [L1] Libertinus releases: <https://github.com/alerque/libertinus/releases>
- [OFL] SIL Open Font License 1.1: <https://openfontlicense.org/open-font-license-official-text/>

[c1]: https://fonts.googleapis.com/css2?family=Hedvig+Letters+Serif:opsz@12..24&display=swap
[c2]: https://fonts.googleapis.com/css2?family=Wittgenstein:ital,wght@0,400..900;1,400..900&display=swap
[c3]: https://fonts.googleapis.com/css2?family=Ancizar+Serif:ital,wght@0,300..900;1,300..900&display=swap
[c4]: https://fonts.googleapis.com/css2?family=Playfair:ital,opsz,wdth,wght@0,5..1200,87.5..112.5,300..900;1,5..1200,87.5..112.5,300..900&display=swap
[c5]: https://fonts.googleapis.com/css2?family=Bodoni+Moda:ital,opsz,wght@0,6..96,400..900;1,6..96,400..900&display=swap
[c6]: https://fonts.googleapis.com/css2?family=Piazzolla:ital,opsz,wght@0,8..30,100..900;1,8..30,100..900&display=swap
[c7]: https://fonts.googleapis.com/css2?family=Literata:ital,opsz,wght@0,7..72,200..900;1,7..72,200..900&display=swap
[c8]: https://fonts.googleapis.com/css2?family=Brygada+1918:ital,wght@0,400..700;1,400..700&display=swap
[c9]: https://fonts.googleapis.com/css2?family=Poltawski+Nowy:ital,wght@0,400..700;1,400..700&display=swap
[c10]: https://fonts.googleapis.com/css2?family=Ibarra+Real+Nova:ital,wght@0,400..700;1,400..700&display=swap
[c12]: https://fonts.googleapis.com/css2?family=Ysabeau:ital,wght@0,1..1000;1,1..1000&display=swap
[f1]: https://raw.githubusercontent.com/google/fonts/main/ofl/hedviglettersserif/HedvigLettersSerif%5Bopsz%5D.ttf
[f2]: https://raw.githubusercontent.com/google/fonts/main/ofl/wittgenstein/Wittgenstein%5Bwght%5D.ttf
[f3]: https://raw.githubusercontent.com/google/fonts/main/ofl/ancizarserif/AncizarSerif%5Bwght%5D.ttf
[f4]: https://raw.githubusercontent.com/google/fonts/main/ofl/playfair/Playfair%5Bopsz,wdth,wght%5D.ttf
[f5]: https://raw.githubusercontent.com/google/fonts/main/ofl/bodonimoda/BodoniModa%5Bopsz,wght%5D.ttf
[f6]: https://raw.githubusercontent.com/google/fonts/main/ofl/piazzolla/Piazzolla%5Bopsz,wght%5D.ttf
[f7]: https://raw.githubusercontent.com/google/fonts/main/ofl/literata/Literata%5Bopsz,wght%5D.ttf
[f8]: https://raw.githubusercontent.com/google/fonts/main/ofl/brygada1918/Brygada1918%5Bwght%5D.ttf
[f9]: https://raw.githubusercontent.com/google/fonts/main/ofl/poltawskinowy/PoltawskiNowy%5Bwght%5D.ttf
[f10]: https://raw.githubusercontent.com/google/fonts/main/ofl/ibarrarealnova/IbarraRealNova%5Bwght%5D.ttf
[f11]: https://cdn.jsdelivr.net/gh/psb1558/Junicode-font@v2.226/webfiles/JunicodeVF-Roman.woff2
[f12]: https://raw.githubusercontent.com/google/fonts/main/ofl/ysabeau/Ysabeau%5Bwght%5D.ttf
