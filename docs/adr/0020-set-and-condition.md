# 0020. Set means works; a search row is a condition

Date: 2026-11-04. Decided by Flo. Bead: sz-rs30.1.74. Replaces the naming note of [0017](0017-composer-and-performer-pages.md).

## Context

The code calls works that share a GROUPING tag a set (`WorkSet`). The search decision (sz-rs30.1.74.5) also called one row of a search a set. ADR 0017 left the name for grouped works open and gave "set" to Search. One word must have one meaning.

## Decision

- A set is a group of works that share a GROUPING tag, such as Etudes, Op. 10. Musicians use the word in this meaning.
- One row of a search is a condition. Its search terms join with "or", and the conditions join with "and".

## Consequences

- CONTEXT.md holds both terms.
- Search code and its tests use "condition" for a row.
