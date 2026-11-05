# Issue tracker: beads (Schaltzentrale ledger)

Issues live as beads in the Schaltzentrale ledger. Use `sz bd` on the Schaltzentrale box. There are no local files and no GitHub Issues.

The ledger is private. Only the owner and authorized agents can read it. This works while the owner is the only contributor. Before the repository takes outside contributors, the project needs a tracker they can reach.

## Codex sessions

- Read Schaltzentrale's `AGENTS.md` “Codex sessions” section first.
- Start with `sz help` and `sz whoami`. Stop unless identity is `codex` via `unix:sz-codex`.
- Use `sz bd` for ledger calls and `--actor codex` on every write.
- Use the launcher's `SZ_SESSION` for the session reference.
- Add `Codex-Session: <SZ_SESSION>` and `Co-Authored-By: Codex <noreply@openai.com>` trailers to every commit.
- Post questions, blockers, PR URLs, checks, and `READY TO SHIP` with the head SHA on the bead.
- The launcher reports worker exits. Never post to its inbox yourself.

## Conventions

- Scope: epic `sz-rs30.1`, label `repo:klassik`. Every new bead is a child of `sz-rs30.1` or of one of its epics.
- Seat `code`. Codex workers use ledger actor `codex`; other coding agents use `code`.
- Pass `--actor` on every write. Set `SZ_SESSION`; `sz` supplies the session reference.
- Issue type: `--type` (epic, task, feature, bug). Never `type:*` labels.
- Hierarchy: `parent-child` links. Ordering: `blocks` links.
- Do not remove `repo:*`, `phase:*`, `blocked:*`, `needs-flo`, `ready-to-ship`, `pain-points`, `idea`, `in-discovery` or `shaped`.
- Run `sz bd prime` after every context clear.

The examples below use actor `code`. Codex workers substitute `codex`.

## When a skill says "publish to the issue tracker"

`sz bd create "<title>" --parent <id> --label repo:klassik --actor code`

## When a skill says "fetch the relevant ticket"

`sz bd show <id> --json`. Read its comments and its parent's comments.

## Comment, claim, close

- Comment: `sz bd comment <id> "<text>" --actor code`
- Claim: `sz bd update <id> --claim --actor code`
- Close: `sz bd close <id> --reason "<change, checks, next step>" --session <ref> --actor code`
- Wait for a date: `sz bd defer <id> --until <YYYY-MM-DD> --actor code`, plus a comment.

## Wayfinding operations

Used by `/wayfinder`. The **map** is an epic bead with one **child** bead per ticket.

- **Map**: an epic under `sz-rs30.1`. Its description holds the Notes, Decisions-so-far and Fog.
- **Child ticket**: a bead with `--parent <map>` and `--type task`. The question is in the description. The first line `Type: <research|prototype|grilling|task>` records the ticket type.
- **Blocking**: a `blocks` link. A ticket is unblocked when every blocker is closed.
- **Frontier**: `sz bd ready --label repo:klassik --json --limit 20`, filtered to the children of the map.
- **Claim**: `--claim` before any work.
- **Resolve**: comment the answer, close with `--reason`, then append a context pointer (gist and bead ID) to the Decisions-so-far of the map.
