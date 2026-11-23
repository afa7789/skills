#!/usr/bin/env node
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const USAGE = 'usage: node record.mjs --url <base> (--flow <file.json> | --explore --routes / /pricing [--max 30] [--all])\n'
  + '  [--start "npm run dev"] [--wait 60] [--out ux/flows/<name>] [--viewport 1440x900] [--headed] [--slowmo 0]';
const BOOLEAN = new Set(['explore', 'all', 'headed']);
const STEP_MS = 5000;
const SETTLE_MS = 800;
const CLICKABLE = 'a[href], button, [role=button], [role=link], [onclick]';
const DESTRUCTIVE = /delete|remove|logout|log out|sign out|pay|buy|purchase|excluir|apagar|sair|remover|pagar|comprar/i;

function parseArgs(argv) {
  const opt = { routes: [], wait: '60', viewport: '1440x900', slowmo: '0', max: '30' };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--/, '');
    if (BOOLEAN.has(key)) {
      opt[key] = true;
    } else if (key === 'routes') {
      while (argv[i + 1] !== undefined && !argv[i + 1].startsWith('--')) opt.routes.push(argv[++i]);
    } else {
      opt[key] = argv[++i];
    }
  }
  if (!opt.routes.length) opt.routes.push('/');
  return opt;
}

function die(msg) {
  console.error(msg);
  process.exit(2);
}

function loadDeps() {
  // Resolve from the project, not from this file: after sync the script lives under ~/.claude/skills.
  const req = createRequire(path.join(process.cwd(), 'package.json'));
  try {
    return req('playwright');
  } catch {
    return die('missing deps in this project: npm i -D playwright');
  }
}

function startServer(cmd) {
  // detached = own process group, so the kill reaches the real server behind `npm run`.
  const child = spawn(cmd, { shell: true, stdio: 'ignore', detached: true });
  const kill = () => {
    try { process.kill(-child.pid, 'SIGTERM'); } catch { /* already gone */ }
  };
  process.on('exit', kill);
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => process.exit(130));
  return child;
}

async function waitUp(url, seconds, child) {
  const deadline = Date.now() + seconds * 1000;
  do {
    try {
      await fetch(url);
      return true;
    } catch { /* not up yet */ }
    if (child?.exitCode != null) return false;
    await new Promise((r) => setTimeout(r, 500));
  } while (Date.now() < deadline);
  return false;
}

const slug = (route) => route.replace(/^\/+|\/+$/g, '').replace(/[^\w-]+/g, '-') || 'root';
const oneLine = (text) => String(text).split('\n')[0].replace(/\s+/g, ' ').trim().slice(0, 200);
const pad = (n) => String(n).padStart(2, '0');
const rel = (url) => { const u = new URL(url); return u.pathname + u.search + u.hash; };

async function openPage(browser, opt) {
  const [width, height] = opt.viewport.split('x').map(Number);
  // Popups record their own videos; keep them in a scratch dir that is removed at the end.
  const ctx = await browser.newContext({ viewport: { width, height }, recordVideo: { dir: path.join(opt.out, '.rec'), size: { width, height } } });
  const page = await ctx.newPage();
  const log = { errors: [], dialogs: [], popups: 0, status: 0 };
  page.on('pageerror', (e) => log.errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && log.errors.push(m.text()));
  page.on('dialog', (d) => { log.dialogs.push(`${d.type()} "${oneLine(d.message())}" dismissed`); d.dismiss().catch(() => {}); });
  page.on('popup', (p) => { log.popups++; p.close().catch(() => {}); });
  page.on('response', (r) => { if (r.request().isNavigationRequest() && r.frame() === page.mainFrame()) log.status = r.status(); });
  return { ctx, page, log };
}

async function closeAndSave({ ctx, page }, file) {
  const video = page.video();
  await ctx.close(); // the video is finalized on close
  fs.renameSync(await video.path(), file);
}

async function shoot(page, out, png) {
  await page.screenshot({ path: path.join(out, png), fullPage: true }).catch(() => {});
}

async function load(page, url, timeout) {
  const res = await page.goto(url, { waitUntil: 'load', timeout });
  // Late renders (data fetched after load) would pass for a click's DOM change; polling apps never idle.
  await page.waitForLoadState('networkidle', { timeout: STEP_MS }).catch(() => {});
  return res?.status() ?? 0;
}

// Candidates in priority order; the first one with a visible match wins.
async function pick(candidates, what) {
  const deadline = Date.now() + STEP_MS;
  do {
    for (const loc of candidates) {
      const hit = loc.locator('visible=true').first();
      if (await hit.count()) return hit;
    }
    await new Promise((r) => setTimeout(r, 100));
  } while (Date.now() < deadline);
  throw new Error(`no visible match for "${what}"`);
}

