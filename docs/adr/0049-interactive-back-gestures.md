# 0049. Back gestures follow the finger

Flo decided this in the 0.14.1 test notes. Bead: sz-3hcq.5.
This replaces the edge gesture rules of [0038](0038-standard-tabs-and-the-cross-tab-back.md).

## Context

Cross-tab swipes changed pages after release. The left timeline intercepted the system gesture.
Flo wants slow drags and flicks that move the page with the finger.

## Decision

- A back drag follows the finger, including across tabs and with the timeline on the left.
- A short drag returns to the current page. A completed drag returns to the previous page.
- Keep the system navigation transition within each tab.
- Across tabs, reveal the previous tab under the outgoing page. Preserve both stacks and their scroll positions.
- Cancellation preserves the back target. Reduce Motion reduces the settling animation.

## Consequences

The window receives edge gestures through the timeline. A cross-tab preview restores its selection and origin on cancellation.
