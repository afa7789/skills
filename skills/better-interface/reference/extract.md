# Extract a design system

Extract only repeated, stable patterns proven by the implementation.

1. Inventory tokens, themes, primitives, variants, and repeated compositions with exact source locations.
2. Distinguish deliberate variation from drift. Do not normalize a one-off experiment into the system.
3. Propose the smallest token and component surface that removes real duplication.
4. Name tokens by semantic role; preserve the project's notation and platform conventions.
5. Migrate representative call sites first, verify visual parity and API ergonomics, then expand.
6. Remove replaced values and components only after all consumers move.
7. Update `DESIGN.md` from the verified result.

Avoid wrapper components that merely rename native elements, variants with one consumer, and token aliases that encode values without meaning.