const ACTIONS = {
  async click(page, name) {
    const byPriority = [page.getByRole('button', { name }), page.getByRole('link', { name }), page.getByLabel(name), page.getByText(name)];
    await (await pick(byPriority, name)).click({ timeout: STEP_MS });
  },
  async fill(page, fields) {
    for (const [label, value] of Object.entries(fields)) {
      await (await pick([page.getByLabel(label), page.getByPlaceholder(label)], label)).fill(String(value), { timeout: STEP_MS });
    }
  },
  press: (page, key) => page.keyboard.press(key),
  expect(page, want) {
    if (want?.url) return page.waitForURL((u) => u.href.includes(want.url), { timeout: STEP_MS });
    return pick([page.getByText(String(want))], want);
  },
  async goto(page, route, base) {
    const status = await load(page, new URL(route, base).href, STEP_MS);
    if (status >= 400) throw new Error(`HTTP ${status}`);
  },
  wait: (page, ms) => page.waitForTimeout(Number(ms)),
};

function describe(action, arg) {
  if (action === 'fill') return Object.keys(arg).join(', '); // labels only, never the values
  return arg?.url ? `url ${arg.url}` : String(arg);
}

async function runStep({ page, log }, n, step, opt) {
  const [action, arg] = Object.entries(step)[0];
  const e0 = log.errors.length;
  const d0 = log.dialogs.length;
  const run = Object.hasOwn(ACTIONS, action) ? ACTIONS[action] : async () => { throw new Error(`unknown action: ${action}`); };
  const failed = await run(page, arg, opt.url).then(() => '', (e) => oneLine(e.message));
  await page.waitForTimeout(300);
  await page.waitForLoadState('load', { timeout: STEP_MS }).catch(() => {});
  const png = `step-${pad(n)}-${action}.png`;
  await shoot(page, opt.out, png);
  const notes = [...log.errors.slice(e0), ...log.dialogs.slice(d0)].map(oneLine);
  const consoleCount = log.errors.length - e0;
  // Same bar as ux/shoot.mjs and explore mode: a console error fails the step.
  const reason = failed || (consoleCount ? `console error: ${oneLine(log.errors[e0])}` : '');
  return { n: pad(n), action, target: describe(action, arg), ok: !reason, reason, url: rel(page.url()), console: consoleCount, png, notes };
}

function printStep(s) {
  console.log(`${s.n} ${s.action} "${s.target}" ${s.ok ? 'ok' : 'FAIL'} url=${s.url} console=${s.console} ${s.png}`);
  for (const note of [s.reason, ...s.notes].filter(Boolean)) console.log(`  ${note}`);
}

function writeFlowMd(opt, name, steps, pass) {
  const cell = (v) => String(v).replace(/\|/g, '\\|');
  const rows = steps.map((s) => `| ${s.n} | ${s.action} | ${cell(s.target)} | ${s.ok ? 'ok' : cell(`FAIL: ${s.reason}`)} | ${cell(s.url)} | ${s.console} | [${s.png}](${s.png}) |`);
  const notes = steps.flatMap((s) => s.notes.map((m) => `- step ${s.n}: ${m}`));
  const md = [`# Flow: ${name}`, '', `- Result: ${pass ? 'PASS' : 'FAIL'}`, `- Date: ${new Date().toISOString()}`,
    `- Viewport: ${opt.viewport}`, `- Base URL: ${opt.url}`, '- Video: [flow.webm](flow.webm)', '',
    '| # | Action | Target | Result | URL | Console | Screenshot |', '|---|---|---|---|---|---|---|', ...rows];
  if (notes.length) md.push('', '## Console errors and dialogs', '', ...notes);
  fs.writeFileSync(path.join(opt.out, 'flow.md'), `${md.join('\n')}\n`);
}

async function runFlow(browser, opt) {
  const flow = JSON.parse(fs.readFileSync(opt.flow, 'utf8'));
  const name = flow.name ?? path.basename(opt.flow, '.json');
  opt.out ??= path.join('ux/flows', name);
  fs.mkdirSync(opt.out, { recursive: true });
  const session = await openPage(browser, opt);
  const steps = [];
  // The start navigation is step 00, so 01..N match the JSON steps.
  for (const step of [{ goto: flow.start ?? '/' }, ...flow.steps]) {
    steps.push(await runStep(session, steps.length, step, opt));
    printStep(steps.at(-1));
    if (!steps.at(-1).ok) break;
  }
  const video = path.join(opt.out, 'flow.webm');
  await closeAndSave(session, video);
  const pass = steps.every((s) => s.ok);
  writeFlowMd(opt, name, steps, pass);
  console.log(`FLOW ${pass ? 'PASS' : 'FAIL'} ${name} video=${video}`);
  return pass;
}

