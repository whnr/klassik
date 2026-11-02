# Marks for a favourite

Question: which marks do readers, editors and musicians use to say "this one", "keep this" or "important"? The answer feeds the favourite mark of Klassik. Apple Music uses a star, Spotify and Navidrome a heart, and Klassik uses a bookmark for the resume point. So these three are out.

Checked 2026-11-02. Code points come from Unicode 18.0 `UnicodeData.txt` and `NamesList.txt` [U1]. SMuFL code points come from SMuFL `glyphnames.json` [S1]. SMuFL code points are in the Private Use Area. Only a SMuFL music font (for example Bravura) draws them.

## Candidate marks

| Mark | Code point | Origin | Meaning | Why it fits a favourite | Risk or clash |
| --- | --- | --- | --- | --- | --- |
| Manicule ☞ ☛ | U+261E WHITE RIGHT POINTING INDEX ("fist" in type), U+261B BLACK RIGHT POINTING INDEX [U1] | Manuscripts from 12th-century Spain. Very common in 14th- and 15th-century Italy. Still used by readers in the 17th century [H1]. | A reader's hand that points to an important passage [H2]. | It is the reader's own mark, not the publisher's. It says "this one". | The hand cursor of computers copies it [H1]. On a phone it can look like "tap here". U+261D (pointing up) is an emoji with skin tones; U+261E is not [U2]. |
| Nota monogram | none | Medieval readers wrote "nota" in the margin [H3]. | "Note this." Each reader built an own pictogram from the four letters N, O, T, A [H3]. | Personal and handwritten. Klassik could draw its own monogram. | Needs a custom glyph. Most listeners cannot read it. |
| Chrismon (chi-rho) ☧ | U+2627 CHI RHO [U1] | Isidore of Seville, *Etymologiae* I.21.22, about 630 [I1]. | "Only this sign is set by the will of each reader, to mark anything" ("Haec sola ex voluntate uniuscuiusque ad aliquid notandum ponitur") [I1]. | It is the only classical critical sign whose meaning is "the reader's own choice". That is the meaning of a favourite. | Unicode names it a Christogram, "Constantine's cross" [U1]. Listeners read it as a religious symbol. |
| Upper ancora ⸕ | U+2E15 UPWARDS ANCORA [U1] | Isidore, *Etymologiae* I.21.24 [I1]. | "Set where a thing is very great" ("ubi aliqua res magna omnino est") [I1]. | Exact meaning: "this matters a lot". Looks like an anchor: "keep this". | Unicode notes that the glyph points opposite to its name [U1]. The lower ancora means "very base" [I1]. Unknown to listeners. |
| Asterisk (asteriskos) * | U+002A; U+2042 ASTERISM ⁂ [U1] | Aristarchus and the Alexandrian critics; Isidore I.21.2 [I1]. | Marks something omitted, "so that it shines through" [I1]. | A small star with a scholarly root. | Reads as a footnote. Close to the Apple Music star. |
| Obelus, dagger † | U+2020 DAGGER (= obelisk) [U1] | Isidore I.21.3 [I1]. | Marks words that are superfluous or false [I1]. | none: the meaning is negative. | Opposite meaning. |
| Hedera ❧ ❦ | U+2767 (= hedera, ivy leaf), U+2766 FLORAL HEART (= Aldus leaf) [U1] | Roman texts; Aldus Manutius in print [U1][H4]. | End of a text, a section break, or a decorative paragraph start [H4]. | Classical and ornamental. A leaf in place of a heart. | Its shape is a heart. It can read as a copy of the Spotify heart. |
| Pilcrow, capitulum ¶ ⸿ | U+00B6, U+2E3F CAPITULUM (ancestor of the pilcrow) [U1] | Medieval manuscripts [U1]. | Start of a paragraph or section [U1]. | A place in a text. | Text editors use ¶ for "show hidden characters". Weak meaning for "favourite". |
| Fermata 𝄐 | U+1D110 MUSICAL SYMBOL FERMATA [U1]; SMuFL U+E4C0 `fermataAbove` [S1] | Standard Western notation. | The music stops and holds the note until the conductor or soloist moves on [M1]. | "Stay here, linger." Every musician knows it. No music app uses it as a favourite. | Non-musicians see an eye or a dot under an arch. Unicode font support on iOS must be checked. |
| Segno 𝄋 | U+1D10B [U1]; SMuFL U+E047 `segno` [S1] | Standard Western notation. | Marks a place to which the player jumps back [M2]. "D.S." means "go to the sign" [M3]. | "Come back to this." Unusual shape. | Looks like % or $ to a non-musician. |
| Coda 𝄌 | U+1D10C [U1]; SMuFL U+E048 `coda` [S1] | Standard Western notation. | Jump target; also the section that ends a piece [M2][M3]. | A target to jump to. Strong shape. | Looks like a crosshair. "Coda" means "ending", not "favourite". |
| Accent > | U+1D17B COMBINING ACCENT [U1]; SMuFL U+E4A0 [S1] | Standard Western notation. | The note is stressed, more than tenuto [M1]. | "This note counts more." | A combining character: it needs a base glyph. Looks like a chevron ">". |
| Marcato ^ | U+1D17F COMBINING MARCATO [U1]; SMuFL U+E4AC [S1] | Standard Western notation. | The note is extremely stressed [M1]. | Strongest emphasis. | Looks like a caret or "up" chevron. |
| Tenuto – | U+1D17D COMBINING TENUTO [U1]; SMuFL U+E4A4 [S1] | Standard Western notation. | Full duration, or a slight stress [M1]. | "Give it its full value." | Looks like a minus sign or "remove". |
| Breath mark 𝄒 | U+1D112 [U1]; SMuFL U+E4CE [S1] | Standard Western notation. | A quick break or a breath [M1]. | none: it means a pause. | Looks like an apostrophe. |
| Hauptstimme 𝆦 | U+1D1A6 MUSICAL SYMBOL HAUPTSTIMME [U1]; SMuFL U+E860 [S1] | Schoenberg and his school [M4]. | "Principal voice": the line that must stand out. U+1D1A7 Nebenstimme is the secondary voice [U1][M4]. | Exact meaning: "the one that matters". A letter H with a hook. Surprising and from classical music. | Unknown to most listeners. Reads as the letter H. |
| Rehearsal mark | none (a boxed letter or number) | Orchestral scores. MusicXML `<rehearsal>` [M5]. | Letters or numbers in the score "for reference during rehearsal" [M5]. | A boxed letter is a place you find again. | Generic. It looks like a keyboard key. |
| Repeat sign 𝄇 | U+1D107 RIGHT REPEAT SIGN [U1]; SMuFL U+E041 [S1] | Standard Western notation. | A section is repeated [M3]. | "I want to hear this again." | Clash with the repeat button of a player. |
| Spectacles 👓 | U+1F453 EYEGLASSES [U1]; SMuFL U+EC62 `miscEyeglasses` [S1] | Pencil mark in orchestral parts. | "Watch out"; watch the conductor even more carefully [P1][P2]. | A real performer's mark. Witty. | Meaning is "danger", not "love". The emoji reads as "reading" or "nerd". |
| Pencil star | none (U+2606 ☆ as text) | Pencil mark in parts. | A passage to practise [P2]. | none. | The Apple Music star. Pimentel calls circles and stars "so vague as to be pointless" [P3]. |
| Pencil circle | none (U+25CB ○ as text) | Pencil mark in parts. | A trouble spot [P2]. | A circle is easy to draw by hand. | Negative meaning for players [P2]. Too vague [P3]. |
| Note ♪ ♩ 🎵 | U+266A EIGHTH NOTE, U+2669 QUARTER NOTE, U+1F3B5 MUSICAL NOTE (= "music, being in good mood") [U1] | Notation; emoji. | A single note. | Links to a logo made of the first notes of a work. | The generic sign for "music" everywhere. Alone it says "music", not "favourite". |

