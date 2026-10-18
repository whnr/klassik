# 0003. Classical filter: rules joined by OR, conditions joined by AND

Date: 2026-10-17. Decided by Flo after testing 0.3.0. Bead: sz-rs30.1.2.

## Context

A library holds classical and other music. Genre tags differ between sources: Presto writes "Classical > Orchestral". Composer and work tags also occur on pop albums. So one condition alone lets wrong albums in.

## Decision

- The filter is a list of rules. A track matches if one rule matches.
- A rule is a list of conditions. A rule matches if all its conditions match.
- Conditions: genre contains, genre does not contain, has a work, has a movement, has a composer. Text compares without case.
- Default rules: genre contains "Classical"; genre contains "Klassik"; has a work AND has a movement.
- An album is classical if more than half of its tracks match. Then all its tracks count.
- An empty rule or an empty text matches nothing, so a half-typed rule does not let the whole library in.

## Consequences

- The rules stay on the device.
- With the default rules, music.whnr.de has 48 classical albums and 1,062 classical tracks.
