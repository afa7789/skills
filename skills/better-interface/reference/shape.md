# Shape a frontend surface

Shape decisions that materially affect the interface before writing code. Return a compact surface contract readable in one pass, not a component inventory; omit settled facts and examples.

1. Read the frontend context and inspect one representative source of incumbent visual truth.
2. State the primary user, job, success condition, visitor mode, scope, and constraints.
3. Map the shortest complete path through the surface, including loading, empty, error, permission, and success states that the product actually needs.
4. Establish information hierarchy and interaction order before choosing decoration.
5. Reuse existing tokens and components unless a confirmed requirement makes them insufficient.
6. For an open design problem, present at most three materially different directions with one benefit, one risk, and the recommended choice. Avoid near-duplicate variants.
7. Record the selected direction in the surface brief. Stop without implementation when the request is planning-only.

The output must name what remains unchanged, what is intentionally new, and how success will be verified at narrow and wide viewports. Prefer one table for paths/states and one short list for open decisions over section-by-section prose.
