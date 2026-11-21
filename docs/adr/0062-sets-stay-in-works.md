# 0062. Sets stay in Works

Date: 2026-11-19. Decided by Flo in the 0.15.0 feedback. Bead: sz-kaqj.6.
Replaces the set placement rule of [0050](0050-partial-works-apart.md).

## Context

Klassik knows whether a work has a complete recording. It cannot determine whether a set is complete.

## Decision

- A set appears once, under Works, with all its matching works.
- Separate Partial Works applies only to work rows outside sets.
- Genre chips keep their current filtering rule.

## Consequences

A set can hold complete and partial works together.
