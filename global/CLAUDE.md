# Global Agent Rules

## Principles
1. Think before coding: don't assume; surface tradeoffs and confusion.
2. Ponytail: code that doesn't need to exist isn't written. DRY on the 2nd duplication. Nothing speculative.
3. Surgical changes: touch only what the task needs; clean up only your own mess.
4. SoC and SOLID: transport, business, domain and data stay separate.
5. Binary proof per task: name the check that exits 0 when done. Default to build, lint and direct smoke probes;
   avoid writing tests unless the project uses them or the user asks. No coverage % gate, no mirrored test folders.
6. Gates over prose: whatever can be checked becomes a linter rule, check or hook.
7. Evidence before claims: show the command and its output.
8. A repeated mistake becomes a rule line or a check; capture corrections in `tasks/lessons.md`.
9. Batch ready tasks into one agent session when efficient; split across parallel agents only for independent work (one owner per file).

## Workflow
- Plan mode when a change alters architecture or spans many files; otherwise act. Re-plan when reality diverges.
- Bug report → fix it autonomously; don't ask for repro steps when the report is clear.
- Subagents for research and independent parallel work, one focused task each.
- Root cause, not symptom. No temporary patches.

## Done
- Never mark done without the task's check passing and the linter (complexity rule on) at zero warnings.
- If `.claude/PLAN.md` has the matching TODO, mark it done with date and note.
