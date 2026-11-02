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

### Views

**Place**:
One of the top-level parts of the app that the listener moves between: Library, Chronology, Search, Settings.
_Avoid_: Tab, section, area

**Library**:
The place that holds the listener's own collection: composers, playlists and favourites. It shows nothing that Klassik picks for the listener.
_Avoid_: Home, Browse

**Chronology**:
The view that places composers and their works by year.
_Avoid_: Timeline, History

**Search term**:
One value that the listener adds to a search: a genre, composer, conductor or performer. A genre value carries no facet, because the app does not know which value is the period.
_Avoid_: Rule, condition, filter, token, criterion

**Set**:
One row of a search. Its search terms join with "or". The sets of a search join with "and", and each set shows how many recordings remain.
_Avoid_: Group, clause, step

**Scope**:
The kind of search term that the search lists: all kinds, genres, composers, conductors or performers. A scope with an empty field lists every search term of that kind.
_Avoid_: Facet, category, tab

**Mini player**:
The bar that shows what plays, on top of every place.
_Avoid_: Now playing bar

**Player**:
The full view of what plays. It opens from the mini player and covers the place below it.
_Avoid_: Now playing, playback screen

### Listener data

**Favourite**:
A composer, performer, work, recording or album that the listener marks as liked. It has no scale.
_Avoid_: Mark, like, love, rating

**Listening note**:
A note that the listener attaches to a position in one recording. The same note does not fit another recording of the work, because tempos differ.
_Avoid_: Timeline tag, timeline comment, bookmark
