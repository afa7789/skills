import assert from 'node:assert/strict'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

import { analyzeProject, fileBasedRoute, isCatchAll, RULES, scanProject } from '../scripts/check-wiring.mjs'

const checkerPath = fileURLToPath(new URL('../scripts/check-wiring.mjs', import.meta.url))

const ROUTER = {
  file: 'src/router/index.ts',
  text: `
    import { createRouter, createWebHistory } from 'vue-router'
    export default createRouter({
      history: createWebHistory(),
      routes: [
        { path: '/dashboard', name: 'dashboard', component: Dashboard },
        { path: '/astro/create', name: 'astro-create', component: AstroCreate },
        { path: '/astro/transits/:id', name: 'astro-transits', component: Transits },
        { path: '/:pathMatch(.*)*', name: 'not-found', component: NotFound },
      ],
    })
  `,
}

test('registry exposes a deterministic wiring rule set', () => {
  assert.equal(RULES.length, 6)
  assert.equal(new Set(RULES.map(rule => rule.id)).size, RULES.length)
  assert.deepEqual(new Set(RULES.map(rule => rule.class)), new Set(['error', 'warning']))
})

test('flags a navigation target that matches no declared route', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'src/views/Dashboard.vue', text: '<a href="/mapas/novo">Novo mapa</a>' },
  ])
  const broken = findings.filter(finding => finding.id === 'broken-link')

  assert.equal(broken.length, 1)
  assert.equal(broken[0].severity, 'P0')
  assert.match(broken[0].message, /\/mapas\/novo/)
  assert.equal(broken[0].file, 'src/views/Dashboard.vue')
})

test('accepts parameterized routes and rejects a wrong parameterized target', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'src/views/Menu.vue', text: `
      <router-link to="/astro/transits/42">Trânsitos</router-link>
      <router-link to="/astro/transit/42">Trânsitos (legado)</router-link>
    ` },
  ])
  const broken = findings.filter(finding => finding.id === 'broken-link')

  assert.equal(broken.length, 1)
  assert.match(broken[0].evidence, /\/astro\/transit\/42/)
})

test('flags navigation calls, not only markup links', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'src/pages/Card.vue', text: "router.push('/bilhete')" },
  ])

  assert.ok(findings.some(finding => finding.id === 'broken-link' && /\/bilhete/.test(finding.message)))
})

test('a test file referencing an unregistered dev route is still a broken link', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'tests/screens.spec.ts', text: "await page.goto('/__dev/screens/dashboard')" },
  ])

  assert.ok(findings.some(finding => finding.id === 'broken-link' && /__dev\/screens/.test(finding.message)))
})

test('requires a catch-all route and stays quiet when one exists', () => {
  const withoutCatchAll = analyzeProject([{
    file: 'src/router.ts',
    text: `createRouter({ routes: [
      { path: '/dashboard' }, { path: '/astro/create' }, { path: '/people' },
    ] })`,
  }])
  const finding = withoutCatchAll.find(item => item.id === 'missing-catch-all')

  assert.ok(finding)
  assert.equal(finding.severity, 'P0')
  assert.ok(!analyzeProject([ROUTER]).some(item => item.id === 'missing-catch-all'))
})

test('reports a declared route nothing links to, ignoring test-only references', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'src/views/Menu.vue', text: '<a href="/dashboard">Dashboard</a><a href="/astro/create">Novo mapa</a>' },
    { file: 'tests/create.spec.ts', text: "await page.goto('/astro/create')" },
  ])
  const orphans = findings.filter(finding => finding.id === 'orphan-route')

  assert.deepEqual(orphans.map(finding => finding.evidence), [])

  const unlinked = analyzeProject([ROUTER, { file: 'src/views/Menu.vue', text: '<a href="/dashboard">Dashboard</a>' }])
  assert.ok(unlinked.some(finding => finding.id === 'orphan-route' && finding.evidence === '/astro/create'))
})

test('groups literal route paths per file when the router declares names', () => {
  const findings = analyzeProject([
    ROUTER,
    { file: 'src/views/Menu.vue', text: '<a href="/dashboard">A</a><a href="/astro/create">B</a>' },
  ])
  const literals = findings.filter(finding => finding.id === 'route-literal')

  assert.equal(literals.length, 1)
  assert.match(literals[0].evidence, /^2 literal path\(s\)/)
})

test('flags a handler module that no composition root imports', () => {
  const sources = [
    { file: 'src/handlers/bilhete.ts', text: 'export function bilheteHandler(req, res) { res.json({}) }' },
    { file: 'src/handlers/people.ts', text: 'export function peopleHandler(req, res) { res.json({}) }' },
    { file: 'src/server.ts', text: "import { peopleHandler } from './handlers/people'\napp.get('/people', peopleHandler)" },
  ]
  const findings = analyzeProject(sources)
  const unregistered = findings.filter(finding => finding.id === 'unregistered-handler')

  assert.equal(unregistered.length, 1)
  assert.equal(unregistered[0].file, 'src/handlers/bilhete.ts')
  assert.equal(unregistered[0].severity, 'P0')
})

