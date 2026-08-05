#!/usr/bin/env node

// Cross-project wiring check: reconciles declared routes against referenced
// navigation targets, unmounted handler modules, and the icon registry.
// Deterministic, source-only, no browser and no dependencies.

import { readdir, readFile, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'

import { filterFindings } from './detect-ui.mjs'

const SOURCE_EXTENSIONS = new Set([
  '.html', '.htm',
  '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.mts', '.cts',
  '.vue', '.svelte', '.astro',
])

const EXCLUDED_DIRS = new Set([
  '.git', '.next', '.nuxt', '.svelte-kit', '.ux-review',
  'build', 'coverage', 'dist', 'node_modules', 'out', 'storybook-static',
])

export const RULES = Object.freeze([
  { id: 'broken-link', class: 'error', severity: 'P0', owner: 'navigation', confidence: 'high' },
  { id: 'missing-catch-all', class: 'error', severity: 'P0', owner: 'navigation', confidence: 'high' },
  { id: 'unregistered-handler', class: 'error', severity: 'P0', owner: 'navigation', confidence: 'medium' },
  { id: 'unregistered-icon', class: 'warning', severity: 'P1', owner: 'ui', confidence: 'medium' },
  { id: 'orphan-route', class: 'warning', severity: 'P2', owner: 'navigation', confidence: 'medium' },
  { id: 'route-literal', class: 'warning', severity: 'P2', owner: 'navigation', confidence: 'medium' },
])

const RULES_BY_ID = new Map(RULES.map(rule => [rule.id, rule]))

const ROUTER_MARKERS = /createBrowserRouter|createHashRouter|createMemoryRouter|createRouter\s*\(|createWebHistory|createWebHashHistory|RouterModule\s*\.\s*for|createFileRoute|createRootRoute|useRoutes\s*\(|defineRoutes|<Route\b|routes\s*:\s*\[/
const AUTOLOADER_MARKERS = /import\.meta\.glob|require\.context|@fastify\/autoload|AutoLoad|autoload|readdirSync|globSync|fast-glob/
const ICON_STYLESHEET = /fontawesome[^"'\s]*\/css|kit\.fontawesome\.com|font-?awesome(?:\.min)?\.css|\ball(?:\.min)?\.css/i
const ASSET_PATH = /\.(?:png|jpe?g|gif|svg|webp|avif|ico|css|js|mjs|json|pdf|txt|xml|csv|woff2?|ttf|eot|mp[34]|webm|zip)$/i

const TEST_FILE = /(?:^|\/)(?:tests?|e2e|__tests__|__mocks__|cypress|playwright|fixtures)(?:\/|$)|\.(?:test|spec|stories|cy)\.[cm]?[jt]sx?$/i
const HANDLER_FILE = /(?:^|\/)(?:handlers?|controllers?|endpoints?|resolvers?)(?:\/|$)|\.(?:handler|controller|route|routes|endpoint)\.[cm]?[jt]s$/i
const HANDLER_EXPORT = /\bexport\s+(?:default|const|let|var|function|async\s+function|class)\b|\bmodule\.exports\b/

const SERVER_REGISTRATION = /\b(?:app|api|server|router|route|fastify|express\(\))\s*\.\s*(?:get|post|put|patch|delete|options|head|all|use|route|register|addRoute)\s*\(/

const FA_MODIFIERS = new Set([
  'solid', 'regular', 'brands', 'light', 'thin', 'duotone', 'sharp', 'sharp-solid', 'sharp-regular',
  'fw', 'xs', '2xs', 'sm', 'lg', 'xl', '2xl', 'border', 'inverse', 'icon',
  'spin', 'spin-pulse', 'spin-reverse', 'pulse', 'beat', 'fade', 'beat-fade', 'bounce', 'shake',
  'flip', 'flip-horizontal', 'flip-vertical', 'flip-both', 'rotate-by', 'rotate-90', 'rotate-180', 'rotate-270',
  'pull-left', 'pull-right', 'stack', 'stack-1x', 'stack-2x', 'ul', 'li', 'layers', 'layers-text', 'layers-counter',
])

const REFERENCE_PATTERNS = [
  { kind: 'link', regex: /\b(?:href|to)\s*=\s*(?:"([^"]*)"|'([^']*)'|\{\s*['"`]([^'"`]*)['"`]\s*\})/g },
  { kind: 'link', regex: /\b:to\s*=\s*"\s*'([^']*)'\s*"/g },
  { kind: 'nav', regex: /\b(?:\$?router|history|nav|navigation)\s*\.\s*(?:push|replace)\s*\(\s*['"`]([^'"`]*)['"`]/g },
  { kind: 'nav', regex: /\b(?:\$?router|history|nav|navigation)\s*\.\s*(?:push|replace)\s*\(\s*\{[^}]*\bpath\s*:\s*['"`]([^'"`]*)['"`]/g },
  { kind: 'nav', regex: /\b(?:navigate|goto|redirect)\s*\(\s*['"`]([^'"`]*)['"`]/g },
]

function compactEvidence(value) {
  return value.replace(/\s+/g, ' ').trim().slice(0, 180)
}

function locate(text, index) {
  const before = text.slice(0, index)
  const lastBreak = before.lastIndexOf('\n')
  return { line: before.split('\n').length, column: index - lastBreak }
}

function matches(text, regex) {
  const flags = regex.flags.includes('g') ? regex.flags : `${regex.flags}g`
  return [...text.matchAll(new RegExp(regex.source, flags))]
}

function firstGroup(match) {
  return match.slice(1).find(value => value !== undefined)
}

function normalizePath(value) {
  const bare = value.split(/[?#]/)[0]
  if (bare.length > 1 && bare.endsWith('/')) return bare.slice(0, -1)
  return bare
}

export function isCatchAll(routePath) {
  return /^\/?\*{1,2}$/.test(routePath)
    || /pathMatch|\(\.\*\)|\[\.\.\.|:\w+\*/.test(routePath)
    || /(?:^|\/)(?:404|not-?found)$/i.test(routePath)
}

function hasParam(routePath) {
  return /[:*]|\[[^\]]+\]|\{[^}]+\}/.test(routePath)
}

function routeMatcher(routePath) {
  const segments = routePath.replace(/^\//, '').split('/')
  const source = segments.map(segment => {
    if (/^\*{1,2}$/.test(segment) || /^\[\.\.\./.test(segment) || /^:\w+\(\.\*\)\*?$/.test(segment)) return '(?:.*)'
    if (/^(?::\w+\??|\[[^\]]+\]|\{[^}]+\}|<[^>]+>|\$\w+)$/.test(segment)) return '[^/]+'
    return segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  }).join('/')
  return new RegExp(`^/${source}/?$`)
}

// Next / Nuxt / SvelteKit / Astro / Expo conventions: the file path IS the route.
export function fileBasedRoute(file) {
  const unix = file.replaceAll('\\', '/')
  const conventions = [
    { root: /^(?:src\/)?routes\//, tail: /\/?\+page\.(?:svelte|[cm]?[jt]s)$/ },
    { root: /^(?:src\/)?app\//, tail: /\/?page\.[cm]?[jt]sx?$/ },
    { root: /^(?:src\/)?pages\//, tail: /\.(?:[cm]?[jt]sx?|vue|astro)$/ },
  ]

  for (const convention of conventions) {
    const rootMatch = convention.root.exec(unix)
    if (!rootMatch || !convention.tail.test(unix)) continue

    const rest = unix.slice(rootMatch[0].length).replace(convention.tail, '')
    if (/(?:^|\/)(?:api|_app|_document|_middleware|\+layout|\+server|\+error)(?:\/|$)/.test(rest)) return null

    const segments = rest.split('/')
      .filter(segment => segment && !/^\(.*\)$/.test(segment))
      .map(segment => segment
        .replace(/^\[\.\.\..*\]$/, '*')
        .replace(/^\[\[?\.\.\..*\]\]?$/, '*')
        .replace(/^\[(.+?)\]$/, (_all, name) => `:${name.replace(/^\.\.\./, '')}`))
      .filter(segment => segment !== 'index')

    return { route: `/${segments.join('/')}`.replace(/\/$/, '') || '/', root: rootMatch[0] }
  }
  return null
}

// A route's own name lives next to its path in the same entry; a narrow window
// pairs them without parsing the whole route tree.
function nearbyRouteName(text, index) {
  const window = text.slice(Math.max(0, index - 200), index + 200)
  return window.match(/\bname\s*:\s*['"`]([\w.-]+)['"`]/)?.[1]
}

function collectRoutes(file, text) {
  const declared = []
  const push = (routePath, index) => {
    if (!routePath || /\$\{|\{\{/.test(routePath)) return
    declared.push({ path: normalizePath(routePath) || '/', file, index, name: nearbyRouteName(text, index) })
  }

  if (ROUTER_MARKERS.test(text)) {
    for (const match of matches(text, /(?:^|[\s{,(])path\s*:\s*(['"`])([^'"`]*)\1/g)) push(match[2], match.index)
    for (const match of matches(text, /<Route\b[^>]*\bpath\s*=\s*(?:["']([^"']*)["']|\{\s*['"`]([^'"`]*)['"`]\s*\})/g)) {
      push(firstGroup(match), match.index)
    }
    for (const match of matches(text, /createFileRoute\s*\(\s*['"`]([^'"`]+)['"`]/g)) push(match[1], match.index)
  }
  return declared
}

function collectReferences(file, text) {
  const references = []
  const isTest = TEST_FILE.test(file)

  for (const pattern of REFERENCE_PATTERNS) {
    for (const match of matches(text, pattern.regex)) {
      const raw = firstGroup(match)
      if (!raw || !raw.startsWith('/') || raw.startsWith('//')) continue
      if (/\$\{|\{\{|\+/.test(raw)) continue
      if (ASSET_PATH.test(raw)) continue

      references.push({
        path: normalizePath(raw) || '/',
        file,
        index: match.index,
        evidence: compactEvidence(match[0]),
        kind: pattern.kind,
        isTest,
      })
    }
  }
  return references
}

function collectImportTargets(text) {
  const targets = new Set()
  const specifiers = [
    ...matches(text, /\bfrom\s*['"]([^'"]+)['"]/g),
    ...matches(text, /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g),
    ...matches(text, /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g),
    ...matches(text, /\bimport\s+['"]([^'"]+)['"]/g),
  ]

  for (const match of specifiers) {
    const segments = match[1].replace(/\.[cm]?[jt]sx?$/, '').split('/').filter(Boolean)
    const last = segments.at(-1)
    if (!last) continue
    targets.add(last === 'index' && segments.length > 1 ? segments.at(-2) : last)
  }
  return targets
}

function camelIconToKebab(name) {
  return name.replace(/([a-z0-9])([A-Z])/g, '$1-$2').replace(/([A-Z])([A-Z][a-z])/g, '$1-$2').toLowerCase()
}

function collectIcons(file, text) {
  const used = []
  const registered = new Set()

  for (const match of matches(text, /\bfa-([a-z0-9]+(?:-[a-z0-9]+)*)/g)) {
    if (FA_MODIFIERS.has(match[1])) continue
    used.push({ name: match[1], file, index: match.index, evidence: compactEvidence(match[0]) })
  }
  for (const match of matches(text, /\bfa([A-Z][A-Za-z0-9]*)\b/g)) registered.add(camelIconToKebab(match[1]))
  for (const match of matches(text, /\bicon\s*=\s*(?:["']([a-z0-9-]+)["']|\{\s*\[[^\]]*['"]([a-z0-9-]+)['"]\s*\]\s*\})/g)) {
    registered.add(firstGroup(match))
  }
  return { used, registered }
}

export function analyzeProject(sources) {
  const declared = []
  const references = []
  const referencedNames = new Set()
  const importTargets = new Set()
  const iconsUsed = []
  const iconsRegistered = new Set()
  const fileBasedRoots = new Set()
  const routeNameFiles = new Set()
  const serverRoutePrefixes = new Set()

  let hasAutoloader = false
  let hasIconStylesheet = false
  let catchAllEvidence = null

  const byFile = new Map(sources.map(source => [source.file, source]))
  const handlerCandidates = []

  for (const { file, text } of sources) {
    const fileRoute = fileBasedRoute(file)
    if (fileRoute) {
      declared.push({ path: fileRoute.route, file, index: 0, fromFilesystem: true })
      fileBasedRoots.add(fileRoute.root)
      if (isCatchAll(fileRoute.route) || /(?:^|\/)(?:not-found|404)/.test(file)) catchAllEvidence ??= { file, index: 0 }
    }

    declared.push(...collectRoutes(file, text))
    references.push(...collectReferences(file, text))
    for (const target of collectImportTargets(text)) importTargets.add(target)
    if (!ROUTER_MARKERS.test(text)) {
      for (const match of matches(text, /\bname\s*:\s*['"`]([\w.-]+)['"`]/g)) referencedNames.add(match[1])
    }

    const icons = collectIcons(file, text)
    iconsUsed.push(...icons.used)
    for (const name of icons.registered) iconsRegistered.add(name)

    if (AUTOLOADER_MARKERS.test(text)) hasAutoloader = true
    if (ICON_STYLESHEET.test(text)) hasIconStylesheet = true
    if (/\bname\s*:\s*['"`][\w.-]+['"`]/.test(text) && ROUTER_MARKERS.test(text)) routeNameFiles.add(file)
    if (/NotFound|not-?found|["'`]\*["'`]|catchAll|404/i.test(text) && ROUTER_MARKERS.test(text)) {
      catchAllEvidence ??= { file, index: 0 }
    }

    for (const match of matches(text, new RegExp(`${SERVER_REGISTRATION.source}\\s*['"\`]([^'"\`]*)['"\`]`, 'g'))) {
      const prefix = normalizePath(match[1] ?? '')
      if (prefix.startsWith('/')) serverRoutePrefixes.add(prefix)
    }

    if (HANDLER_FILE.test(file) && !TEST_FILE.test(file) && HANDLER_EXPORT.test(text) && !SERVER_REGISTRATION.test(text)) {
      handlerCandidates.push({ file, text })
    }
  }

  const absolute = declared.filter(route => route.path.startsWith('/'))
  const relative = declared.filter(route => !route.path.startsWith('/'))
  const matchers = absolute.map(route => ({ ...route, matcher: routeMatcher(route.path) }))
  const relativeMatchers = relative.map(route => ({ ...route, matcher: new RegExp(`(?:^|/)${routeMatcher(route.path).source.slice(2)}`) }))
  const hasCatchAll = absolute.some(route => isCatchAll(route.path)) || Boolean(catchAllEvidence)

  // A catch-all resolves every URL to the not-found view, so it must never be
  // allowed to prove that a link works.
  const reachable = [...matchers, ...relativeMatchers].filter(route => !isCatchAll(route.path))

  const findings = []
  const add = (id, source, evidence, message, proposedChange, overrides = {}) => {
    const rule = RULES_BY_ID.get(id)
    const text = byFile.get(source.file)?.text ?? ''
    const { line, column } = locate(text, source.index ?? 0)
    findings.push({
      ...rule, file: source.file, line, column, evidence: compactEvidence(evidence),
      message, proposedChange, verification: 'source-detected', ...overrides,
    })
  }

  // Routes are only judgeable when a route table was found at all.
  if (matchers.length > 0) {
    const resolves = target => reachable.some(route => route.matcher.test(target))
      || [...serverRoutePrefixes].some(prefix => target === prefix || target.startsWith(`${prefix}/`))
    const confidence = relative.length > 0 ? 'medium' : 'high'

    for (const reference of references) {
      if (resolves(reference.path)) continue
      add('broken-link', reference, reference.evidence,
        `Navigation target ${reference.path} matches no declared route.`,
        `Register ${reference.path} in the router or point this ${reference.kind === 'link' ? 'link' : 'navigation call'} at an existing route.`,
        { confidence })
    }

    if (!hasCatchAll && absolute.length >= 3) {
      const busiest = [...matchers].sort((a, b) => a.file.localeCompare(b.file))[0]
      add('missing-catch-all', busiest, `${absolute.length} routes declared, no catch-all`,
        'The router has no catch-all route, so an unknown URL renders the layout shell with no content.',
        'Add a catch-all route rendering an explicit "page not found" view with a way back.')
    }

    const referencedByProduct = references.filter(reference => !reference.isTest)
    for (const route of matchers) {
      if (route.fromFilesystem || isCatchAll(route.path) || hasParam(route.path) || route.path === '/') continue
      if (route.name && referencedNames.has(route.name)) continue
      if (referencedByProduct.some(reference => route.matcher.test(reference.path))) continue
      add('orphan-route', route, route.path,
        `Route ${route.path} is declared but never linked from product code.`,
        'Link it from the surface where users start, or delete the route.')
    }

    if (routeNameFiles.size > 0) {
      const literalsByFile = new Map()
      for (const reference of references) {
        if (reference.isTest || /\.html?$/i.test(reference.file)) continue
        if (!literalsByFile.has(reference.file)) literalsByFile.set(reference.file, [])
        literalsByFile.get(reference.file).push(reference)
      }
      for (const [file, group] of literalsByFile) {
        if (routeNameFiles.has(file)) continue
        add('route-literal', group[0], `${group.length} literal path(s), e.g. ${group[0].path}`,
          'Route paths are spread as string literals while the router declares named routes.',
          `Navigate by route name (or a single canonical routes module) instead of the ${group.length} literal path(s) in this file.`)
      }
    }
  }

  if (!hasAutoloader) {
    for (const candidate of handlerCandidates) {
      const base = path.basename(candidate.file).replace(/\.[cm]?[jt]sx?$/, '')
      const key = base === 'index' ? path.basename(path.dirname(candidate.file)) : base
      if (importTargets.has(key)) continue
      if ([...fileBasedRoots].some(root => candidate.file.replaceAll('\\', '/').startsWith(root))) continue
      add('unregistered-handler', { file: candidate.file, index: 0 }, base,
        `${candidate.file} exports a handler that no other module imports, so it is never registered on the app.`,
        'Register it at the composition root and add a test that resolves the path through the composed app, not the handler alone.')
    }
  }

  if (iconsRegistered.size > 0 && !hasIconStylesheet) {
    const reported = new Set()
    for (const icon of iconsUsed) {
      if (iconsRegistered.has(icon.name) || reported.has(icon.name)) continue
      reported.add(icon.name)
      add('unregistered-icon', icon, icon.evidence,
        `Icon fa-${icon.name} is used in markup but is not in the imported icon registry.`,
        `Import fa${icon.name.replace(/(^|-)([a-z0-9])/g, (_all, _sep, char) => char.toUpperCase())} and add it to the icon library, or use a registered icon.`)
    }
  }

  return findings.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.id.localeCompare(b.id))
}

async function collectFiles(target, files) {
  const absolute = path.resolve(target)
  const details = await stat(absolute)
  if (details.isFile()) {
    if (SOURCE_EXTENSIONS.has(path.extname(absolute).toLowerCase())) files.push(absolute)
    return
  }
  if (!details.isDirectory()) return

  for (const entry of await readdir(absolute, { withFileTypes: true })) {
    if (entry.isDirectory() && EXCLUDED_DIRS.has(entry.name)) continue
    const child = path.join(absolute, entry.name)
    if (entry.isDirectory()) await collectFiles(child, files)
    else if (entry.isFile() && SOURCE_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) files.push(child)
  }
}

export async function scanProject(targets, options = {}) {
  const cwd = options.cwd ?? process.cwd()
  const files = []
  for (const target of targets.length ? targets : ['.']) await collectFiles(path.resolve(cwd, target), files)

  const sources = []
  for (const absolute of [...new Set(files)].sort()) {
    sources.push({
      file: (path.relative(cwd, absolute) || path.basename(absolute)).replaceAll('\\', '/'),
      text: await readFile(absolute, 'utf8'),
    })
  }
  return filterFindings(analyzeProject(sources), options.config)
}

function parseArgs(argv) {
  const parsed = { json: false, configPath: '.ui-quality.json', targets: [] }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--json') parsed.json = true
    else if (arg === '--config') parsed.configPath = argv[++index]
    else if (arg === '--help' || arg === '-h') parsed.help = true
    else parsed.targets.push(arg)
  }
  return parsed
}

async function readConfig(configPath) {
  try {
    return JSON.parse(await readFile(path.resolve(configPath), 'utf8'))
  } catch (error) {
    if (error.code === 'ENOENT') return {}
    throw new Error(`Cannot read wiring config ${configPath}: ${error.message}`)
  }
}

function summarize(findings) {
  const count = value => findings.filter(finding => finding.class === value).length
  return { total: findings.length, errors: count('error'), warnings: count('warning'), advisories: count('advisory') }
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    process.stdout.write('Usage: node check-wiring.mjs [--json] [--config path] [file-or-directory ...]\n')
    return
  }

  const config = await readConfig(args.configPath)
  const findings = await scanProject(args.targets, { config })
  const summary = summarize(findings)

  if (args.json) {
    process.stdout.write(`${JSON.stringify({ summary, findings }, null, 2)}\n`)
  } else {
    for (const finding of findings) {
      process.stdout.write(`${finding.file}:${finding.line}:${finding.column} ${finding.severity} ${finding.class} ${finding.id} — ${finding.message}\n`)
    }
    process.stdout.write(`Wiring check: ${summary.errors} error(s), ${summary.warnings} warning(s).\n`)
  }

  if (summary.errors > 0) process.exitCode = 1
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
if (isMain) main().catch(error => {
  process.stderr.write(`${error.message}\n`)
  process.exitCode = 2
})
