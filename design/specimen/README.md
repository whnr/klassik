# Design

The specimen is the design reference of Klassik: what is decided, in light, dark and Increase Contrast. The pages on screen are the reference. A rule that a page cannot show is a short comment in that page's HTML. Claret is the default accent.

## Principles

- The work comes first. An album only tells where a recording comes from.
- Klassik shows the listener's own library and picks nothing for them.
- Everything is ready before a page opens. No page waits for the network.
- Facts read as prose, with no separator glyphs.
- Native iOS first: system tabs, stacks, sheets, glass and gestures.
- The phone is the judge. The checks cannot judge looks.

## Pages

- `index.html`: the Library tab and the frame of every page, with links to every page.
- `library.html`: the Library tab, drawn from a list of rows (`library.js`, `library.css`). `?rows=all` draws every row kind; `?rows=composers,albums` draws the kinds named. `?edit=1` opens the edit sheet on load; `?edit=row` opens the settings of the Composers row; `?edit=empty` adds a row with nothing to show. The edit sheet is `library-edit.js` and `library-edit.css`; its Filter level is the Search filter sheet (`filters.js`, `filters.css`). The specimen bar has Reset rows.
- `work.html`: a work page. `?work=<composer>|<work>` picks another work.
- `player.html`: a recording or album page. `?embed=player` is the player overlay. `?recording=<id>` or `?album=<id>` picks another.
- `chronology.html`: one composer among the contemporaries, and the overview (`?level=overview`).
- `search.html`: Search and its Filters sheet, built on the shared frame. `?filters=example` opens it on three conditions, with the third marked and the Performers picker open. Scroll the sheet to see the picker stick under the header.
- `list.html`: the shared list page frame, with Composers as sample content. `?lang=en` and `?lang=de` draw both languages. `?state=filtered`, `empty`, `no-match`, `keyboard`, `long` or `accessibility` opens a review state. `?sheet=settings`, `filter`, `sort` or `form` opens the shared sheet. The specimen bar switches states. Form choices and section rules need sign-off.
- `person.html`: a composer or performer page. `?name=<artist name>`.
- `settings.html`, `lookup.html`, `storage.html`, `server.html`, `rules.html`, `swipe.html`: Settings and its pages.
- `tokens.html`: the token sheet: every colour in the four themes, contrast, type scale, spacing, radius, size and motion.
- `sheet.html`: the shared sheet frame at its two levels, and its rules. `sheet.css` and `sheet.js` hold the frame. `filters.js` and `filters.css` hold the filter sheet that Search and the Library edit sheet share.
- `menu.html`: the page menu, one page per variant, drawn open. `?for=recording`, `album`, `work` or `player`; `?state=none`, `downloading`, `downloaded` or `offline`.

The pill at the top belongs to the specimen, not to the app. It sets the timeline edge, room, accent, player look, contrast, Dynamic Type size and what plays. The settings stay in the URL.

## Files

- `specimen.css`, `specimen.js`: the frame and the components. Pages read tokens only; a fixed value is chrome that iOS fixes.
- `library.*`, `pill.*`, `overlay.*`, `timeline.css`, `cover.*`, `picture.*`: the Library rows, the mini player, the player overlay, the timeline, the cover room and the person picture.
- `../tokens.css`: written by `design/scripts/tokens.py` from the token files. `design/scripts/palette.py` solves the colours from their contrast targets; `check.py` proves the pairs.
- `../marks/fermata.svg`: the favourite mark and the master of its SF Symbol. `FermataMark.swift` draws and scales it.
- `../fonts/`: [Wittgenstein](https://github.com/jrgdrs/Wittgenstein) by Jörg Drees, SIL Open Font License (`OFL.txt`), for page titles and section headings at weight 500.
- `data/`: the Navidrome responses and the Wikidata facts that the pages show (see `data/README.md`).

## Conventions

- A comment names the shared part, such as "the shared sheet frame", never a file name. In every tracked file except Markdown, `design/scripts/check.py` refuses a comment (`//`, `#`, `/* */`, `<!-- -->`) with a file name of type `.html`, `.css` or `.js` in parentheses.
- To check a theme by script, open the page with `?theme=dark` or `?theme=light`. The URL parameter survives every look control. Setting `data-theme` on the root element after load also works, but a look control resets it. `emulateMedia` alone does not switch the pages.

## Variants

A look under review adds its variants to `variants/variants.json` or `variants/looks.json`; `?variant=<name>` or `?look=<name>` loads them. When Flo decides, the winning values go into the token files and the base files, and the variant files go.

## Run

Raise the `?v=` stamp on the `tokens.css`, `specimen.css` and `specimen.js` links in every page before a deploy, because the server sends no cache header.

In `design/`, run `python3 -m http.server 8765 --bind 0.0.0.0` and open `http://<laptop>:8765/specimen/`. Covers and pictures load from Wikimedia Commons.

The Preview workflow publishes the specimen of every push to `gh-pages`: `/c/<sha>/specimen/` for one commit, `/b/<branch>/specimen/index.html` for the newest push of a branch. The bot comments the links on the pull request. Forks are not published.

The specimen approximates native glass, display corners and system gestures. The installed app is their check. With each UX change, update the affected pages and run `design/scripts/lint.sh`.
