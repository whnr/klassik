# 0052. Favourites wait for server sync

Date: 2026-11-18. Decided by Flo. Bead: sz-rs30.1.117.4. Refines the offline queue of [0013](0013-favourites.md).

## Context

Flo requires favourites to stay in the app when the server cannot save them.
A failed server request must not undo a tap.

## Decision

- Save each recording or album change on the device before sending it to the server.
- Keep the mark, recording order and pending changes for each server and listener through relaunch and sign-out.
- Send pending changes in order. Retry when the connection returns, at launch and on return to the foreground.
- Keep pending changes after a server refusal. Server reads cannot replace pending local choices.
- After sync, server changes from other apps still apply, as ADR 0013 requires.
- Show one notice for each failed tap: “No internet connection. This syncs when you are back online.”
- A server refusal explains that the device saved the favourite but server sync failed.
- Automatic retries show no notices. Work favourites stay local.

## Consequences

The listener can set and remove favourites offline without losing a choice.
A refused change waits until the server accepts it. Later changes wait behind it.
