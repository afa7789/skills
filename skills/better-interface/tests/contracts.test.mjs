import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const skillRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const skillsRoot = path.resolve(skillRoot, '..')

test('gateway references resolve and frontmatter stays minimal', async () => {
  const skill = await readFile(path.join(skillRoot, 'SKILL.md'), 'utf8')
  const frontmatter = skill.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? ''
  const keys = [...frontmatter.matchAll(/^([a-z][a-z-]*):/gm)].map(match => match[1])
  assert.deepEqual(keys, ['name', 'description'])

  const references = [...skill.matchAll(/\]\((reference\/[^)]+)\)/g)].map(match => match[1])
  assert.ok(references.length >= 7)
  for (const reference of references) await access(path.join(skillRoot, reference))
})

test('context templates keep product, design, and surface authority separate', async () => {
  const expectations = new Map([
    ['PRODUCT.template.md', ['## Users and jobs', '## Capabilities and constraints']],
    ['DESIGN.template.md', ['## Color and semantic tokens', '## Components and states']],
    ['SURFACE.template.md', ['Visitor mode:', 'Change type:']],
  ])

  for (const [file, headings] of expectations) {
    const content = await readFile(path.join(skillRoot, 'assets', file), 'utf8')
    for (const heading of headings) assert.ok(content.includes(heading), `${file} misses ${heading}`)
  }
})

test('frontend skills share the P0-P3 contract and audit runs the detector', async () => {
  const domains = ['accessibility', 'layout', 'writing', 'typography', 'colors', 'ui']
  for (const domain of domains) {
    const content = await readFile(path.join(skillsRoot, `better-${domain}`, 'SKILL.md'), 'utf8')
    assert.match(content, /`P0`/)
    assert.doesNotMatch(content, /`HIGH`|`MEDIUM`|`LOW`/)
  }

  const audit = await readFile(path.join(skillsRoot, 'frontend-audit', 'SKILL.md'), 'utf8')
  assert.match(audit, /scripts\/detect-ui\.mjs/)
  await access(path.join(skillsRoot, 'frontend-audit', 'scripts', 'detect-ui.mjs'))

  const gateway = await readFile(path.join(skillRoot, 'SKILL.md'), 'utf8')
  const quickGate = await readFile(path.join(skillRoot, 'reference', 'quick-gate.md'), 'utf8')
  assert.match(gateway, /quick[^\n]*P0.P3/i)
  assert.match(quickGate, /P0.P3/)
})

test('gateway and audit SKILL links resolve locally', async () => {
  for (const root of [skillRoot, path.join(skillsRoot, 'frontend-audit')]) {
    const content = await readFile(path.join(root, 'SKILL.md'), 'utf8')
    const links = [...content.matchAll(/\]\(([^)]+)\)/g)]
      .map(match => match[1].split('#')[0])
      .filter(link => link && !link.includes('://'))
    for (const link of links) await access(path.resolve(root, link))
  }
})
