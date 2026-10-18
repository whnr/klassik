# 0009. The reference recording is a star

Date: 2026-10-17, built 2026-10-18. Decided by Flo. Bead: sz-rs30.1.6.

## Context

A work has several recordings. The listener has one favourite for each work. Klassik keeps no state of its own that the server can hold (see 0002).

## Decision

- A recording is the reference of its work when the server stars all its tracks.
- Setting a reference stars the tracks of the recording and unstars the tracks of the other recordings of the work.
- The start of a work plays the reference recording. Without one, it plays the oldest recording.
- A star on a recording is not a like of the work. A later local flag can mark favourite works.

## Consequences

- Other apps show and change the same stars. A star from another app shows in Klassik after the next full sync.
- An album has no reference, because it can hold several works.
