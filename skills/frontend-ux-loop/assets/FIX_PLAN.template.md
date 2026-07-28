# UX Fix Plan

**Source:** `UX_REVIEW.md` · **Date:** <date> · **Mode:** <plan | fix>
**Ordering:** severity first, then findings-closed ÷ effort. Work top to bottom.

## Summary

| Group | Severity | Findings closed | Effort | Needs design decision |
|---|---|---|---|---|
| F1 | P0 | 12 | S | no |
| F2 | P0 | 3 | M | no |
| F3 | P1 | 8 | S | yes |
| F4 | P2 | 21 | M | no |

**Recommended pass:** F1 + F2 (all P0) — <total effort>. Stop there and re-capture
before touching P1/P2, so the before/after signal stays readable.

---

## F1 · Replace hard-coded greys with theme roles
**Severity:** P0 · **Effort:** S · **Closes:** 12 findings across 7 screens
**Findings:** `dashboard/default`, `login/default`, `admin-users/empty`, …

**Root cause:** `#8A8A8A`, `#9E9E9E` and `#B0B0B0` are hard-coded in 9 components
instead of using `on-surface-variant`. All three fail 4.5:1 on `surface`.

**Change:**
| File:line | From | To |
|---|---|---|
| `src/components/MetricCard.tsx:34` | `color: '#8A8A8A'` | `color: theme.colors.onSurfaceVariant` |
| `src/components/ListItem.tsx:51` | `color: '#9E9E9E'` | `color: theme.colors.onSurfaceVariant` |

**Verification:** re-run axe on the 7 screens — `color-contrast` violations must
drop to 0; measured ratio ≥ 4.5:1 in both light and dark themes.
**Risk:** low — visual-only. Dark theme must be re-checked, the roles differ there.

---

## F2 · <next group>
**Severity:** · **Effort:** · **Closes:**
**Root cause:**
**Change:**
**Verification:**
**Risk:**

---

## Needs a design/product decision (do not implement unilaterally)

| # | Finding | The decision required | Options | Recommendation |
|---|---|---|---|---|
| 1 | P1 · admin-users has no empty state | What should an empty user list say and offer? | (a) "No users yet" + Invite CTA (b) hide the table (c) seed help content | (a) — matches the pattern already used on `dashboard/empty` |

---

## Explicitly out of scope for this pass

| Item | Reason |
|---|---|
| P3 polish (N findings) | keeps the before/after signal clean; schedule separately |
| Redesign of the dashboard layout | product-level change, not a defect fix |

---

## Execution checklist (fix mode)

- [ ] Branch created: `ux/<scope>-pass`
- [ ] Fix groups applied in order, one commit per group
- [ ] `rtk lint` clean
- [ ] Type check clean
- [ ] Test suite passing (or failures listed and explained)
- [ ] Re-captured into `screenshots/after/` with the **identical** harness, seed,
      clock, devices and viewports
- [ ] Determinism re-verified: two consecutive captures produce identical images
- [ ] Phase 6 audits re-run; numbers compared, not just pixels
- [ ] `comparisons/` diffs generated and every unexpected diff investigated
- [ ] `UX_REVIEW.md` § Results appended, including regressions
- [ ] Nothing committed to the default branch; no push without the user asking
