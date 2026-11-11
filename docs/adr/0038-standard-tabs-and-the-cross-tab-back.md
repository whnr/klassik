# 0038. Standard tabs, and a back arrow on a root reached from another tab

Date: 2026-11-11. Decided by Flo after the slice 2 review (PR #17). Beads: sz-rs30.1.105.21, sz-rs30.1.105.23. Replaces the rule of [0018](0018-stack-and-back.md) that a page is in the stack once. Replaces the rule of [0018](0018-stack-and-back.md) that the back button shows the name of the page behind. Replaces the named arrow of [0029](0029-search-at-the-top.md). Replaces the clause of [0015](0015-player-page.md) that the mini player jumps back to a page that the stack holds. Replaces the rule of [0029](0029-search-at-the-top.md) that Library has no back arrow.

## Context

The places keep one stack each (ADR 0018). A link to a page that the stack held went back to it. On iOS 27 the system back button draws a chevron in a glass circle, with no name. The name is only in its accessibility label. ADR 0018 says Flo decides again in that case.

The root of Chronology, Search or Settings has no system back button, so ADR 0029 gave it an arrow with a name. A root has no system pop, so that arrow had no swipe from the edge. Flo wants a trip across places to end with Back, and wants as little custom code as possible.

## Decision

- The places are standard iOS tabs, as the Human Interface Guidelines describe them. Each tab keeps its own stack. A tap on a tab switches to it.
- A link to a page pushes it onto the stack of the current place. This holds when the stack has the page already. Back is one step back.
- The system back button shows the chevron only. Its accessibility label names the page behind. Bead sz-rs30.1.105.23 revisits the name at the end of the rebuild.
- A tab root that the listener reached from another tab shows an arrow. A tap on the tab or a link to a place, such as a link that opens Chronology, reaches it.
- The arrow copies the system back button: a toolbar button in the leading position, the chevron `chevron.backward`, no name. Its accessibility label names the target.
- The arrow returns to the previous tab. That tab shows its page as the listener left it. A place opened with no place behind returns to Library.
- Library shows the arrow too when the listener reached it from another tab (Flo, 2026-11-11, sz-rs30.1.105.21). At launch, Library has no place behind it and no arrow.
- A swipe from the left edge of such a root does the same as the arrow. It acts when the swipe ends, without a peel of the page. One `UIScreenEdgePanGestureRecognizer` does it.
- The recogniser is off on every pushed page, where the system swipe works.

## Consequences

- A stack can hold one page twice. A long trip makes a long stack. The long press on Back lists it, and the tip stays.
- No back control names the page behind. The second rule of [0023](0023-no-title-in-the-bar.md), that the back button takes the width of the title, has no effect until the name returns.
- The edge swipe moves no page under the finger. Flo checks on the phone whether this is enough.
- The Chronology opens on the composer of what plays (ADR 0016). This record does not change that.