test('skips the handler rule when modules are auto-loaded', () => {
  const findings = analyzeProject([
    { file: 'src/handlers/bilhete.ts', text: 'export function bilheteHandler() {}' },
    { file: 'src/server.ts', text: 'const routes = import.meta.glob("./handlers/*.ts")' },
  ])

  assert.ok(!findings.some(finding => finding.id === 'unregistered-handler'))
})

test('flags icon classes missing from the imported registry', () => {
  const findings = analyzeProject([
    { file: 'src/icons.ts', text: "import { faPlus, faArrowRight } from '@fortawesome/free-solid-svg-icons'\nlibrary.add(faPlus, faArrowRight)" },
    { file: 'src/views/Menu.vue', text: '<i class="fa-solid fa-plus fa-lg"></i><i class="fa-solid fa-cake-candles"></i>' },
  ])
  const icons = findings.filter(finding => finding.id === 'unregistered-icon')

  assert.equal(icons.length, 1)
  assert.equal(icons[0].severity, 'P1')
  assert.match(icons[0].message, /fa-cake-candles/)
  assert.match(icons[0].proposedChange, /faCakeCandles/)
})

test('skips the icon rule when the full stylesheet is loaded', () => {
  const findings = analyzeProject([
    { file: 'src/main.ts', text: "import { faPlus } from '@fortawesome/free-solid-svg-icons'\nimport '@fortawesome/fontawesome-free/css/all.min.css'" },
    { file: 'src/views/Menu.vue', text: '<i class="fa-solid fa-cake-candles"></i>' },
  ])

  assert.ok(!findings.some(finding => finding.id === 'unregistered-icon'))
})

test('derives file-based routes and treats them as declared', () => {
  assert.deepEqual(fileBasedRoute('src/routes/astro/create/+page.svelte'), { route: '/astro/create', root: 'src/routes/' })
  assert.deepEqual(fileBasedRoute('app/(marketing)/pricing/page.tsx'), { route: '/pricing', root: 'app/' })
  assert.deepEqual(fileBasedRoute('pages/index.vue'), { route: '/', root: 'pages/' })
  assert.equal(fileBasedRoute('pages/api/webhook.ts'), null)
  assert.equal(fileBasedRoute('src/components/Button.vue'), null)

  const findings = analyzeProject([
    { file: 'app/dashboard/page.tsx', text: '<a href="/dashboard">Home</a><a href="/missing">Gone</a>' },
    { file: 'app/not-found.tsx', text: 'export default function NotFound() { return <h1>Not found</h1> }' },
  ])

  assert.ok(findings.some(finding => finding.id === 'broken-link' && /\/missing/.test(finding.message)))
  assert.ok(!findings.some(finding => finding.id === 'broken-link' && /\/dashboard/.test(finding.message)))
})

test('identifies catch-all shapes across frameworks', () => {
  for (const value of ['*', '/*', '/:pathMatch(.*)*', '/[...slug]', '/404', '/not-found']) {
    assert.ok(isCatchAll(value), `expected catch-all: ${value}`)
  }
  for (const value of ['/', '/dashboard', '/astro/:id']) assert.ok(!isCatchAll(value))
})

test('stays silent when no route table exists and on a wired baseline', () => {
  assert.deepEqual(analyzeProject([{ file: 'src/lib/format.ts', text: "export const base = '/api/v1'" }]), [])

  const wired = analyzeProject([
    ROUTER,
    { file: 'src/views/Menu.vue', text: `
      <router-link :to="{ name: 'dashboard' }">Dashboard</router-link>
      <router-link :to="{ name: 'astro-create' }">Novo mapa</router-link>
      <router-link :to="{ name: 'astro-transits', params: { id } }">Trânsitos</router-link>
    ` },
  ])
  assert.deepEqual(wired, [])
})

test('honors the shared detector ignore config and reports through the CLI', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'check-wiring-'))
  try {
    await mkdir(path.join(root, 'src'), { recursive: true })
    await writeFile(path.join(root, 'src', 'router.ts'), ROUTER.text)
    await writeFile(path.join(root, 'src', 'Menu.vue'), '<a href="/mapas/novo">Novo mapa</a>')

    const findings = await scanProject(['.'], { cwd: root })
    assert.ok(findings.some(finding => finding.id === 'broken-link'))

    const ignored = await scanProject(['.'], { cwd: root, config: { ignoreRules: ['broken-link', 'route-literal', 'orphan-route'] } })
    assert.deepEqual(ignored, [])

    const cli = spawnSync(process.execPath, [checkerPath, '--json', '.'], { cwd: root, encoding: 'utf8' })
    const output = JSON.parse(cli.stdout)

    assert.equal(cli.status, 1)
    assert.ok(output.summary.errors >= 1)

    const missing = spawnSync(process.execPath, [checkerPath, path.join(root, 'nope')], { encoding: 'utf8' })
    assert.equal(missing.status, 2)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
