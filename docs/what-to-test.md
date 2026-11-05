Klassik 0.10.4

Album rows show all performers in track order and keep their names stable.
Playback recovers after system interruptions and preserves the queue.
The comparison engine downloads movements during playback.

Known problems
- Recovery can repeat audio since the last position checkpoint, which targets 250 ms.
- iOS controls automatic resume permission. Explicit pauses and headphone removal require Play.
- Download and decoding errors require explicit retry.

On-device checks

1. Open Classical Albums. Open a recording, play, pause, and return. Expect identical performer names. (sz-rs30.1.69, PR #2)
2. Open an album with different performers across movements. Expect each name once, in track order. Increase text size. Expect all names visible. (sz-qf3x, PR #4)
3. Play several movements with the gapless comparison engine. Expect downloads during playback and gapless joins. (sz-vnh1, PR #3; sz-5sbe, PR #5)
4. Queue another recording. Browse, switch tabs, lock the phone for two minutes, and switch apps. Expect playback across movement joins. (sz-5sbe)
5. Receive notifications and play another app's short sound. Expect music to continue or resume when iOS permits. (sz-5sbe)
6. Use Siri, then dismiss it. Receive and end a call. Expect music near the saved position when iOS permits. (sz-5sbe)
7. Pause before a call. Repeat with remote Pause during a call. Expect music to stay paused after each call. (sz-5sbe)
8. Let another music app interrupt Klassik. Return and press Play. Expect playback when session activation succeeds. (sz-5sbe)
9. Remove wired or Bluetooth headphones, then reconnect them. Expect silence until Play. (sz-5sbe)
10. Switch Bluetooth, AirPlay, speaker, and CarPlay routes where available. Expect playback to continue or recover with the queue intact. (sz-5sbe)
11. Reset Media Services in Developer settings during playback. Expect recovery near the saved position. Repeat while paused. Expect silence. (sz-5sbe)
12. Seek during a call, then end the call. Expect playback at that position when iOS permits. (sz-5sbe)
13. Queue another recording. Pause at the final movement's end, then press Play. Expect the queued recording with sound. Repeat without a queue. Expect stopped playback without silent playing controls. (sz-5sbe)
14. Play three uncached movements on a slow connection. Let movement one finish while movement two downloads. Expect movement two selected. Press Next during the wait. Expect movement three to play. (sz-5sbe)
