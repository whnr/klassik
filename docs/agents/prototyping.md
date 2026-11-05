# Prototyping

How to build a UX prototype that the tester tests on a phone. The search ticket (sz-rs30.1.74.5) used this flow.

## What the owner judges

- The owner judges the flow: the steps, the states, and what each tap does. Polish comes second.
- Still make it look native. A clean iOS 26 look lets the owner judge the flow without distraction. The search prototypes had the right level: system colours, light and dark mode, inset lists, a glass search field at the bottom. Do not spend more time on looks than that.
- Looks get their own decisions in the design system map (sz-rs30.1.83).

## Build

- Use a worker branch and worktree. Use one folder for each question: `prototypes/<name>/index.html`.
- One self-contained HTML file. Vanilla JavaScript, no dependencies, no network.
- Generated data from a fixed seed. Use the owner's library tags only when the owner requests them. Never audio, cover art or a credential.
- Build at least three variants that differ in structure, not in colour. Switch with `?variant=` and a pill at the top of the screen. The bottom belongs to the iOS search field. Add a reset link.
- Each variant shows its state after every tap: counts, the current selection, and what a tap will do.
- Only the content scrolls, never the page. Move the bottom bar with `visualViewport`. Otherwise the layout jumps when the keyboard opens.
- A round of feedback gets a new folder, so that the owner can compare it with the round before.
- To build more variants, use subagents in their own worktrees, one at a time. Base each one on the previous agent's branch, so that the merges stay clean.

## Check before the handover

- Open the page with Playwright at 393×852, `deviceScaleFactor: 3`, `isMobile` and `hasTouch`. A check at scale 1 with a mouse hides canvas size faults and taps that land on a control that opens under the finger.
- Drive every gesture with touch: taps with `touchscreen.tap`, drags and pinches with CDP `Input.dispatchTouchEvent`.
- Drive the main flow in each variant. Confirm that the counts agree between the variants.
- Look at a screenshot of each variant. Fix what overlaps or hides behind the pill.

## Hand over

- Default: copy the file to `whnr:/var/www/virtual/whnr/html/klassik/<name>-<8 random hex>/index.html`. The owner opens `https://whnr.uber.space/klassik/<name>-<hex>/`. The random suffix keeps it unlisted: link it nowhere except to the owner. Touch nothing else in that web root. Delete the folder after the owner's verdict.
- At home, if the owner asks: in `prototypes/`, run `python3 -m http.server 8765 --bind 0.0.0.0`. The owner opens `http://<laptop LAN address>:8765/<name>/` on a phone.
- Commit each round on the worker branch and open a PR. Follow the review rules in `AGENTS.md`.

## Record

- Write the owner's verdict on each variant into the ticket, in a few words each.
- On resolution: write the decision, the data that the view needs, and the bugs that its tracer fixes first. Put new terms into `CONTEXT.md`.
- Put open details into the map's "Not yet specified" section.
