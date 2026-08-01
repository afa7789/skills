# Quick visual gate

Run this after every user-visible UI change. It is a bounded finish check, not a full audit.

1. Identify the changed surface and its primary path. Use existing preview, test, or dev-server tooling.
2. Make the render deterministic where practical: fixed data and clock, no live network variance, animations disabled for screenshots, fonts awaited.
3. Capture or inspect one narrow viewport and one wide viewport. Include the changed non-default state when the task concerns loading, empty, error, disabled, permission, or interaction behavior.
4. Run the project's existing lint, type, and focused tests. For web source, run `node <frontend-audit>/scripts/detect-ui.mjs --json <changed-targets>` when available.
5. Inspect accessibility, hierarchy, overflow, copy, type, color, motion, console errors, and design-system consistency. Record P0–P3 findings.
6. Fix material findings in one batch. Re-run the same checks and captures once.
7. Stop after the confirmation pass. Report remaining findings honestly instead of opening another polish loop.

If the interface cannot be rendered, report that limitation and verify from source without making visual claims. Escalate to `frontend-audit` when the change crosses several screens, roles, states, platforms, or design-system primitives.
