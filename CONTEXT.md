# Klassik

An iPhone player for classical music on an OpenSubsonic server. The listener looks for a work first, then picks a performance of it.

## Language

### Music

**Work**:
A composition that a composer wrote, such as a symphony or one étude. It is the primary object of the app.
_Avoid_: Piece, song

**Movement**:
One part of a work that has its own track, such as the Adagio of a symphony.
_Avoid_: Track, part

**Recording**:
One performance of a work, as the tracks of that work on one album.
_Avoid_: Performance, version

**Album**:
The release that a recording comes from. It shows provenance, and the listener can make it a favourite.
_Avoid_: Disc, CD

**Reference recording**:
The first recording in the list of a work: the first favourite recording, else the first that a favourite lifts, else the newest. It plays when the listener plays the work.
_Avoid_: Default recording

### Classical filter

**Classical rule**:
A rule that the listener edits to say which tracks are classical. A track matches when any classical rule matches. An album counts when most of its tracks match.
_Avoid_: Filter, condition

**Check**:
One test in a classical rule, such as "Genre contains Classical" or "Has a work". A classical rule matches when all of its checks match.
_Avoid_: Condition, criterion, clause

### Views

**Place**:
One of the top-level parts of the app that the listener moves between: Library, Chronology and Search. Settings opens from the Library toolbar.
_Avoid_: Tab, section, area

**Library**:
The place that holds the listener's own collection: composers, playlists and favourites. It shows nothing that Klassik picks for the listener.
_Avoid_: Home, Browse

**Chronology**:
The place that shows one composer's works by year, among the composers of their time. Its overview shows all composers.
_Avoid_: Timeline, History

**Active years**:
The years from a composer's work period start in Wikidata until their death. Before them, the Chronology draws the line dim.
_Avoid_: Career, working life

**Contemporary**:
A composer in the library whose active years overlap those of the composer in focus, 10 years before and after (ADR 0026).
_Avoid_: Neighbour, peer

**Page**:
A view about one thing, such as a composer, work, recording, album or performer. A link pushes it onto the stack of the current place.
_Avoid_: Screen, detail view

**Stack**:
The pages a listener opened in one place, in order. Back leaves the top page. A link always pushes a page, also one that the stack holds.
_Avoid_: History, trail, breadcrumbs

**Work page**:
The page of one work: its composer and its recordings, each with its own cover. The work page has no cover of its own.
_Avoid_: Work screen

**Recording page**:
The page of one recording: its cover, performers, album and one row for each movement. It has the player's layout, but it must not look like the player while another recording plays.
_Avoid_: Player, work page

**Album page**:
The page of one album: its works and their tracks in disc order. It has the player's layout.
_Avoid_: Disc page, release page

**Composer page**:
The page of one composer: a picture, the Wikidata description and years, then the Works and About tabs. About holds the bio and every credit.
_Avoid_: Artist page, composer screen

**Performer page**:
The page of one conductor, soloist or ensemble. It has the composer page's layout, with the Albums and About tabs.
_Avoid_: Artist page, musician page

**Genre**:
A label from the tags of a track. A track carries one to many genres. Klassik gives no meaning to their order or style.
_Avoid_: Category, period, form

**Search term**:
One value that the listener adds to a search: a genre, composer, conductor or performer. A genre value carries no facet, because the app does not know which value is the period.
_Avoid_: Rule, filter, token, criterion

**Condition**:
One row of a search. Its search terms join with "or". The conditions of a search join with "and", and each condition shows how many recordings remain.
_Avoid_: Set, group, clause, step

**Recent search**:
A search that the listener made, kept on the device with its text and its conditions. The empty Search page lists them, newest first.
_Avoid_: History, suggestion, saved search

**Search session**:
The time from the first text or condition until the x pill clears the search. One search session is one recent search.
_Avoid_: Query, visit

**Set**:
Works that share a GROUPING tag, such as Etudes, Op. 10. A set folds into one row that opens in place.
_Avoid_: Group, cycle, collection

**Scope**:
The kind of search term that the filter sheet lists: genres, composers, conductors or performers. A scope with an empty field lists every search term of that kind.
_Avoid_: Facet, category, tab

**Timeline**:
The bar on the screen edge that shows the whole work or album that plays, one segment for each movement or track. It is always on screen, and the listener scrubs on it.
_Avoid_: Rail, edge bar, progress bar

**Mini player**:
The pill at the end of the timeline, in the tab bar row: play/pause and the square cover. The cover opens the player.
_Avoid_: Now playing bar

**Player**:
The recording page or album page of the queue item that plays. The mini player links to it.
_Avoid_: Now playing, playback screen

**Queue item**:
One thing in the queue: a recording, or a whole album. When it ends, the next queue item takes the player.
_Avoid_: Track, entry

### Listener data

**Favourite**:
A composer, performer, work, recording or album that the listener marks as liked. It has no scale.
_Avoid_: Mark, like, love, rating

**Listening note**:
A note that the listener attaches to a position in one recording. The same note does not fit another recording of the work, because tempos differ.
_Avoid_: Timeline tag, timeline comment, bookmark
