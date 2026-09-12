import assert from 'node:assert/strict'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('../scripts/discover-screens.sh', import.meta.url))

function hasRipgrep() {
  const r = spawnSync('rg', ['--version'], { encoding: 'utf8' })
  return r.status === 0 && /^ripgrep/i.test(r.stdout)
}

function run(root, extraArgs) {
  const r = spawnSync('bash', [scriptPath, '--root', root, ...extraArgs], { encoding: 'utf8' })
  assert.equal(r.status, 0, r.stderr)
  // "Engine:" names the engine and "Generated:" is a wall-clock timestamp;
  // neither is a discovery result, so strip both before comparing.
  return r.stdout.replace(/^Engine:.*$/m, '').replace(/^Generated:.*$/m, '')
}

test('grep and ripgrep engines produce identical discovery output on one fixture tree', async (t) => {
  if (!hasRipgrep()) {
    t.skip('ripgrep not installed — cannot compare engines')
    return
  }

  const root = await mkdtemp(path.join(tmpdir(), 'discover-screens-'))
  try {
    await mkdir(path.join(root, 'src', 'routes'), { recursive: true })
    await writeFile(path.join(root, 'package.json'), JSON.stringify({ dependencies: { react: '^18.0.0' } }))
    await writeFile(
      path.join(root, 'src', 'routes', 'index.tsx'),
      [
        "import { Route } from 'react-router-dom'",
        "export const routes = [",
        "  { path: '/dashboard', component: Dashboard },",
        "  { path: '/settings/:id', component: Settings },",
        ']',
      ].join('\n'),
    )
    await writeFile(
      path.join(root, 'src', 'Dashboard.tsx'),
      "export function Dashboard() { return isLoading ? <Skeleton/> : <div/> }",
    )

    const withRipgrep = run(root, [])
    const withGrep = run(root, ['--no-rg'])

    assert.equal(withRipgrep, withGrep)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