## What library and catalogue software uses

No surveyed tool has an own glyph for "favourite". They use lists, tags or a 5-star rating.

- Zotero: no favourite. Up to 9 coloured tags, set with the number keys. An emoji in a coloured tag replaces the colour square. "Many people use colored tags for 'to read' or 'favorite' items" [L1].
- MusicBrainz: a rating from 1 to 5 stars, averaged into a community rating [L2].
- VuFind (a library discovery layer): the string key `Add to favorites` shows the text "Save to List" [L3].
- Koha OPAC: "Lists" and a "Cart" [L4].
- WorldCat.org: "Add item to list" and a "Save to" menu. Lists live in the profile [L5].
- Discogs: "Collection" and "Wantlist"; a wantlist item has a rating [L6].
- IMSLP: not checked. Its help pages did not load.

## Short openings for a logo motif

All works below are centuries old. Their composers died before 1900.

- Beethoven, Symphony No. 5, Op. 67 (1804–08) [W1]. Rhythm "da-da-da daah". The BBC used it in 1941 for "V for Victory", because Morse V is three dots and a dash [W2]. Risk: very common; tied to war propaganda and "fate".
- Beethoven, String Quartet Op. 135 (1826) [W3]. The finale has the title *Der schwer gefasste Entschluss*, "the hard-won decision" [W3]. A decision to keep a recording fits the title.
- Schumann, *Carnaval*, Op. 9 (1833–35), subtitled "on four notes" (*auf vier Noten*) [W4]. Schumann spells words with German note names.
- Bach, *Die Kunst der Fuge*, BWV 1080 (1742–50) [W5]. B-A-C-H in German note names is B♭-A-C-B♮.

Not checked against a source: German note names read A = A, S (Es) = E♭, H = B♮. The letters A-S-S in "KLASSIK" then give A-E♭-E♭, in the way of Schumann's A-S-C-H.

