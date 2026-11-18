# 0058. One quiet server status

Date: 2026-11-18. Decided by Flo. Beads: sz-rs30.1.121, sz-rs30.1.122. Replaces the notice rule of [0052](0052-favourites-stay-in-the-app.md).

## Context

In 0.14.3 each favourite tap without a server answer showed a notice. Flo: "we would probably just show a server status somewhere rather than complaining for every failed synchronization with the server; that goes for scrobbles as well." He also found that a favourite "seems to wait for server confirmation" and still faded.

## Decision

- A failed send of a favourite, a scrobble or the play queue shows no notice. The change waits on the device, as 0052 says.
- The Library page shows one quiet line under its sync status while changes wait: "Server not reachable. Changes wait on this iPhone." When the server answers but does not take a change: "The server did not take some changes. They wait on this iPhone." No answer wins over a refusal.
- The next successful send of each kind clears its part of the line. The line goes when no part is left.
- Settings shows no listening data error.
- Each favourite control changes its mark in the tap, with no animation. A star change does not rebuild the work index, so the tap never waits for a rebuild or the server.
- Only a failure of the device file still shows a notice, because then the change is not kept.

## Consequences

- The listener sees server trouble only on the Library page.
- A change that the server always refuses keeps the line until a send of its kind goes through.
