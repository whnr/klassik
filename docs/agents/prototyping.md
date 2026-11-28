# Prototyping

How to build a UX prototype that the tester tests on a phone.

## What the owner judges

- The owner judges the flow: the steps, the states, and what each tap does.
- The specimen is the look. A prototype links `design/tokens.css` and the specimen CSS, and copies specimen components: titles with the fermata, section headings, the search field row. A prototype states no design rule of its own.

## Build

- One folder for each question, one self-contained HTML file. Vanilla JavaScript, no dependencies, no network.
- Generated data from a fixed seed, unless the bead names other data. Never audio or a credential.
- Build at least three variants that differ in structure, not in colour. Switch with `?variant=` and a pill at the top of the screen. Add a reset link.
- Each variant shows its state after every tap: counts, the current selection, and what a tap will do.
- Only the content scrolls, never the page. Move a bottom bar with `visualViewport`, so that the layout stays still when the keyboard opens.
- A round of feedback gets a new folder, so that the owner can compare it with the round before.
- To build more variants, use subagents in their own worktrees, one at a time.

## Check before the handover

- Open the page with Playwright at 393×852, `deviceScaleFactor: 3`, `isMobile` and `hasTouch`. A check at scale 1 with a mouse hides canvas size faults and taps that land on a control that opens under the finger.
- Drive every gesture with touch: taps with `touchscreen.tap`, drags and pinches with CDP `Input.dispatchTouchEvent`.
- Drive the main flow in each variant. Confirm that the counts agree between the variants.
- View every screenshot: each variant, in light and dark, at the top and scrolled. Name each one in the report. Fix what overlaps, clips or hides behind the pill.

## Hand over

- The bead names where the prototype goes and which data it may use. Without that, serve it from the folder with `python3 -m http.server 8765 --bind 0.0.0.0`. The owner opens `http://<laptop LAN address>:8765/<name>/` on a phone.

## Record

- Write the owner's verdict on each variant into the bead, in a few words each.
- On resolution: write the decision, the data that the view needs, and the bugs that its tracer fixes first. Put new terms into `CONTEXT.md`. The decided look goes into the specimen, with its comments.
