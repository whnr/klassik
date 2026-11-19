# 0050. Partial works under their own heading

Date: 2026-11-17. Decided by Flo after the 0.14.0 build. Bead: sz-rs30.1.105.76.
The set placement rule is replaced by [0062](0062-sets-stay-in-works.md).
Adds to the Works tab of [0017](0017-composer-and-performer-pages.md).

## Context

The Works tab lists every work A to Z. A recital disc often holds one movement of a work. Such a work then stands
beside the complete symphonies and concertos, and the listener cannot tell which works they have in full.

Flo's decision: "Separate full and partial works (under a setting toggle on by default). Any work that does not
have a full recording will show only under partial."

## Decision

- A recording is partial when the tags give a movement total and the recording holds fewer movements. Without a
  total, Klassik cannot tell, and the recording counts as whole. This is the rule of "3 of 5 movements".
- A work is partial when every recording of it is partial.
- The Works tab shows the other works under "Works (n)", then the partial works under "Partial works (n)". Both
  lists keep the rules of 0017: A to Z, sets folded, genre chips.
- A set can have works in both lists. Each list shows only its own works of the set.
- A list with no works does not show. When no work matches the chips, "Works (0)" and the notice show.
- Settings has the toggle "Separate Partial Works". It is on by default. Off, the tab shows one list "Works (n)".

## Consequences

- A work counts as partial only from its tags. A library without movement totals shows no partial works.
- The specimen data has no movement totals, so person.html shows no "Partial works" list.
