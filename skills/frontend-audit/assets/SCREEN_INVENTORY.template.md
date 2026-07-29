# Screen Inventory

**App:** <app / path>
**Stack:** <framework · router · package manager>
**Design standard:** <material-3 | hig | fluent | custom:tokens.ts>
**Discovered:** <date> · **Method:** <routers | file-based routes | navigator | previews | tests>

## Coverage

| | Count |
|---|---|
| Screens found | N |
| Screens with `confidence: high` | N |
| Total states | N |
| Screens unresolved (see `UNRESOLVED_SCREENS.md`) | N |
| Shots planned (screens × states × viewports × themes) | N |

## Screens

| Screen id | Route | Component | Role | States found | Conf. | Evidence |
|---|---|---|---|---|---|---|
| login | `/login` | LoginPage | guest | default, validation-error, loading, error | high | `src/router/index.ts:24` |
| dashboard | `/dashboard` | DashboardPage | user | default, loading, empty, error | high | `src/router/index.ts:82` |
| profile-details | `/profiles/:id` | ProfileDetailsPage | user | default, loading, error, permission-denied | high | `src/router/index.ts:96` |
| admin-users | `/admin/users` | AdminUsersPage | admin | default, empty, loading, error | medium | `src/router/admin.ts:14` |
| not-found | catch-all | NotFoundPage | guest | default | high | `src/router/index.ts:140` |

## State evidence

Only states with code behind them are captured. `suggested` states have no
implementation and their absence is itself a finding.

| Screen | State | Evidence in code | Status |
|---|---|---|---|
| dashboard | loading | `DashboardPage.tsx:22` (`isPending` → `<Skeleton/>`) | implemented |
| dashboard | empty | `DashboardPage.tsx:41` (`items.length === 0`) | implemented |
| dashboard | error | `DashboardPage.tsx:57` (`isError` → `<ErrorCard/>`) | implemented |
| dashboard | offline | — | **suggested — not implemented** |
| admin-users | empty | — | **suggested — not implemented** |

## Parameters and auth

| Screen | Param | Value used | Source of the value |
|---|---|---|---|
| profile-details | `id` | `usr_000000000001` | `e2e/fixtures/users.ts:12` |

| Role | How the harness authenticates |
|---|---|
| user | saved `storageState` from `.ux-review/auth-user.json` |
| admin | saved `storageState` from `.ux-review/auth-admin.json` |

## Reductions and masks (declared, not silent)

| Screen | Reduction / mask | Reason |
|---|---|---|
| admin-users | tablet + desktop only | product decision: admin is desktop-only |
| dashboard | mask `[data-testid="live-chart"]` | animated, polls live data |
| all | font-scale 200% only on forms and text-heavy screens | matrix size |

## Not screens (checked and excluded)

| Path | Why excluded |
|---|---|
| `pages/api/**` | API routes, no UI |
| `src/components/**` | components, not screens — audited indirectly |
| `LegacyOnboarding.tsx` | in no route table; suspected dead code → `UNRESOLVED_SCREENS.md` |
