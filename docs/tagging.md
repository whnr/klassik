# Tagging

Klassik reads the tags that the server sends and never changes them. This page tells which tag gives each name in the app.

## Titles

A classical TITLE tag often holds the work and the movement in one line, such as `Symphonie Nr.3 Es-Dur "Eroica": I. Allegro con brio`. Klassik does not edit this line. It takes each name from its own tag:

| Name in the app | Tag | Example |
| --- | --- | --- |
| Work title | WORK, as written | `Symphonie Nr. 3 Es-Dur, Op. 55` |
| Movement | MOVEMENTNAME; without it, TITLE | `Allegro con brio` |
| Track of an album without WORK tags | TITLE, as written | `Liebesleid` |
| Line under the work title | the part that all TITLE tags of the first recording share, when it differs from WORK | `Symphonie Nr.3 Es-Dur "Eroica"` |

So the movement row shows no work name, key or nickname. These stay in the TITLE tag, and the rules below use them.

## Nicknames

A nickname, such as "Eroica", is part of the work. Navidrome has no tag of its own for it: it adds TIT3 to the title.

- Klassik finds a nickname in quotes in the part that all TITLE tags of one recording share. A single track counts up to its first colon.
- The quotes can be `"…"`, `“…”`, `„…“`, `«…»`, `»…«` or `‘…’`.
- Quotes in a movement name, after the shared part, do not count. `Sonata: II. "Marcia funebre"` gives no nickname.
- Search finds the work by its nicknames as it does by its title. A row found only by a nickname shows `Nickname: …`.
- A WORK tag that holds the nickname, such as `Symphonie Nr. 3 Es-Dur „Eroica“, Op. 55`, needs none of this.

## Search

Search matches the start of each word. It ignores case and diacritics.

- Sections run in this order: Composers, Works, Albums, Performers. Albums holds only albums. A recording shows only inside its work.
- Works rank in four steps: the title starts with the text; the title or a nickname holds every word; the composer or the set matches; a track title matches.
- A work or album found by a track title shows a line `Track: …`. A track with a WORK tag finds its work. Only a track without one finds its album.
- A nickname needs quotes in the title to be found (see [Nicknames](#nicknames)).
- Search has no alias list and no catalogue prefixes. `op67` does not find `Op. 67`, and `K. 626` does not find `KV 626`.
