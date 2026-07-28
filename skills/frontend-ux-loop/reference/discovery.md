# Screen discovery — every pattern, every platform

The goal of Phase 2 is a complete, evidence-backed list of **screens × visual
states**, produced *before* any harness is configured. `scripts/discover-screens.sh`
greps for the patterns below; this document tells you how to read the results,
where the patterns lie, and what grep can never see.

**Rule:** grep produces *candidates*. You confirm each one by reading the file at
the reported line. A candidate you did not read does not go in the catalog with
`confidence: high`.

---

## 1. Explicit routers (highest confidence)

The route table is the ground truth when it exists. Find it, read it whole.

| Framework | Where | Grep for |
|---|---|---|
| React Router | `src/router*`, `App.tsx` | `createBrowserRouter`, `<Route `, `path:`, `RouterProvider`, `useRoutes` |
| Vue Router | `src/router/index.*` | `createRouter`, `routes:`, `path:`, `component:`, `children:` |
| Angular Router | `*-routing.module.ts`, `app.routes.ts` | `RouterModule.forRoot`, `Routes = [`, `path:`, `loadChildren` |
| TanStack Router | `src/routes/**`, `routeTree.gen.ts` | `createRoute`, `createFileRoute`, `getParentRoute` |
| Svelte (SPA) | `src/routes*`, `svelte-routing`/`page.js` | `<Route path`, `router.on(`, `page(` |
| Solid Router | `src/App.tsx` | `<Route path`, `createRouter` |

Read the file for: nested routes (children compose full paths), lazy imports
(the component name is in the dynamic `import()`), route guards
(`beforeEnter`, `canActivate`, `loader`, `meta: { requiresAuth }`), redirects,
and `404`/catch-all routes — **the error and not-found screens are screens**.

---

## 2. File-based routing (route = path on disk)

Derive the URL from the file path; the mapping rules differ per framework.

| Framework | Route files | Notes |
|---|---|---|
| Next.js App Router | `app/**/page.tsx` | plus `layout`, `loading`, `error`, `not-found`, `template`; route groups `(group)` do not appear in the URL; `[id]`, `[...slug]`, `[[...opt]]` are params |
| Next.js Pages Router | `pages/**/*.tsx` | `_app`, `_document`, `api/**` are **not** screens; `404.tsx`/`500.tsx` are |
| Nuxt | `pages/**/*.vue` | `[id].vue`, `[...slug].vue`; `error.vue` is a screen |
| SvelteKit | `src/routes/**/+page.svelte` | plus `+layout`, `+error`; `[id]`, `[...rest]`; `(group)` invisible in URL; `+server.ts` is not a screen |
| Astro | `src/pages/**/*.astro` | `[id].astro`, `[...slug].astro` |
| Remix | `app/routes/**` | flat or nested convention; `$param`, `_index` |
| Expo Router | `app/**/*.tsx` | same conventions as Next App Router, plus `(tabs)`, `_layout` |

`loading.tsx` / `+page` streaming boundaries / `error.tsx` are **explicit proof
that loading and error states exist** — record them as states, with the file as
evidence.

---

## 3. Mobile navigation

| Stack | Grep for | Notes |
|---|---|---|
| React Navigation | `createNativeStackNavigator`, `createBottomTabNavigator`, `createDrawerNavigator`, `<Screen name=`, `navigation.navigate(` | every `<Stack.Screen name="X" component={Y}>` is a screen; `navigate('X')` calls reveal reachability |
| Expo Router | `app/**` file tree, `router.push(`, `<Link href=` | see §2 |
| Flutter | `GoRoute(`, `AutoRoute(`, `MaterialApp(routes:`, `onGenerateRoute`, `Navigator.pushNamed(`, `Navigator.push(` | also grep `class .* extends StatelessWidget` in `lib/**/screens|pages|views` |
| Android Compose | `composable(route =`, `NavHost(`, `navController.navigate(` | plus `<activity>` entries in `AndroidManifest.xml` and `Fragment` classes |
| Android Views | `AndroidManifest.xml`, `res/navigation/*.xml` | `<fragment android:name=`, `<activity` |
| iOS SwiftUI | `NavigationStack`, `NavigationLink(`, `.sheet(`, `.fullScreenCover(`, `navigationDestination(for:` | screen types are usually `struct XView: View` |
| iOS UIKit | `*ViewController.swift`, `*.storyboard` | `pushViewController`, `present(`, storyboard scene identifiers |

Modals, sheets, bottom sheets, dialogs and full-screen covers are screens for
audit purposes — they have their own layout, states and a11y semantics.

---

## 4. Naming conventions (medium confidence — only after routers)

Use this to catch screens the router grep missed (dynamically registered,
feature-flagged, or reachable only via deep link):

