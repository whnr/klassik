# 0017. Composer and performer pages

Date: 2026-11-04. Decided by Flo after six prototype rounds. Beads: sz-rs30.1.74.8, sz-rs30.1.74.12. The naming note for grouped works is replaced by [0020](0020-set-and-condition.md). The outline of a mark that is not set is replaced by [0032](0032-fermata-mark.md).

## Context

Every composer and performer name on the work, recording and album pages is a link, so both pages must exist. The old composer page showed two full lists: sets and works. Tags differ between libraries. A track carries one to many genres, in each library's own style. Flo's tag contract is one style among many. Wikidata gives a picture, a description and life dates. Its descriptions repeat the years in some items only.

## Decision

- A composer page shows a picture, the name, a description line, a Chronology button, and two tabs: Works and About.
- A performer page has the same layout. Its tabs are Albums and About.
- The picture is as wide as the screen and runs under the timeline. It shows the part of the whole picture around the face. It is a view, not a crop. A tap shows the whole picture with its credit.
- Under the timeline, the picture blurs and fades into the page, as the iOS 26 scroll edge effect does under a bar.
- The picture has no caption. About holds the bio and every credit: picture, text and facts.
- Each fact shows once. The description line gives the Wikidata description without years, then the years. Tag roles show only when Wikidata has no description.
- The Works tab lists the works A to Z. Works that share a grouping fold into one row that opens in place.
- Genre chips above the list filter the works. Several chips join with "or". A genre that every work carries does not show. Klassik reads genres as plain labels and gives no meaning to their order.
- The Albums tab shows the performer's albums as covers, newest first. On the album page, each work opens its recording page.
- A composer tag that gives only a surname, such as "Strauss", is matched through its works: the Wikidata composer of the tagged works decides. Only when the works do not decide does the page ask the listener to pick from the Wikidata matches. The listener can choose again or pick "None of these".
- When the works of one surname tag belong to different composers, the page tells the listener to retag them with full names. Klassik does not split the tag.
- The favourite mark sits right after the title on every page: composer, performer, work, recording and album. It is filled when set and an outline when not. It replaces the Favourite buttons.

## Consequences

- The composer page needs the Wikidata match, description, P569, P570, P18 and the Wikipedia lead (ADR 0011). It also needs the Commons author, licence and file page, and a face rectangle from Vision on the device.
- The Works tab needs `genres[]` from every track of each work, and the grouping of each work.
- The performer page needs `contributors[]` with roles, `artists[]` without a role, and the albums of each performer. A star on the artist marks a favourite performer (ADR 0013).
- Performer pictures and descriptions from Wikidata are not researched yet.
- Commons gives the author as HTML, sometimes as a file name. The app must clean it.
- A face that is small in a wide photo zooms at most twice the cover size.
- The name for works that share a GROUPING tag is open. "Set" belongs to Search.
- Layout, colours and type are not decided here. They belong to the design system map (sz-rs30.1.83).
