# Specimen

The design reference of Klassik: every decision of the design map sz-rs30.1.83 and the colour map sz-rs30.1.83.19 on six pages and a token sheet, in light, dark and Increase Contrast. It shows only what is decided (ADR 0021 to 0035). Claret is the default accent.

## Pages

- `index.html`: the Library place, with links to every page.
- `work.html`: a work page with recording rows. `?work=<composer>|<work>` picks another work.
- `player.html`: the page of what plays, in the cover room (or the hall, a setting), with the timeline and the open movement. A tap opens a movement row: the performers that differ from the whole page (ADR 0014) and its notes, the play button in place of the chevron. An album page heads its tracks by work only when a work has two movements on consecutive tracks (ADR 0024). `?recording=<id>` or `?album=<id>` shows another page; Play turns it into the player in place. Movement rows follow sz-rs30.1.83.8: a faint play button at the end of every row; a row with notes or with names that differ from the header opens under a trailing disclosure chevron. The header shows what every track shares, the composer included. After a quiet spell the view brings the playing row back (ADR 0014). A scrub on the timeline holds the rows still until the finger lifts. A row that does not play has no bar. A note is written in the playing row: one tap starts it at the playing time and opens the text field; "End here" is optional and makes a span. The first pill button puts the timeline on the right or the left edge (`?side=`), on every page.
- `chronology.html`: one composer among the contemporaries, and the overview (`?level=overview`).
- `search.html`: the field finds works, names and albums; filters on demand in a sheet (ADR 0025). The field and the Filters button sit at the top under the back arrow, which returns to the page Search was opened from. The x in the field clears the text; the x pill beside Filters clears the text and every condition. The empty page lists recent searches, newest first, each with its filters; One search session is one entry: Enter, Done on the filters, opening a result and leaving the page update it; the x pill ends the session. Back from a result keeps the search; a tab or a link opens Search fresh. A tap restores the text and the filters. A pick in the filters clears their narrowing field. Filters closes the keyboard as the sheet rises (sz-rs30.1.83.13).
- `person.html`: a composer or performer page with the screen-wide picture (ADR 0017, 0019). The name sits on the picture over a blur and a measured scrim (ADR 0034). `?name=<artist name>`.
- `tokens.html`: the token sheet. Every colour in the four themes side by side, contrast on rows, the type scale at each Dynamic Type size, spacing, radius, size and each animation alone. The Library cog opens Settings. Settings links to the token sheet.

The flows follow ADR 0013 to 0029. Nothing comes from the UX prototypes.

## Words and role lines

The pages carry no middle dot (sz-rs30.1.83.16). Facts read as prose: "Recorded in 1972 on Dvořák Symphonies. 42 minutes, 4 movements." Durations round to the minute. Counts stand in words; a section heading takes its count in lighter parentheses, "Recordings (23)". Names in one role join with commas and "and". `K.roleBlock` sets names one line per role behind a small-cap label; at accessibility sizes the label stands above its names. `?edge=sort` shows every personal name in sort form ("Kubelík, Rafael").

## Mini player

`pill.css` and `pill.js` draw the mini player of ADR 0028 on every page. They load before any variant, so a variant can still replace the mini player through `K.setMini`.

## Specimen controls

The pill at the top belongs to the specimen, not to the app. It sets the timeline edge, the room (light or dark, never from the system settings), the accent (claret, bottle green, plum), the player look (cover room or hall), Increase Contrast, the Dynamic Type size and what plays (Beethoven 5, a Chopin album, the Matthäus-Passion, the Chopin sonatas, weak tags, nothing). The settings stay in the URL and in the session, so links keep them. The page scroll indicator is drawn by hand so it runs beside the timeline. The specimen pill pushes the timeline down; the app starts it at the top safe area.

## Drawn views

- `timeline.css`: the timeline shape of ADR 0035. `K.setTimeline` sets the gap between two segments.
- `cover.css` and `cover.js`: the player page while it plays (ADR 0034). The cover room solves the ground, secondary text, the tint and the favourite from the cover's hue; the hall lights the dark room with a glow in the cover's hue.
- `picture.css` and `picture.js`: the person picture. The script measures the blurred picture under the name and sets the scrim just strong enough (ADR 0034).
- `pill.css` and `pill.js`: the mini player of ADR 0028. A look can replace it through `K.setMini`.
- The fermata of ADR 0033 is drawn in `specimen.js`; `design/marks/fermata.svg` on `main` holds the same path.

## Values

- `tokens.css` is `design/tokens.css` on `main`, which `design/scripts/tokens.py` writes from the token files. The copy under `design/specimen/` on `main` links it directly.
- `specimen.css` and every page read tokens only. A fixed value in them is chrome that iOS fixes, such as the tab label size.
- Favourites, listening notes and the queue are specimen state in the session. Close the tab to reset them.
- `design/scripts/palette.py` solves the colour values from their contrast targets (ADR 0037); `design/scripts/check.py` proves the pairs.

## Variants for a new look ticket

A look ticket adds its variants to `variants/variants.json` or `variants/looks.json`; both are empty when nothing is open. `?variant=<name>` or `?look=<name>` loads its css and js after the decided files, and the pill shows a menu. When Flo decides, the winning values go into the token file on `main`, the decided rules into the base files here, and the variant files go.

## Data

`data/specimen.json` holds the Navidrome responses (see `data/README.md`). `data/chronology.json` holds composer dates and work years from Wikidata, because the server gives none. `data/people.json` holds the Wikidata facts, Commons picture and Wikipedia lead of each composer and performer. `make_chronology.py` and `make_people.py` in `data/` write them again. The specimen cannot detect faces, so every Wikidata picture shows.

## Run

The server sends no cache header, so Safari keeps old copies. Raise the `?v=` stamp on the `tokens.css`, `specimen.css` and `specimen.js` links in every page before a deploy.

In the folder above the specimen, run `python3 -m http.server 8765 --bind 0.0.0.0` and open `http://<laptop>:8765/specimen/`. The covers and pictures load from Wikimedia Commons, so the phone needs network access.

## Parity and previews

The frame has three places, a Library Settings cog and a chevron Back button (ADRs 0038 and 0040).
A first tab tap restores its page. A second tap returns to its root.
The scrub label uses 17-point body text and adds 36 points of finger clearance on each edge.
The composer link and fading header follow the app specification.

The specimen shows decided flows for unfinished slices too. It does not prove their installed-app behavior.
Native glass, display corners and system gestures require an installed-app check.
With each UX change, update affected specimen flows and run the design check.

The Design workflow attaches the public specimen to each relevant pull request.
The Specimen Pages workflow publishes main after validation. Its manual run can preview a worker branch.
Enable GitHub Pages with GitHub Actions as its source. The deployment summary gives the phone link.
A manual preview replaces the current site until the next deployment.
