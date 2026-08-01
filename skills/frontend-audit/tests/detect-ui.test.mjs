import assert from 'node:assert/strict'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

import { filterFindings, RULES, scanPaths, scanText } from '../scripts/detect-ui.mjs'

const detectorPath = fileURLToPath(new URL('../scripts/detect-ui.mjs', import.meta.url))

test('registry exposes a concise deterministic rule set', () => {
  assert.equal(RULES.length, 17)
  assert.deepEqual(new Set(RULES.map(rule => rule.class)), new Set(['error', 'warning', 'advisory']))
  assert.equal(new Set(RULES.map(rule => rule.id)).size, RULES.length)
})

test('detects objective accessibility and interaction failures', () => {
  const findings = scanText(`
    <meta name="viewport" content="width=device-width, maximum-scale=1">
    <div onClick={save} tabindex="2">Save</div>
    <img src="cover.png">
    <button aria-hidden="true">Hidden</button>
    <video autoplay src="intro.mp4"></video>
  `, 'src/App.tsx')
  const ids = new Set(findings.map(finding => finding.id))

  for (const id of [
    'disabled-viewport-zoom', 'interactive-nonsemantic', 'positive-tabindex',
    'image-missing-alt', 'aria-hidden-focusable', 'autoplay-without-controls',
    'button-missing-type',
  ]) assert.ok(ids.has(id), `missing ${id}`)
})

test('detects system drift and keeps aesthetic checks advisory', () => {
  const findings = scanText(`
    <h1>Title</h1><h3>Details</h3>
    <article class="card"><section class="metric-card">Value</section></article>
    <p class="text-[10px] bg-clip-text transition-all animate-pulse">Tiny</p>
  `, 'src/Dashboard.html')
  const byId = new Map(findings.map(finding => [finding.id, finding]))

  assert.equal(byId.get('skipped-heading-level').severity, 'P2')
  assert.equal(byId.get('tiny-text').class, 'warning')
  assert.equal(byId.get('nested-cards').class, 'advisory')
  assert.equal(byId.get('gradient-text').severity, 'P3')
  assert.equal(byId.get('decorative-pulse').severity, 'P3')
})

test('supports rule, file, and evidence-scoped ignores', () => {
  const findings = scanText(`
    <p class="bg-clip-text transition-all">Decorative</p>
    <p class="text-[10px]">Legal</p>
  `, 'src/legacy/Hero.tsx')

  const filtered = filterFindings(findings, {
    ignoreRules: ['gradient-text'],
    ignoreFiles: ['**/legacy/**'],
    ignores: [{ rule: 'tiny-text', contains: 'text-[10px]' }],
  })

  assert.equal(filtered.length, 0)

  const rootFiltered = filterFindings(
    scanText('<p class="transition-all">Legacy</p>', 'legacy/Hero.tsx'),
    { ignoreFiles: ['**/legacy/**'] },
  )
  assert.equal(rootFiltered.length, 0)
})

test('passes a semantic baseline', () => {
  const findings = scanText(`
    <main>
      <h1>Settings</h1>
      <img src="avatar.png" alt="Afa">
      <button type="button">Save</button>
      <a href="/billing">Billing</a>
    </main>
  `, 'src/Settings.tsx')

  assert.deepEqual(findings, [])
})

test('avoids blocking false positives in valid viewport and non-focusable controls', () => {
  const findings = scanText(`
    <meta name="viewport" content="width=device-width, maximum-scale=10">
    <meta name="preview" content="maximum-scale=1.5">
    const viewportExample = "maximum-scale=1"
    <button disabled aria-hidden="true">Unavailable</button>
    <button disabled={loading} aria-hidden="true">Conditionally unavailable</button>
    <input type="hidden" aria-hidden="true">
    <input type={"hidden"} aria-hidden="true">
    <input type={fieldType} aria-hidden="true">
    <a aria-hidden="true">Not a link</a>
  `, 'index.html')

  assert.ok(!findings.some(finding => finding.id === 'disabled-viewport-zoom'))
  assert.ok(!findings.some(finding => finding.id === 'aria-hidden-focusable'))

  const visibleInput = scanText('<input type={"text"} aria-hidden="true">', 'src/Field.tsx')
  assert.ok(visibleInput.some(finding => finding.id === 'aria-hidden-focusable'))
})

test('parses JSX arrows without truncating tag attributes', () => {
  const findings = scanText(`
    <button onClick={() => save()} type="button">Save</button>
    <img onError={() => fallback()} src="cover.png" alt="">
  `, 'src/Page.tsx')

  assert.ok(!findings.some(finding => finding.id === 'button-missing-type'))
  assert.ok(!findings.some(finding => finding.id === 'image-missing-alt'))
})

test('handles literal React media booleans', () => {
  const findings = scanText(`
    <video autoPlay={false}></video>
    <video autoPlay controls={false}></video>
    <video autoPlay controls></video>
  `, 'src/Media.tsx')
  const media = findings.filter(finding => finding.id === 'autoplay-without-controls')

  assert.equal(media.length, 1)
  assert.match(media[0].evidence, /controls=\{false\}/)
})

test('does not treat examples or independent React components as rendered failures', () => {
  const findings = scanText(`
    // Example: <button>Save</button>
    const value = 1 // Example: <button>Save</button>
    {/* <img src="example.png"> */}
    const snippet = '<button>Example</button>'
    const template = \`<button>Example</button>\`
    export const PageTitle = () => <h1>Page</h1>
    export const CardTitle = () => <h3>Card</h3>
  `, 'src/examples.tsx')

  assert.ok(!findings.some(finding => finding.id === 'button-missing-type'))
  assert.ok(!findings.some(finding => finding.id === 'image-missing-alt'))
  assert.ok(!findings.some(finding => finding.id === 'skipped-heading-level'))
})

test('scans Astro files and rejects nonexistent targets', async () => {
  const fixtureDir = await mkdtemp(path.join(tmpdir(), 'detect-ui-targets-'))
  try {
    await writeFile(path.join(fixtureDir, 'Page.astro'), '<img src="cover.png">')
    const findings = await scanPaths(['.'], { cwd: fixtureDir })
    assert.ok(findings.some(finding => finding.id === 'image-missing-alt'))

    const missing = spawnSync(process.execPath, [detectorPath, path.join(fixtureDir, 'missing')], { encoding: 'utf8' })
    assert.equal(missing.status, 2)
    assert.match(missing.stderr, /ENOENT/)
  } finally {
    await rm(fixtureDir, { recursive: true, force: true })
  }
})

test('CLI emits machine-readable output and fails only on errors', async () => {
  const fixtureDir = await mkdtemp(path.join(tmpdir(), 'detect-ui-'))
  const fixture = path.join(fixtureDir, 'Page.tsx')
  try {
    await writeFile(fixture, '<button type="button" aria-hidden="true">Hidden</button>\n<p class="bg-clip-text">Brand</p>')

    const result = spawnSync(process.execPath, [detectorPath, '--json', fixture], { encoding: 'utf8' })
    const output = JSON.parse(result.stdout)

    assert.equal(result.status, 1)
    assert.equal(output.summary.errors, 1)
    assert.equal(output.summary.advisories, 1)
  } finally {
    await rm(fixtureDir, { recursive: true, force: true })
  }
})
