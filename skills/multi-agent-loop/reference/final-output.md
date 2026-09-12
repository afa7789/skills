# Final Output

Use once the Hard Stop Condition holds — every bullet verified this turn.

```markdown
## Completed
- [list of completed features]

## Remaining Gaps
TYPE A: none
TYPE B: none
TYPE C:
  - [ ] <human-required item>

## Review Summary
- Rounds: <n> | fixed: <n> | rejected as false positives: <n> | fresh-eyes pass: PASS

## Possible Improvements (no failure mode — never blocking)
- <pulled from .claude/IMPROVEMENTS.md>
- <each item: what was chosen, what would be ideal, rough effort to migrate>

<promise>HARD_STOP</promise>
```

Use `<promise>BLOCKED_TYPE_C</promise>` instead when the loop stops on TYPE C only.
