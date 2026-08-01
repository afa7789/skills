#!/usr/bin/env node

import { readdir, readFile, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'

const SOURCE_EXTENSIONS = new Set([
  '.html', '.htm', '.css', '.scss', '.sass', '.less',
  '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.vue', '.svelte', '.astro', '.mdx',
])

const EXCLUDED_DIRS = new Set([
  '.git', '.next', '.nuxt', '.svelte-kit', '.ux-review',
  'build', 'coverage', 'dist', 'node_modules', 'out', 'storybook-static',
])

const SIMPLE_RULES = [
  {
    id: 'disabled-viewport-zoom', class: 'error', severity: 'P0', owner: 'accessibility', confidence: 'high',
    regex: /(?:user-scalable\s*=\s*["']?no(?=["'\s,;]|$)|maximum-scale\s*=\s*["']?1(?:\.0+)?(?=["'\s,;]|$))/gi,
    message: 'The viewport prevents or caps user zoom.',
    proposedChange: 'Remove user-scalable=no and maximum-scale=1; make the layout survive zoom.',
  },
  {
    id: 'positive-tabindex', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'high',
    regex: /tabindex\s*=\s*(?:["']|\{)?\s*[1-9]\d*/gi,
    message: 'A positive tabindex overrides the natural focus order.',
    proposedChange: 'Use DOM order with tabindex=0 or -1 only.',
  },
  {
    id: 'interactive-nonsemantic', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'high',
    regex: /<(?:div|span)\b[^>]*(?:onclick|onClick|@click|v-on:click)\s*=/gi,
    message: 'A non-semantic element handles pointer activation.',
    proposedChange: 'Use button for actions or a[href] for navigation; preserve native keyboard behavior.',
  },
  {
    id: 'empty-link-target', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'high',
    regex: /<a\b[^>]*href\s*=\s*["'](?:#|javascript:void\(0\))?["']/gi,
    message: 'A link has an empty or script-only destination.',
    proposedChange: 'Use a real href for navigation or a button for an action.',
  },
  {
    id: 'focus-outline-removed', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'medium',
    regex: /(?:outline\s*:\s*(?:none|0)\b|\boutline-none\b)/gi,
    message: 'A focus outline is removed; a verified replacement may be missing.',
    proposedChange: 'Keep the native outline or add a visible :focus-visible replacement and verify forced colors.',
  },
  {
    id: 'unsafe-html-sink', class: 'warning', severity: 'P1', owner: 'ui', confidence: 'medium',
    regex: /(?:dangerouslySetInnerHTML|\bv-html\s*=|\{@html\b)/g,
    message: 'Raw HTML is injected into the interface.',
    proposedChange: 'Remove the raw HTML sink or prove content is sanitized at the trust boundary.',
  },
  {
    id: 'transition-all', class: 'warning', severity: 'P2', owner: 'ui', confidence: 'high',
    regex: /(?:\btransition\s*:\s*all\b|\btransition-all\b)/gi,
    message: 'The transition animates every changed property.',
    proposedChange: 'List only the properties that should animate.',
  },
  {
    id: 'tiny-text', class: 'warning', severity: 'P2', owner: 'typography', confidence: 'medium',
    regex: /(?:font-size\s*:\s*(?:[1-9]|1[01])px\b|\btext-\[(?:[1-9]|1[01])px\])/gi,
    message: 'Functional text may render below the 12px quality floor.',
    proposedChange: 'Use the project type scale and verify the rendered role, viewport, and contrast.',
  },
  {
    id: 'gradient-text', class: 'advisory', severity: 'P3', owner: 'colors', confidence: 'high',
    regex: /(?:background-clip\s*:\s*text|-webkit-background-clip\s*:\s*text|\bbg-clip-text\b)/gi,
    message: 'Gradient text is a saturated generated-UI pattern when it lacks contextual purpose.',
    proposedChange: 'Keep it only when the design brief makes it intentional; otherwise use a solid semantic color.',
  },
  {
    id: 'hardcoded-directional-css', class: 'advisory', severity: 'P3', owner: 'layout', confidence: 'medium',
    regex: /\b(?:margin|padding|border)-(?:left|right)\s*:|\b(?:left|right)\s*:\s*[-\d]/gi,
    message: 'Physical left/right CSS may not adapt to RTL.',
    proposedChange: 'Use logical properties when the direction is semantic rather than physical.',
  },
  {
    id: 'decorative-pulse', class: 'advisory', severity: 'P3', owner: 'ui', confidence: 'medium',
    regex: /(?:\banimate-pulse\b|animation(?:-name)?\s*:\s*[^;\n]*\bpulse\b)/gi,
    message: 'A pulse animation may simulate liveness without representing changing data.',
    proposedChange: 'Keep pulse only for genuinely live state; otherwise use a static labeled indicator.',
  },
]

export const RULES = Object.freeze([
  ...SIMPLE_RULES.map(({ regex: _regex, ...rule }) => rule),
  { id: 'image-missing-alt', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'high' },
  { id: 'aria-hidden-focusable', class: 'error', severity: 'P0', owner: 'accessibility', confidence: 'high' },
  { id: 'autoplay-without-controls', class: 'warning', severity: 'P1', owner: 'accessibility', confidence: 'high' },
  { id: 'button-missing-type', class: 'warning', severity: 'P2', owner: 'accessibility', confidence: 'medium' },
  { id: 'skipped-heading-level', class: 'warning', severity: 'P2', owner: 'accessibility', confidence: 'medium' },
  { id: 'nested-cards', class: 'advisory', severity: 'P3', owner: 'layout', confidence: 'medium' },
])

const TAG_RULES = new Map(RULES.map(rule => [rule.id, rule]))
const STRUCTURED_RULE_IDS = new Set([
  'disabled-viewport-zoom', 'positive-tabindex', 'interactive-nonsemantic', 'empty-link-target',
])
const SIMPLE_RULES_BY_ID = new Map(SIMPLE_RULES.map(rule => [rule.id, rule]))

function compactEvidence(value) {
  return value.replace(/\s+/g, ' ').trim().slice(0, 180)
}

function locate(text, index) {
  const before = text.slice(0, index)
  const lastBreak = before.lastIndexOf('\n')
  return {
    line: before.split('\n').length,
    column: index - lastBreak,
  }
}

function regexMatches(text, regex) {
  const flags = regex.flags.includes('g') ? regex.flags : `${regex.flags}g`
  const copy = new RegExp(regex.source, flags)
  return [...text.matchAll(copy)]
}

function preserveLines(value) {
  return value.replace(/[^\n]/g, ' ')
}

function maskLineComments(text) {
  return text.split('\n').map(line => {
    let quote = null
    let escaped = false
    for (let index = 0; index < line.length - 1; index += 1) {
      const character = line[index]
      if (quote) {
        if (escaped) escaped = false
        else if (character === '\\') escaped = true
        else if (character === quote) quote = null
        continue
      }
      if (character === '"' || character === "'" || character === '`') {
        quote = character
        continue
      }
      if (character === '/' && line[index + 1] === '/' && line[index - 1] !== ':') {
        return `${line.slice(0, index)}${preserveLines(line.slice(index))}`
      }
    }
    return line
  }).join('\n')
}

function maskIgnoredSource(text, file) {
  let masked = maskLineComments(text
    .replace(/<!--[\s\S]*?-->/g, preserveLines)
    .replace(/\/\*[\s\S]*?\*\//g, preserveLines))

  if (/\.(?:[cm]?[jt]sx?)$/i.test(file)) {
    masked = masked.replace(/(["'])(?:\\.|(?!\1)[^\\\n])*\1/g, value => (
      /<\/?[a-z][\w:-]*\b/i.test(value) ? preserveLines(value) : value
    ))
    masked = masked.replace(/`(?:\\[\s\S]|[^\\`])*`/g, value => (
      /<\/?[a-z][\w:-]*\b/i.test(value) ? preserveLines(value) : value
    ))
  }
  return masked
}

function extractTags(text) {
  const tags = []
  const start = /<\s*(\/?)\s*([a-z][\w:-]*)\b/gi
  let match

  while ((match = start.exec(text))) {
    let quote = null
    let escaped = false
    let braceDepth = 0
    let end = -1

    for (let index = start.lastIndex; index < text.length; index += 1) {
      const character = text[index]
      if (quote) {
        if (escaped) escaped = false
        else if (character === '\\') escaped = true
        else if (character === quote) quote = null
        continue
      }
      if (character === '"' || character === "'" || character === '`') {
        quote = character
        continue
      }
      if (character === '{') braceDepth += 1
      else if (character === '}' && braceDepth > 0) braceDepth -= 1
      else if (character === '>' && braceDepth === 0) {
        end = index + 1
        break
      }
    }

    if (end < 0) break
    const whole = text.slice(match.index, end)
    tags.push({
      index: match.index,
      tagName: match[2].toLowerCase(),
      closing: match[1] === '/',
      selfClosing: /\/\s*>$/.test(whole),
      whole,
    })
    start.lastIndex = end
  }
  return tags
}

function readAttribute(tag, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = new RegExp(`(?:^|\\s)${escaped}(?=\\s|=|/?>)`, 'i').exec(tag)
  if (!match) return { present: false }

  let index = match.index + match[0].length
  while (/\s/.test(tag[index] ?? '')) index += 1
  if (tag[index] !== '=') return { present: true, kind: 'bare', value: '' }
  index += 1
  while (/\s/.test(tag[index] ?? '')) index += 1

  const opener = tag[index]
  if (opener === '"' || opener === "'") {
    const end = tag.indexOf(opener, index + 1)
    return { present: true, kind: 'quoted', value: tag.slice(index + 1, end < 0 ? tag.length : end) }
  }
  if (opener === '{') {
    const end = tag.indexOf('}', index + 1)
    return { present: true, kind: 'expression', value: tag.slice(index + 1, end < 0 ? tag.length : end).trim() }
  }
  const end = tag.slice(index).search(/[\s>]/)
  return { present: true, kind: 'unquoted', value: tag.slice(index, end < 0 ? tag.length : index + end) }
}

function tagHasAttribute(tag, name) {
  return readAttribute(tag, name).present
}

function booleanAttributeState(tag, name) {
  const attribute = readAttribute(tag, name)
  if (!attribute.present) return 'absent'
  if (attribute.kind !== 'expression') return 'true'
  if (attribute.value === 'true') return 'true'
  if (attribute.value === 'false') return 'false'
  return 'unknown'
}

function staticAttributeValue(attribute) {
  if (!attribute.present) return undefined
  if (attribute.kind !== 'expression') return attribute.value
  const literal = attribute.value.match(/^(["'])([\s\S]*)\1$/)
  return literal?.[2]
}

function tagFinding(id, index, evidence, overrides = {}) {
  const rule = TAG_RULES.get(id)
  const messages = {
    'image-missing-alt': ['An image has no alt attribute.', 'Add alt="" for decorative images or meaningful alternative text for informative/functional images.'],
    'aria-hidden-focusable': ['A focusable element is hidden from the accessibility tree.', 'Remove aria-hidden or make the element non-focusable and unavailable to every input mode.'],
    'autoplay-without-controls': ['Media autoplays without a visible control.', 'Remove autoplay or provide visible pause/stop controls and honor reduced motion.'],
    'button-missing-type': ['A button relies on the implicit submit type.', 'Set type="button" unless this control intentionally submits its form.'],
    'skipped-heading-level': ['Heading levels skip a structural level.', 'Use a coherent heading outline without changing levels only for visual size.'],
    'nested-cards': ['A card-like container is nested inside another card-like container.', 'Flatten the hierarchy unless both boundaries communicate distinct, necessary structure.'],
  }
  return {
    ...rule,
    index,
    evidence: compactEvidence(evidence),
    message: messages[id][0],
    proposedChange: messages[id][1],
    verification: 'source-detected',
    ...overrides,
  }
}

export function scanText(text, file = '<memory>') {
  const findings = []
  const source = maskIgnoredSource(text, file)
  const tags = extractTags(source)
  const add = finding => {
    const { line, column } = locate(text, finding.index)
    findings.push({
      id: finding.id,
      class: finding.class,
      severity: finding.severity,
      confidence: finding.confidence,
      owner: finding.owner,
      file,
      line,
      column,
      evidence: finding.evidence,
      message: finding.message,
      proposedChange: finding.proposedChange,
      verification: finding.verification ?? 'source-detected',
    })
  }

  for (const rule of SIMPLE_RULES) {
    if (STRUCTURED_RULE_IDS.has(rule.id)) continue
    for (const match of regexMatches(source, rule.regex)) {
      add({ ...rule, index: match.index, evidence: compactEvidence(match[0]) })
    }
  }

  for (const tag of tags.filter(item => !item.closing)) {
    if (tag.tagName === 'meta') {
      const rule = SIMPLE_RULES_BY_ID.get('disabled-viewport-zoom')
      for (const match of regexMatches(tag.whole, rule.regex)) {
        add({ ...rule, index: tag.index + match.index, evidence: compactEvidence(match[0]) })
      }
    }

    const tabIndex = readAttribute(tag.whole, 'tabindex')
    if (tabIndex.present && /^[1-9]\d*$/.test(tabIndex.value ?? '')) {
      const rule = SIMPLE_RULES_BY_ID.get('positive-tabindex')
      add({ ...rule, index: tag.index, evidence: compactEvidence(tag.whole) })
    }

    if (/^(?:div|span)$/.test(tag.tagName) && ['onclick', '@click', 'v-on:click'].some(name => tagHasAttribute(tag.whole, name))) {
      const rule = SIMPLE_RULES_BY_ID.get('interactive-nonsemantic')
      add({ ...rule, index: tag.index, evidence: compactEvidence(tag.whole) })
    }

    if (tag.tagName === 'a') {
      const href = readAttribute(tag.whole, 'href')
      if (href.present && /^(?:|#|javascript:void\(0\))$/i.test(href.value ?? '')) {
        const rule = SIMPLE_RULES_BY_ID.get('empty-link-target')
        add({ ...rule, index: tag.index, evidence: compactEvidence(tag.whole) })
      }
    }
  }

  for (const tag of tags.filter(item => !item.closing && item.tagName === 'img')) {
    if (!tagHasAttribute(tag.whole, 'alt')) add(tagFinding('image-missing-alt', tag.index, tag.whole))
  }

  for (const tag of tags.filter(item => !item.closing && /^(?:a|button|input|select|textarea)$/.test(item.tagName))) {
    const ariaHidden = readAttribute(tag.whole, 'aria-hidden')
    const ariaHiddenTrue = staticAttributeValue(ariaHidden) === 'true'
    const disabledState = booleanAttributeState(tag.whole, 'disabled')
    const type = readAttribute(tag.whole, 'type')
    const typeValue = staticAttributeValue(type)
    const hiddenInput = tag.tagName === 'input' && typeValue?.toLowerCase() === 'hidden'
    const uncertainInputType = tag.tagName === 'input' && type.kind === 'expression' && typeValue === undefined
    const linkWithoutFocus = tag.tagName === 'a'
      && !tagHasAttribute(tag.whole, 'href')
      && !tagHasAttribute(tag.whole, 'tabindex')
      && !tagHasAttribute(tag.whole, 'contenteditable')
    const definitelyEnabled = disabledState === 'absent' || disabledState === 'false'
    if (ariaHiddenTrue && definitelyEnabled && !hiddenInput && !uncertainInputType && !linkWithoutFocus) {
      add(tagFinding('aria-hidden-focusable', tag.index, tag.whole))
    }
  }

  for (const tag of tags.filter(item => !item.closing && /^(?:video|audio)$/.test(item.tagName))) {
    const autoplay = booleanAttributeState(tag.whole, 'autoplay')
    const controls = booleanAttributeState(tag.whole, 'controls')
    if (autoplay === 'true' && (controls === 'absent' || controls === 'false')) {
      add(tagFinding('autoplay-without-controls', tag.index, tag.whole))
    }
  }

  for (const tag of tags.filter(item => !item.closing && item.tagName === 'button')) {
    if (!tagHasAttribute(tag.whole, 'type')) add(tagFinding('button-missing-type', tag.index, tag.whole))
  }

  if (/\.(?:html?|vue|svelte|astro|mdx)$/i.test(file) || file === '<memory>') {
    let previousHeading = null
    for (const tag of tags.filter(item => !item.closing && /^h[1-6]$/.test(item.tagName))) {
      const level = Number(tag.tagName[1])
      if (previousHeading !== null && level > previousHeading + 1) {
        add(tagFinding('skipped-heading-level', tag.index, tag.whole))
      }
      previousHeading = level
    }
  }

  const stack = []
  for (const tag of tags) {
    const { whole, tagName } = tag
    if (tag.closing) {
      const found = stack.map(item => item.tagName).lastIndexOf(tagName)
      if (found >= 0) stack.splice(found)
      continue
    }

    const classValue = whole.match(/\bclass(?:Name)?\s*=\s*(?:["']([^"']*)["']|\{([^}]*)\})/i)
    const isCard = /(?:^|[-_\s])card(?:$|[-_\s])|\bcard\b/i.test(classValue?.[1] ?? classValue?.[2] ?? '')
    if (isCard && stack.some(item => item.isCard)) add(tagFinding('nested-cards', tag.index, whole))

    const isVoid = /^(?:area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr)$/.test(tagName)
    if (!isVoid && !tag.selfClosing) stack.push({ tagName, isCard })
  }

  return findings.sort((a, b) => a.line - b.line || a.column - b.column || a.id.localeCompare(b.id))
}

function globRegex(pattern) {
  const normalized = pattern.replaceAll('\\', '/')
  let source = ''
  for (let index = 0; index < normalized.length; index += 1) {
    const character = normalized[index]
    if (character === '*' && normalized[index + 1] === '*') {
      if (normalized[index + 2] === '/') {
        source += '(?:.*/)?'
        index += 2
      } else {
        source += '.*'
        index += 1
      }
    } else if (character === '*') source += '[^/]*'
    else if (character === '?') source += '[^/]'
    else source += character.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp(`^${source}$`)
}

function matchesGlob(file, pattern) {
  const normalized = file.replaceAll('\\', '/')
  return globRegex(pattern).test(normalized) || globRegex(`**/${pattern}`).test(normalized)
}

export function filterFindings(findings, config = {}) {
  const ignoreRules = new Set(config.ignoreRules ?? [])
  const ignoreFiles = config.ignoreFiles ?? []
  const ignores = config.ignores ?? []

  return findings.filter(finding => {
    if (ignoreRules.has(finding.id)) return false
    if (ignoreFiles.some(pattern => matchesGlob(finding.file, pattern))) return false
    return !ignores.some(ignore => {
      if (ignore.rule && ignore.rule !== finding.id) return false
      if (ignore.file && !matchesGlob(finding.file, ignore.file)) return false
      if (ignore.contains && !finding.evidence.includes(ignore.contains)) return false
      return true
    })
  })
}

async function collectFiles(target, files) {
  const absolute = path.resolve(target)
  const details = await stat(absolute)
  if (details.isFile()) {
    if (SOURCE_EXTENSIONS.has(path.extname(absolute).toLowerCase())) files.push(absolute)
    return
  }
  if (!details.isDirectory()) return

  const entries = await readdir(absolute, { withFileTypes: true })

  for (const entry of entries) {
    if (entry.isDirectory() && EXCLUDED_DIRS.has(entry.name)) continue
    const child = path.join(absolute, entry.name)
    if (entry.isDirectory()) await collectFiles(child, files)
    else if (entry.isFile() && SOURCE_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) files.push(child)
  }
}

export async function scanPaths(targets, options = {}) {
  const cwd = options.cwd ?? process.cwd()
  const files = []
  for (const target of targets.length ? targets : ['.']) await collectFiles(path.resolve(cwd, target), files)

  const findings = []
  for (const absolute of [...new Set(files)].sort()) {
    const relative = path.relative(cwd, absolute) || path.basename(absolute)
    const text = await readFile(absolute, 'utf8')
    findings.push(...scanText(text, relative))
  }
  return filterFindings(findings, options.config)
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
    throw new Error(`Cannot read detector config ${configPath}: ${error.message}`)
  }
}

function summarize(findings) {
  const count = value => findings.filter(finding => finding.class === value).length
  return { total: findings.length, errors: count('error'), warnings: count('warning'), advisories: count('advisory') }
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    process.stdout.write('Usage: node detect-ui.mjs [--json] [--config path] [file-or-directory ...]\n')
    return
  }

  const config = await readConfig(args.configPath)
  const findings = await scanPaths(args.targets, { config })
  const summary = summarize(findings)

  if (args.json) {
    process.stdout.write(`${JSON.stringify({ summary, findings }, null, 2)}\n`)
  } else {
    for (const finding of findings) {
      process.stdout.write(`${finding.file}:${finding.line}:${finding.column} ${finding.severity} ${finding.class} ${finding.id} — ${finding.message}\n`)
    }
    process.stdout.write(`UI detector: ${summary.errors} error(s), ${summary.warnings} warning(s), ${summary.advisories} advisory finding(s).\n`)
  }

  if (summary.errors > 0) process.exitCode = 1
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
if (isMain) main().catch(error => {
  process.stderr.write(`${error.message}\n`)
  process.exitCode = 2
})
