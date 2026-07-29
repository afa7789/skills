# Web adapter — React / Vue / Svelte / Angular / Next / Nuxt / SvelteKit / Astro

Two mechanisms, two jobs. They are **complementary, not alternatives**:

| | Storybook | Playwright on the real app |
|---|---|---|
| Best at | isolating **states** (loading / empty / error / disabled) deterministically | **truth** — real router, real layout, real auth, real scroll, real data flow |
| Gives you | one URL per screen×state, no backend needed | end-to-end flows, cross-browser, viewport emulation |
| Weak at | drifting from the real app; needs stories written | hard to force an error/empty state without mocking |

Default: **Storybook for the state matrix, Playwright as the capture engine for
both Storybook and the real routes.** Storybook's own test tooling drives a real
browser through Playwright underneath, so this is not two competing stacks — it
is one browser engine with two page sources.

When the same screen looks different in Storybook and on the real route, that
disagreement is a finding (the story lies, or the page has unmodeled state).

---

## 1. Storybook — the state catalog

### Setup (only if the project has none)

```bash
npx storybook@latest init        # auto-detects React/Vue/Svelte/Angular/web components
pnpm storybook                   # dev server, usually :6006
pnpm build-storybook -o .ux-review/storybook-static
```

Ask before installing. If Storybook exists, extend it and match its conventions
(CSF version, decorators, existing mock setup) instead of introducing a second style.

### One story per screen × state

Stories are not only for buttons — a full page with providers, layout and
connected state is a legitimate story. Title them so the catalog id is derivable:

```
Screens/Dashboard/Default
Screens/Dashboard/Loading
Screens/Dashboard/Empty
Screens/Dashboard/Error
```

```ts
// DashboardPage.stories.ts  (CSF3)
import type { Meta, StoryObj } from '@storybook/react'
import { DashboardPage } from './DashboardPage'

const meta: Meta<typeof DashboardPage> = {
  title: 'Screens/Dashboard',
  component: DashboardPage,
  parameters: { layout: 'fullscreen' },   // pages need the whole canvas
}
export default meta
type Story = StoryObj<typeof DashboardPage>

export const Default: Story = { parameters: { msw: { handlers: [okHandler] } } }
export const Loading: Story = { parameters: { msw: { handlers: [neverResolves] } } }
export const Empty:   Story = { parameters: { msw: { handlers: [emptyHandler] } } }
export const Error:   Story = { parameters: { msw: { handlers: [errorHandler] } } }
```

Whatever the screen needs to render must be provided by a **decorator**: router
context, i18n, theme, query client, store. Put shared ones in
`.storybook/preview.ts` so every screen story gets them for free.

### Mocking the network — MSW

```bash
pnpm add -D msw msw-storybook-addon
npx msw init public/            # service worker
```

```ts
// .storybook/preview.ts
import { initialize, mswLoader } from 'msw-storybook-addon'
initialize({ onUnhandledRequest: 'warn' })   // 'error' once fixtures are complete
export default { loaders: [mswLoader] }
```

Handlers per state — this is what makes `loading`/`error` capturable at all:

```ts
import { http, HttpResponse, delay } from 'msw'
export const okHandler      = http.get('/api/items', () => HttpResponse.json(FIXTURE))
export const emptyHandler   = http.get('/api/items', () => HttpResponse.json([]))
export const errorHandler   = http.get('/api/items', () => new HttpResponse(null, { status: 500 }))
export const neverResolves  = http.get('/api/items', async () => { await delay('infinite') })
```

For screens that call modules instead of HTTP, mock the **module** (Storybook
module mocking / framework-level DI) rather than reaching into the component.

### Enumerating stories for capture

The built Storybook exposes the authoritative story list at `index.json`
(the dev server serves `/index.json` too). Each entry gives an `id`, `title`,
`name` and `type: 'story' | 'docs'`. Render any story standalone at:

```
http://localhost:6006/iframe.html?id=<storyId>&viewMode=story
                                  &globals=theme:dark          # if the project uses a theme global
```

Filter to `type === 'story'` and to your `Screens/*` prefix so docs pages and
component stories do not pollute the screen catalog.

### Free audits from Storybook

- `@storybook/addon-a11y` — axe-core against each story (per-story config via
  `parameters.a11y`).
- Interaction tests (`play` functions with `userEvent`) — reach a state that
  requires clicks (open menu, invalid form, expanded row) and screenshot **after**
  the play function settles.
- Visual testing add-ons/services exist, but the local Playwright comparison
  below is enough for a before/after pass and needs no external account.

---

## 2. Playwright — the capture engine

```bash
pnpm add -D @playwright/test && npx playwright install --with-deps chromium
```

### Config for deterministic, multi-viewport shots

```ts
// playwright.ux.config.ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: '.ux-review/harness',
  snapshotPathTemplate: '.ux-review/screenshots/{arg}{ext}',
  use: {
    locale: 'en-US',
    timezoneId: 'UTC',
    colorScheme: 'light',
    reducedMotion: 'reduce',
    deviceScaleFactor: 2,
  },
  projects: [
    { name: 'mobile',  use: { ...devices['iPhone 13'] } },
    { name: 'tablet',  use: { viewport: { width: 834,  height: 1112 } } },
    { name: 'desktop', use: { viewport: { width: 1440, height: 1000 } } },
  ],
})
```