function collect(page, all) {
  return page.locator(CLICKABLE).evaluateAll((els) => {
    const skipOf = (el) => {
      if (el.disabled) return 'disabled';
      const href = el.getAttribute('href');
      if (href === null) return '';
      const u = new URL(href, location.href);
      if (u.protocol === 'mailto:' || u.protocol === 'tel:') return u.protocol.slice(0, -1);
      return u.protocol.startsWith('http') && u.origin !== location.origin ? 'external' : '';
    };
    const nameOf = (el) => el.getAttribute('aria-label') || el.innerText || el.value || el.title || el.querySelector('img')?.alt || '';
    const visible = (el) => el.checkVisibility() && el.getClientRects().length > 0;
    // `i` indexes the full list, so the element can be found again after a fresh load.
    return els.map((el, i) => ({ i, el })).filter((c) => visible(c.el))
      .map(({ i, el }) => ({ i, skip: skipOf(el), name: nameOf(el).replace(/\s+/g, ' ').trim().slice(0, 60) }));
  }).then((items) => items.map((c) => ({ ...c, skip: c.skip || (!all && DESTRUCTIVE.test(c.name) ? 'destructive' : '') })));
}

function classify(before, after, log, clickError) {
  if (clickError || log.errors.length > before.errors || log.status >= 400) return 'ERROR';
  if (log.popups > before.popups) return 'popup';
  if (after.url.replace(/#$/, '') !== before.url.replace(/#$/, '')) return 'nav'; // a bare "#" link stays DEAD
  if (log.dialogs.length > before.dialogs || after.open > before.open) return 'dialog';
  return after.mutations > 0 ? 'change' : 'DEAD';
}

async function clickOne({ page, log }, routeUrl, item) {
  await load(page, routeUrl);
  const dialogs = page.locator('[role=dialog], dialog[open]').locator('visible=true');
  const before = { url: page.url(), errors: log.errors.length, dialogs: log.dialogs.length, popups: log.popups, open: await dialogs.count() };
  log.status = 0;
  await page.evaluate(() => {
    window.__mutations = 0;
    new MutationObserver(() => window.__mutations++).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
  });
  const clickError = await page.locator(CLICKABLE).nth(item.i).click({ timeout: STEP_MS }).then(() => '', (e) => oneLine(e.message));
  await page.waitForTimeout(SETTLE_MS);
  // After a navigation the observer and its context are gone; that case is already `nav`.
  const after = { url: page.url(), mutations: await page.evaluate(() => window.__mutations ?? 0).catch(() => 0), open: await dialogs.count().catch(() => 0) };
  return { kind: classify(before, after, log, clickError), reason: clickError || log.errors.slice(before.errors).map(oneLine)[0] };
}

async function exploreRoute(browser, opt, route, tally) {
  const session = await openPage(browser, opt);
  const routeUrl = new URL(route, opt.url).href;
  const status = await load(session.page, routeUrl);
  if (status >= 400) {
    console.log(`${route} load ERROR status=${status}`);
    tally.ERROR++;
  }
  let clicks = 0;
  for (const item of await collect(session.page, opt.all)) {
    if (item.skip) {
      console.log(`${route} "${item.name}" skipped (${item.skip})`);
      continue;
    }
    if (clicks >= Number(opt.max)) break;
    const r = await clickOne(session, routeUrl, item);
    const png = `${slug(route)}-${pad(++clicks)}.png`;
    await shoot(session.page, opt.out, png);
    console.log(`${route} "${item.name}" ${r.kind} url=${rel(session.page.url())} ${png}`);
    if (r.reason) console.log(`  ${r.reason}`);
    tally[r.kind] = (tally[r.kind] ?? 0) + 1;
  }
  tally.clicks += clicks;
  await closeAndSave(session, path.join(opt.out, `${slug(route)}.webm`));
}

async function runExplore(browser, opt) {
  opt.out ??= 'ux/flows/explore';
  fs.mkdirSync(opt.out, { recursive: true });
  const tally = { clicks: 0, DEAD: 0, ERROR: 0 };
  for (const route of opt.routes) await exploreRoute(browser, opt, route, tally);
  const pass = tally.DEAD + tally.ERROR === 0;
  console.log(`EXPLORE ${pass ? 'PASS' : 'FAIL'} ${tally.clicks} clicks ${tally.DEAD} dead ${tally.ERROR} errors`);
  return pass;
}

async function main() {
  const opt = parseArgs(process.argv.slice(2));
  if (!opt.url || (!opt.flow && !opt.explore)) die(USAGE);
  const { chromium } = loadDeps();
  const child = opt.start ? startServer(opt.start) : null;
  if (!(await waitUp(opt.url, opt.start ? Number(opt.wait) : 0, child))) die(`not reachable: ${opt.url}`);
  const browser = await chromium.launch({ headless: !opt.headed, slowMo: Number(opt.slowmo) });
  const pass = opt.flow ? await runFlow(browser, opt) : await runExplore(browser, opt);
  await browser.close();
  fs.rmSync(path.join(opt.out, '.rec'), { recursive: true, force: true });
  process.exit(pass ? 0 : 1);
}

main().catch((e) => die(`record error: ${e.message}`));
