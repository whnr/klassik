# 0022. Chronology taps open pages

Date: 2026-11-07. Decided by Flo after the first specimen round. Bead: sz-rs30.1.83.10. Replaces parts of [0016](0016-chronology.md).

## Context

ADR 0016 opened a card with Play and Open Work when the listener tapped a work. A sideways drag moved to another composer while the finger moved, and it mapped the screen width onto every composer in the library. On the phone, Flo always expected a work to open its page. The card was one step too many. A live drag moved the chart under the finger before the listener had chosen. Flo expected the drag to pick among the lines he sees.

## Decision

- A tap on a work opens its work page. The card with Play and Open Work goes.
- A tap on a row that stands for several works lists them. A tap on a work in the list opens its work page.
- A tap on the composer's name opens the composer page.
- A sideways drag scrubs across the composers on the screen: in the overview all composers, at the composer level the focus composer and the contemporaries in view. The width of the chart maps onto those lines in order.
- During the drag, the label names the composer under the finger, and that composer's line is highlighted. The chart stays. On release, the chart glides to that composer.
- The Chronology still opens on the composer of what plays, with that work marked (ADR 0016).
- The overview marks the composer of what plays. It also marks the composer that the listener last opened.

## Consequences

- Play from the Chronology goes through the work page, which says which recording plays.
- The overview needs two marks that differ from each other and from the plain lines. Their look belongs to the design map.