## Notes

- The closest historic meaning to "my favourite" is Isidore's chrismon: the reader's free mark [I1]. The closest music meaning is the Hauptstimme: "the voice that matters" [M4]. The best known music mark with a positive meaning is the fermata: "hold this" [M1].
- Unicode Musical Symbols render only with a font that has them. Check iOS support before a choice. SMuFL glyphs need a bundled music font, for example Bravura [S1].
- A combining mark (accent, marcato, tenuto) needs a base. Draw it as a custom image.

## Sources

- [U1] Unicode 18.0 `UnicodeData.txt` and `NamesList.txt`: https://www.unicode.org/Public/UCD/latest/ucd/
- [U2] Unicode `emoji-data.txt`: https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
- [S1] SMuFL `glyphnames.json` (W3C Music Notation CG): https://github.com/w3c/smufl/blob/gh-pages/metadata/glyphnames.json; Miscellaneous symbols table: https://smufl.formats.music/latest/tables/miscellaneous-symbols.html
- [I1] Isidore of Seville, *Etymologiae* I.21, Latin text: https://www.thelatinlibrary.com/isidore/1.shtml
- [H1] William H. Sherman, "Toward a History of the Manicule", CELL forum, March 2005: https://www.livesandletters.ac.uk/papers/FOR_2005_04_001.pdf
- [H2] Erik Kwakkel, "Helping Hands on the Medieval Page", 13 March 2015: https://medievalbooks.nl/tag/manicula/
- [H3] Erik Kwakkel, "Voices on the Medieval Page (1): The Reader", 21 June 2013: https://medievalbooks.nl/tag/manicula/
- [H4] Michael Quinion, World Wide Words, "Hedera": https://worldwidewords.org/ww-hed1.html
- [M1] Andrew Ewell, *High-Yield Music Theory* Vol. 1, "Dynamics and Articulations", p. 25: https://learnmusictheory.net/PDFs/pdffiles/01-01-09-DynamicsArticulations.pdf
- [M2] teoria.com, "Coda": https://www.teoria.com/en/reference/c/coda.php
- [M3] Devin Hart, *Introduction to Music Theory and Rudiments*, ch. 6 "Repeats", MacEwan Open Books: https://openbooks.macewan.ca/introtomusictheory/chapter/repeats/
- [M4] Wikipedia, "Hauptstimme and Nebenstimme" (cites Haimo, *Schoenberg's Serial Odyssey*, p. 38), and LilyPond Snippet 843: https://en.wikipedia.org/wiki/Hauptstimme_and_Nebenstimme, https://lsr.di.unimi.it/LSR/Item?id=843. Medium trust: no primary source found.
- [M5] W3C MusicXML 4.0, element `<rehearsal>`: https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/rehearsal/
- [P1] Royal College of Music, "Ensemble Guidelines" (PDF now 404; quote from search index): https://t4.rcm.ac.uk/media/Ensemble%20Guidelines.pdf
- [P2] Bruce Hembd, Horn Matters, on pencil markings: https://www.hornmatters.com/?p=459
- [P3] Bret Pimentel, "Using a pencil like a pro": https://bretpimentel.com/using-a-pencil-like-a-pro/
- [L1] Zotero, "Collections and Tags": https://www.zotero.org/support/collections_and_tags
- [L2] MusicBrainz, "Rating System": https://musicbrainz.org/doc/Rating_System
- [L3] VuFind `languages/en.ini`, line 29: https://github.com/vufind-org/vufind/blob/dev/languages/en.ini
- [L4] Koha OPAC `masthead.inc`: https://github.com/Koha-Community/Koha/blob/main/koha-tmpl/opac-tmpl/bootstrap/en/includes/masthead.inc
- [L5] OCLC Support, "Work with lists": https://help.oclc.org/Discovery_and_Reference/WorldCat-org/Search_WorldCat-org/Work_with_lists
- [L6] Discogs API client `models.py` (joalla/discogs_client): https://github.com/joalla/discogs_client/blob/master/discogs_client/models.py
- [W1] IMSLP, Symphony No. 5, Op. 67: https://imslp.org/wiki/Symphony_No.5,_Op.67_(Beethoven,_Ludwig_van)
- [W2] Imperial War Museums, "Where does V for Victory come from": https://www.iwm.org.uk/history/where-does-v-for-victory-come-from
- [W3] IMSLP, String Quartet No. 16, Op. 135: https://imslp.org/wiki/String_Quartet_No.16,_Op.135_(Beethoven,_Ludwig_van)
- [W4] IMSLP, Carnaval, Op. 9: https://imslp.org/wiki/Carnaval,_Op.9_(Schumann,_Robert)
- [W5] IMSLP, Die Kunst der Fuge, BWV 1080: https://imslp.org/wiki/Die_Kunst_der_Fuge,_BWV_1080_(Bach,_Johann_Sebastian)
