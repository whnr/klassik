# 0052. Favourites stay in the app

Date: 2026-11-18. Decided by Flo. Replaces the offline rules of [0013](0013-favourites.md). The notice rule is replaced by 0058.

## Context

In 0.14.2 a recording or album favourite went back when the server did not answer. Flo: "We allow favorites in app. The sync to opensubsonic happens in the background. We store the state in the app."

## Decision

- The app stores each recording and album favourite on the device before it tells the server. A failed server call never takes a mark back.
- The changes that wait are kept for each server and listener, also after a restart and a sign-out. The queue keeps the newest change for each song and album only.
- The app sends the queue after each tap, at launch, on return to the foreground, and when the connection comes back.
- A change that the server refuses waits in the queue. The next changes go on.
- A star read from the server replaces the local stars, except the stars of changes that wait.
- Each tap whose change cannot go to the server shows one notice. Without a connection: "No internet connection. This syncs when you are back online." A send without a tap shows no notice.
- The album stars are also stored on the device, so that they show without a connection.

## Consequences

- Another app sees an offline change only after Klassik sends it.
- A change that the server always refuses stays on the device and is sent again at each launch.
