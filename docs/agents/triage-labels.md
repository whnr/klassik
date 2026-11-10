# Triage Labels

The skills speak in terms of five triage roles. This file maps each role to a label in the ledger.

| Label in upstream skills | Label in the ledger  | Meaning                                       |
| -------------------------- | -------------------- | --------------------------------------------- |
| `needs-triage`             | `needs-triage` (new) | Maintainer needs to evaluate this bead        |
| `needs-info`               | `needs-info` (new)   | Waiting on the reporter for information       |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent       |
| `ready-for-human`          | `needs-flo`          | Needs the owner's decision or work           |
| `wontfix`                  | `wont-do`            | Will not be actioned. Close with `--reason`.  |

`needs-triage` and `needs-info` do not exist in the ledger yet. Add each one to a bead when first used.