```
**/*Page.{tsx,jsx,vue,svelte,ts}    **/*Screen.*    **/*View.*
**/pages/**    **/screens/**    **/views/**    **/routes/**
lib/**/{screens,pages,views}/**.dart
**/*Activity.kt    **/*Fragment.kt    **/*ViewController.swift
```

A component matching these patterns that appears in **no** route table is a
finding in itself: either an unreachable screen (dead code) or a discovery gap.
Put it in `UNRESOLVED_SCREENS.md` — never drop it.

---

## 5. Existing catalogs and previews (free, high-quality inventory)

If any of these exist, the project already told you what its screens and states
are. Read them first — and reuse them in Phase 4 instead of building a parallel
harness.

| Source | Grep for |
|---|---|
| Storybook | `*.stories.@(ts|tsx|js|jsx|svelte|vue|mdx)`, `.storybook/main.*`, `export const <Name>: Story` |
| Storybook index | built Storybook `index.json` / running dev server `/index.json` — the authoritative story list |
| Widgetbook | `*.widgetbook.dart`, `@widgetbook.UseCase`, `widgetbook/**` |
| Compose | `@Preview`, `@PreviewParameter`, `@PreviewScreenSizes` |
| SwiftUI | `#Preview`, `PreviewProvider`, `.previewDevice(` |
| Histoire (Vue) | `*.story.vue` |
| Ladle / Cosmos | `*.stories.*`, `*.fixture.*` |

Story/use-case names usually encode the state (`Loading`, `Empty`, `WithError`,
`Disabled`) — harvest them as the state list.

---

## 6. Tests as a route oracle

Tests visit real screens, with real params and real auth. This is often the only
place a concrete id, token or role appears.

```
Playwright/Cypress   page.goto('...'), cy.visit('...'), await page.getByRole
Maestro              *.yaml with `- launchApp`, `- tapOn`, `- assertVisible`
Detox                device.launchApp, element(by.id(
Flutter              integration_test/**, tester.pumpWidget, find.byType
Espresso/XCUITest    onView(withId(, app.buttons["..."]
```

Harvest from tests: reachable routes, **valid sample parameter values**, login
credentials/fixtures, and the flows worth capturing end-to-end.

---

## 7. Visual states — infer from the code, do not invent

For each screen, open the component and look for real branches. Only states with
code behind them go in the catalog; anything else goes in
`UNRESOLVED_SCREENS.md` as `suggested`.

| State | Evidence to grep inside the screen/component |
|---|---|
| `loading` | `isLoading`, `isPending`, `loading`, `<Suspense`, `Skeleton`, `CircularProgress`, `AsyncValue.loading`, `.loading` |
| `empty` | `length === 0`, `isEmpty`, `EmptyState`, `no results`, `\.isEmpty` |
| `error` | `isError`, `catch`, `ErrorBoundary`, `error.vue`, `+error.svelte`, `AsyncValue.error`, `try/catch` around the fetch |
| `success` / `default` | the normal render path with fixture data |
| `disabled` / `readonly` | `disabled=`, `readonly`, `enabled: false` |
| `permission-denied` | role/guard checks, `403`, `canActivate`, `if (!user.isAdmin)` |
| `offline` | `navigator.onLine`, `ConnectivityResult`, `NetworkInfo`, offline banners |
| `validation-error` | form schema (`zod`, `yup`, `FormState.errors`, `TextFormField.validator`) |
| `dark mode` | `prefers-color-scheme`, `useColorScheme`, `ThemeMode`, `isSystemInDarkTheme()` |
| `long content` / `i18n` | any user text — always capture one long-string variant |

Two states are almost always missing from projects and almost always broken:
**empty** and **error**. Capture them even when the project has no fixture for
them — the absence *is* the finding.

---

## 8. Parameters, auth and guards

A route with a param cannot be captured without a value. For each `:id`-style
segment, resolve a value in this order and record which one you used:

1. a value used in an existing test or fixture,
2. a value from the seeded/mock dataset,
3. a synthetic value the mock layer is configured to answer for.

For guarded routes, record the required role and how the harness satisfies it
(mock session, storage state, test user). A route you cannot authenticate into
is an `UNRESOLVED_SCREENS.md` entry, not a skipped line.

---

## 9. What grep cannot see — always check by hand

- Routes built by string concatenation or from config/CMS data at runtime.
- Screens registered by a plugin system or dependency injection.
- Feature-flagged screens (grep the flag names too: `useFlag(`, `isEnabled(`).
- Deep-link-only and push-notification-only destinations (`AndroidManifest`
  intent filters, `Associated Domains`, `scheme://`, universal links).
- Native OS surfaces: permission dialogs, share sheets, widgets, notifications,
  App Clips, watch/TV targets.
- Micro-frontend or module-federation remotes.
- Screens rendered only after a specific data shape arrives from the backend.
- WebViews inside a native app (they are a whole second frontend).

Every item above that applies goes into `UNRESOLVED_SCREENS.md` with the reason.
An honest gap list is what makes the inventory trustworthy.
