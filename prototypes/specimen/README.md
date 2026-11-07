# Specimen

The design specimen of map sz-rs30.1.83 (ticket sz-rs30.1.83.4). Every look ticket shows its variants here. It shows Klassik's decided tokens on four screens and a token sheet, in light and dark.

## Pages

- `index.html`: the Library place, with links to every page.
- `work.html`: a work page with recording rows. `?work=<composer>|<work>` picks another work.
- `player.html`: the page of what plays, with the cover wash, the timeline and the open movement. `?recording=<id>` or `?album=<id>` shows another page; Play turns it into the player in place.
- `chronology.html`: one composer among the contemporaries, and the overview (`?level=overview`).
- `search.html`: the field finds works, names and albums; filters on demand. Round 3 of sz-rs30.1.83.7 shows three places for the filters: `?variant=search-sheet`, `search-panel`, `search-chips`.
- `person.html`: a composer or performer page with the screen-wide picture (ADR 0017, 0019). `?name=<artist name>`.
- `tokens.html`: the token sheet. Every colour in the four themes side by side, contrast on rows, the type scale at each Dynamic Type size, spacing, radius, size and each animation alone. The Settings tab opens it.

The flows follow ADR 0013 to 0020. Nothing comes from the UX prototypes.

## Specimen controls

The pill at the top belongs to the specimen, not to the app. It sets the variant, the theme (auto, light, dark), high contrast, the Dynamic Type size and what plays (a recording, a Chopin album, weak tags, nothing). The settings stay in the URL and in the session, so links keep them.

## Values

- `tokens.css` is a copy of `design/tokens.css` on `main`, which `scripts/tokens.py` writes. Refresh it with `git -C <repo> show main:design/tokens.css > tokens.css`.
- `specimen.css` and every page read tokens only. A fixed value in them is chrome that iOS fixes, such as the tab label size.
- Favourites, listening notes and the queue are specimen state in the session. The favourite mark is the fermata of ADR 0017.

## Variants

A look ticket adds its variants to `variants/variants.json`:

```json
{ "a": { "label": "A serif", "css": "a.css", "js": "a.js" } }
```

`?variant=a` loads `variants/a.css` after the frame and `variants/a.js` before the page renders. A variant overrides tokens, such as `:root { --type-body-family: ...; }` and `[data-theme="dark"] { --color-tint: ...; }`. It may add rules for a drawn view. When Flo decides, the winning values go into `design/klassik.tokens.json` on `main`, and `tokens.css` here is refreshed.

## Data

`data/specimen.json` holds the Navidrome responses (see `data/README.md`). `data/chronology.json` holds composer dates and work years from Wikidata, because the server gives none. `data/people.json` holds the Wikidata facts, Commons picture and Wikipedia lead of each composer and performer. `make_chronology.py` and `make_people.py` in `data/` write them again. The specimen cannot detect faces, so every Wikidata picture shows.

## Run

In `prototypes/`, run `python3 -m http.server 8765 --bind 0.0.0.0` and open `http://<laptop>:8765/specimen/`. The covers load from Wikimedia Commons, so the phone needs network access.
