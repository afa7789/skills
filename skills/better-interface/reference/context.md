# Frontend context contract

Use context to keep product truth, durable visual rules, and route-specific decisions separate. Do not create artifacts for a narrow refinement when the existing code already answers the task.

## Resolve existing authority

Inspect, in order:

1. The user's request and confirmed decisions.
2. Existing `PRODUCT.md`, `DESIGN.md`, and `.ux-review/surfaces/*.md` files.
3. Product specifications, brand guides, tokens, themes, shared components, and representative rendered screens.
4. Nearby implementation conventions.

Repository evidence is a hypothesis, not permission to replace confirmed content or brand decisions.

## Artifact ownership

- `PRODUCT.md` stores durable product truth: users, jobs, purpose, terminology, constraints, evidence, platform, brand commitments, accessibility needs. Use [`../assets/PRODUCT.template.md`](../assets/PRODUCT.template.md).
- `DESIGN.md` stores the implemented visual system: principles, tokens, type, layout, components, motion, do/don't rules. Use [`../assets/DESIGN.template.md`](../assets/DESIGN.template.md).
- `.ux-review/surfaces/<surface>.md` stores only route- or artifact-specific strategy: visitor mode, task/action, content, chosen direction, states, constraints, open decisions. Use [`../assets/SURFACE.template.md`](../assets/SURFACE.template.md).

Do not duplicate the same fact across files. Product truth outranks surface strategy; durable design rules outrank local styling; an explicit surface exception applies only to that surface.

## Write rules

- For new products or materially new surfaces, resolve material unknowns before implementation. Ask at most three related questions in one round.
- Update an existing authority instead of creating a competing file. Never silently overwrite confirmed decisions.
- Create `PRODUCT.md` from confirmed facts before new visual-world work. Mark open decisions; never invent claims, customers, pricing, or proof.
- Derive `DESIGN.md` from an existing coherent implementation or write it after a new/redesigned surface has been rendered and verified. Do not freeze speculative tokens before reality tests them.
- Write a surface brief only when the route has durable strategy not explained by the global files.
- A narrow refinement may proceed from incumbent code without creating context files; report the missing durable context as an optional follow-up.

## Handoff packet

Pass the resolved context paths, surface, visitor mode, refinement/redesign boundary, immutable constraints, and open decisions to every planner, builder, reviewer, and QA evaluator touching the UI.
