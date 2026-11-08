# Specimen

The design specimen of map sz-rs30.1.83 (ticket sz-rs30.1.83.4). Every look ticket shows its variants here. It shows Klassik's decided tokens on four screens and a token sheet, in light and dark.

## Pages

- `index.html`: the Library place, with links to every page.
- `work.html`: a work page with recording rows. `?work=<composer>|<work>` picks another work.
- `player.html`: the page of what plays, with the cover wash, the timeline and the open movement. A tap opens a movement row: the performers that differ from the whole page (ADR 0014) and its notes, the play button in place of the chevron. An album page heads its tracks by work only when a work has two movements on consecutive tracks (ADR 0024). `?recording=<id>` or `?album=<id>` shows another page; Play turns it into the player in place. Movement rows follow sz-rs30.1.83.8: a faint play button at the end of every row; a row with notes or with names that differ from the header opens under a trailing disclosure chevron. The header shows what every track shares, the composer included. After a quiet spell the view brings the playing row back (ADR 0014). A scrub on the timeline holds the rows still until the finger lifts. A row that does not play has no bar. A note is written in the playing row: one tap starts it at the playing time and opens the text field; "End here" is optional and makes a span. The first pill button puts the timeline on the right or the left edge (`?side=`), on every page.
- `chronology.html`: one composer among the contemporaries, and the overview (`?level=overview`).
- `search.html`: the field finds works, names and albums; filters on demand in a sheet (ADR 0025). The field and the Filters button sit at the top under the back arrow, which returns to the page Search was opened from. The x clears the text. The empty page lists recent searches, newest first; Enter or opening a result keeps the query. Filters closes the keyboard as the sheet rises (sz-rs30.1.83.13).
- `person.html`: a composer or performer page with the screen-wide picture (ADR 0017, 0019). `?name=<artist name>`.
- `tokens.html`: the token sheet. Every colour in the four themes side by side, contrast on rows, the type scale at each Dynamic Type size, spacing, radius, size and each animation alone. The Settings tab opens it.

The flows follow ADR 0013 to 0020. Nothing comes from the UX prototypes.

## Mini player

`pill.css` and `pill.js` draw the mini player of ADR 0028 on every page. They load before any variant, so a variant can still replace the mini player through `K.setMini`.

## Specimen controls

The pill at the top belongs to the specimen, not to the app. The page scroll indicator is drawn by hand so it runs beside the timeline. It sets the variant, the theme (auto, light, dark), high contrast, the Dynamic Type size and what plays (a recording, a Chopin album, weak tags, nothing). The settings stay in the URL and in the session, so links keep them.

## Values

- `tokens.css` is a copy of `design/tokens.css` on `main`, which `scripts/tokens.py` writes. Refresh it with `git -C <repo> show main:design/tokens.css > tokens.css`.
- `specimen.css` and every page read tokens only. A fixed value in them is chrome that iOS fixes, such as the tab label size.
- Favourites, listening notes and the queue are specimen state in the session. Close the tab to reset them. The favourite mark is the fermata of ADR 0017.

## Variants

A look ticket adds its variants to `variants/variants.json`:

```json
{ "a": { "label": "A serif", "css": "a.css", "js": "a.js", "page": "player" } }
```

`page` limits the variant menu to that page; without it the variant shows on every page. The empty choice, "decided", shows the decided tokens only. `?variant=a` loads `variants/a.css` after the frame and `variants/a.js` before the page renders. A variant overrides tokens, such as `:root { --type-body-family: ...; }` and `[data-theme="dark"] { --color-tint: ...; }`. It may add rules for a drawn view. When Flo decides, the winning values go into `design/klassik.tokens.json` on `main`, and `tokens.css` here is refreshed.

## Data

`data/specimen.json` holds the Navidrome responses (see `data/README.md`). `data/chronology.json` holds composer dates and work years from Wikidata, because the server gives none. `data/people.json` holds the Wikidata facts, Commons picture and Wikipedia lead of each composer and performer. `make_chronology.py` and `make_people.py` in `data/` write them again. The specimen cannot detect faces, so every Wikidata picture shows.

## Run

The server sends no cache header, so Safari keeps old copies. Raise the `?v=` stamp on the `tokens.css`, `specimen.css` and `specimen.js` links in every page before a deploy.


In `prototypes/`, run `python3 -m http.server 8765 --bind 0.0.0.0` and open `http://<laptop>:8765/specimen/`. The covers load from Wikimedia Commons, so the phone needs network access.