### Capture loop (Storybook source)

```ts
import { test, expect } from '@playwright/test'
import index from '../storybook-static/index.json' assert { type: 'json' }

const stories = Object.values(index.entries as Record<string, any>)
  .filter(e => e.type === 'story' && e.title.startsWith('Screens/'))

for (const s of stories) {
  test(`shot ${s.id}`, async ({ page }, info) => {
    await page.goto(`/iframe.html?id=${s.id}&viewMode=story`)
    await page.locator('#storybook-root').waitFor({ state: 'visible' })
    await page.evaluate(() => document.fonts.ready)
    await page.addStyleTag({ content: `*,*::before,*::after{
      animation:none!important;transition:none!important;caret-color:transparent!important}` })
    await page.screenshot({
      path: `.ux-review/screenshots/before/${slug(s.title)}__${slug(s.name)}__${info.project.name}.png`,
      fullPage: true, animations: 'disabled', caret: 'hide',
    })
  })
}
```

### Capture loop (real routes)

Use this for auth-gated screens, real navigation and real layout. Reuse a saved
`storageState` for the logged-in role so you do not re-login per screen:

```ts
// one-time: log in, then context.storageState({ path: '.ux-review/auth-user.json' })
test.use({ storageState: '.ux-review/auth-user.json' })

for (const screen of catalog.screens) {
  test(`route ${screen.id}`, async ({ page }, info) => {
    await page.clock.setFixedTime(new Date('2025-01-01T12:00:00Z'))  // freeze the clock
    await page.route('**/api/**', route => route.fulfill({ json: fixtureFor(route) }))
    await page.goto(resolveRoute(screen))          // substitutes :params from the catalog
    await page.waitForLoadState('networkidle')
    await page.screenshot({ path: shotPath(screen, info), fullPage: true, animations: 'disabled' })
  })
}
```

### Dark mode and font scaling

```ts
await page.emulateMedia({ colorScheme: 'dark' })                    // dark variant
await page.emulateMedia({ forcedColors: 'active' })                 // Windows high contrast
// text scaling: set the root font-size, or zoom the viewport
await page.addStyleTag({ content: 'html{font-size:200%}' })         // WCAG 1.4.4 / 1.4.10 check
```

### Before/after comparison without any service

```ts
await expect(page).toHaveScreenshot(`${screen.id}__${state}.png`, {
  maxDiffPixelRatio: 0.01, animations: 'disabled', caret: 'hide',
})
```

Run once on the baseline (`--update-snapshots`) to establish `before/`, then again
after the fixes; Playwright writes the diff image itself. Copy the diffs into
`.ux-review/comparisons/`.

### a11y audit in the same pass

```ts
import AxeBuilder from '@axe-core/playwright'
const results = await new AxeBuilder({ page })
  .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
  .analyze()
// write results.violations to .ux-review/audits/<screen>__<state>.axe.json
```

---

## 3. Framework specifics

| Framework | Watch out for |
|---|---|
| **React** | provider soup — put QueryClient/Router/Theme/i18n in `.storybook/preview.ts` decorators; `Suspense` boundaries define the loading state |
| **Vue / Nuxt** | Pinia needs `createTestingPinia()` per story; `<Suspense>` and `useAsyncData` drive loading; Nuxt needs its Storybook module or capture real routes |
| **Svelte / SvelteKit** | SvelteKit `load` functions do not run in Storybook — pass the `data` prop directly per state; `+error.svelte` and `+loading` boundaries are your state evidence |
| **Angular** | stories need `moduleMetadata`/`applicationConfig`; mock HTTP with `HttpTestingController` or MSW; `RouterTestingModule` for router-dependent screens |
| **Next.js App Router** | server components do not render in a browser-only harness — capture those screens from the real dev server instead; `loading.tsx`/`error.tsx` are separate shots |
| **Astro** | mostly static output — capture the built site with Playwright; islands need hydration waits |

---

## 4. Determinism checklist (web)

- [ ] `msw` (or `page.route`) intercepts **everything**; `onUnhandledRequest: 'error'` once fixtures are complete
- [ ] `page.clock.setFixedTime(...)` — no relative timestamps ("2 minutes ago")
- [ ] `locale` + `timezoneId` pinned in the Playwright config
- [ ] Seeded fixtures, no `Math.random()`, no unseeded faker
- [ ] `reducedMotion: 'reduce'` + the animation-killing `addStyleTag` + `animations: 'disabled'`
- [ ] `document.fonts.ready` awaited (font swap is the #1 cause of flaky diffs)
- [ ] Images: local fixtures only — a remote avatar service will change under you
- [ ] Scroll reset; lazy/virtualized lists forced to render (or captured at a fixed scroll offset)
- [ ] One project per viewport, and a dark-mode pass if the app themes
