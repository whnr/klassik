# 0046. Composers first, and the performers of a shown page next

Date: 2026-11-17. Decided by Flo after the 0.14.0 build. Bead: sz-rs30.1.105.84.
Replaces the order rule of [0042](0042-wikidata-pass-in-the-background.md): "new persons first, composers before
performers, then due persons".

## Context

ADR 0042 took all new persons first, composers before performers, and then all due persons. So a due composer
waited for every new performer. A page that the listener opened could show performers without facts for a long
time, because the pass reached them only after all composers.

Flo's decision: "Composers load first always. Performers second." And: "If a page is loaded that shows performers
and the performers were not searched yet they are prioritized."

## Decision

- A pass takes all composers before all performers. In each group, new persons come first in library order, then
  due persons with the longest wait first.
- A page that shows performers puts each of its performers without a saved check in front of the pass. The pages
  are the work page, the recording page, the album page, the player and the rows of the performer list on the
  screen. The latest page goes first. The pass keeps at most 100 such performers.
- A shown performer goes first only before its first try of the pass. The retry rule of
  [0044](0044-a-failed-person-goes-to-the-end.md) stays: a failed person goes to the end of the queue.
- A stopped try is no try. A shown performer whose try the system stopped stays in front for the next pass.
- A performer with a saved check, or one that waits for its due time after two failures, is not put in front.

## Consequences

- The composer pages get their facts before any performer page, also when a composer is due again.
- A page that the listener opens during a pass gets the facts of its performers within a few lookups.
- The pass does not start for a shown page. It takes the shown performers when it runs.
