# Composer and performer pages

Rules for `person.html`.

## Layout

- A composer page shows a picture, the name, a description line, a Chronology button, and the tabs Works and About. A performer page has the same layout with the tabs Albums and About.
- The picture is as wide as the screen and runs under the timeline. It shows the part around the face; it is a view, not a crop. A tap shows the whole picture with its credit. Under the top edge it blurs into the page, as the system scroll edge effect does.
- The picture has no caption. About holds the bio and every credit: picture, text and facts.
- Each fact shows once. The description line gives the Wikidata description without years, then the years. Tag roles show only when Wikidata has no description.
- The favourite mark sits right after the title on every page: composer, performer, work, recording and album.
- The Chronology button returns to the chart when the stack came from it. Its label then reads "Back to Chronology".

## Pictures

- A page shows the Wikidata picture of every person, whatever it shows. Orchestras and quartets often have a group or a hall as their picture.
- A picture with one face centres on that face. A face that is small in a wide photo zooms at most twice the cover size. A composer picture with several faces centres on the largest face. A performer picture with no face or several faces fills the frame from its centre and does not zoom.
- Pictures are prepared before the page opens: decoded at the display size, with the face framing ready. So a page draws its picture in its first frame.
- Low Data Mode permits person pictures. Only album art falls back to placeholders.

## Works tab

- The works stand A to Z. Works that share a GROUPING tag fold into one set row that opens in place.
- Genre chips above the list filter the works. Several chips join with "or". A genre that every work carries does not show. Genres are plain labels; their order means nothing.
- With "Separate Partial Works" on (the default), work rows outside sets stand under "Works (n)", then "Partial works (n)". A recording is partial when the tags give a movement total and it holds fewer movements. A work is partial when every recording of it is partial. Without a total, a recording counts as whole.
- A set shows once, under Works, with all its matching works, because Klassik cannot tell whether a set is complete.
- A list with no works does not show. When no work matches the chips, "Works (0)" and the notice show.

## Albums tab

The performer's albums as covers, newest first.

## Which person a tag names

- The works decide first: when the MusicBrainz composers of the tagged works lead to one Wikidata person, the tag takes that person.
- Else a tag of two or more words takes the one search hit whose name is the tag. A namesake whose description names the tag loses, such as "grandfather of composer Ludwig van Beethoven".
- Only when that does not decide does the page ask the listener to pick. Each row of the pick list is a tap target for its whole width. "Choose Composer Again" lists every hit; the listener can pick "None of these".
- When the works of one surname tag belong to different composers, the page asks the listener to retag them with full names. Klassik does not split the tag.
- The performer search filters Wikidata items by P434, the MusicBrainz artist ID. It reads no ID from the tags. When it finds nothing, it searches again without the filter. When neither finds the performer, the page shows the tags only.
