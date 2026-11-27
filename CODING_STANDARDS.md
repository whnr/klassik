# Coding standards

The review reads this file. The implementer need not read it first.

## Layout citations

- A `Klassik/Layout.swift` citation names the specimen rule that the value comes from.
- Another rule with an equal value is not a source.
- When a rule leaves the specimen, a view that still uses its constant gets a literal. The literal and its reason go into `scripts/layout_literals.txt`.

Why: `scripts/layout_tokens.py --check` passes on a wrong citation that has an equal value. Only review catches it.
