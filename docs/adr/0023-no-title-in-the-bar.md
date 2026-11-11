# 0023. No title in the navigation bar

Date: 2026-11-07. Decided by Flo after the first specimen round. Bead: sz-rs30.1.83.10. The second rule has no effect while [0038](0038-standard-tabs-and-the-cross-tab-back.md) hides the name on the back button.

## Context

iOS shows a small title in the navigation bar when the large title of a page scrolls away. The bar then holds the back button and the title side by side. Klassik's titles and the names on its back buttons are long, such as "Symphony No. 5 in C minor, Op. 67". In the specimen both were cut to fragments such as "Symphon…". ADR 0018 makes the name of the page behind the main signal of the stack.

## Decision

- The navigation bar shows no title. The large title stays in the page and scrolls with it.
- The back button takes the width that the title had, so the name of the page behind shows in full where it fits.

## Consequences

- The SwiftUI tracer finds the way to hide the bar title on iOS 26 and checks that VoiceOver still reads the page title.
- When the large title has scrolled away, the page names itself only through its content.
