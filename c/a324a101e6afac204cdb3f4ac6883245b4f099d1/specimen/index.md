# Places, stacks and Library

Rules for the frame of every page and for `index.html`, the Library place.

## Places and tabs

- Library, Chronology and Search are native iOS tabs. Each keeps its own `NavigationStack`. Library and Chronology share the tab capsule. Search stays apart, with `UISearchTab.automaticallyActivatesSearch` on, because only then does the system draw it apart.
- Space beside the native tab bar holds the mini player.
- A first tap on a tab restores its stack. A second tap returns to the root of that place.
- Settings is no place. A cog in the trailing toolbar of the Library root pushes it onto the Library stack. So Settings has the system Back and swipe.

## Stacks and Back

- A link always pushes its page onto the stack of the current place, also when the stack holds that page already. Back is one step back. A long trip makes a long stack; the long press on Back lists it.
- Each place keeps the system back button, its edge swipe and its long-press menu. A custom back button would lose the menu and the swipe.
- The system back button shows the chevron only. Its accessibility label names the page behind. So every page needs a short name, such as "Beethoven" or "Karajan, 1962".
- The navigation bar shows no title, because Klassik's long titles and back names were cut to fragments side by side. The large title stays in the page and scrolls with it.
- A tab root that the listener reached from another tab shows a back arrow that copies the system button: leading toolbar position, `chevron.backward`, no name, an accessibility label that names the target. It returns to the previous tab as the listener left it. A place opened with no place behind returns to Library. At launch, Library has no arrow.
- A back drag follows the finger, also across tabs and with the timeline on the left edge. A short drag returns to the current page. Across tabs, the previous tab shows under the outgoing page, and both stacks keep their scroll positions. A cancelled drag keeps the back target. Reduce Motion reduces the settling animation.

## Library

- Library shows only the listener's own collection. It has no Shuffle button and no list of all performers. Search results and the pages that name a performer lead to a performer page.
- Library shows one quiet line under its sync status while changes wait for the server: "Server not reachable. Changes wait on this iPhone.", or "The server did not take some changes. They wait on this iPhone." No answer wins over a refusal. The next good send of each kind clears its part. The line goes when no part is left.
- A failed send of a favourite, a scrobble or the play queue shows no notice anywhere. Only a failure of the device file shows a notice, because then the change is not kept.
- A favourite control changes its mark in the tap, with no animation, and never waits for the server.

## Swipe actions

`swipe.html` shows the buttons on each edge. The colours are in [tokens.md](tokens.md).

## Device checks

The specimen approximates native glass, tab symbols, display corners and system gestures. The installed app is their check.
