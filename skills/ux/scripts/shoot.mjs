#!/usr/bin/env node
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const USAGE = 'usage: node shoot.mjs --url <base> --routes / /login [--start "npm run dev"] [--wait 60] [--out ux/shots/before]';
const VIEWPORTS = [[390, 844], [1440, 900]];
const MAX_DETAIL = 3;

function parseArgs(argv) {
  const opt = { routes: [], wait: '60', out: 'ux/shots/before' };
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i].replace(/^--/, '');
    if (key === 'routes') {
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
    return { chromium: req('playwright').chromium, AxeBuilder: req('@axe-core/playwright').default };
  } catch {
    return die('missing deps in this project: npm i -D playwright @axe-core/playwright');
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

function slug(route) {
  return route.replace(/^\/+|\/+$/g, '').replace(/[^\w-]+/g, '-') || 'root';
}

function oneLine(text) {
  return String(text).replace(/\s+/g, ' ').trim().slice(0, 200);
}

async function shootScreen(browser, AxeBuilder, base, route, [w, h], out) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, reducedMotion: 'reduce' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  try {
    await page.goto(new URL(route, base).href, { waitUntil: 'load' });
    // Polling apps never reach network idle; settle for what loaded.
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await page.evaluate(() => document.fonts.ready.then(() => 0));
  } catch (e) {
    errors.push(`navigation: ${e.message}`);
  }
  const png = path.join(out, `${slug(route)}__${w}x${h}.png`);
  await page.screenshot({ path: png, fullPage: true, animations: 'disabled' }).catch((e) => errors.push(`screenshot: ${e.message}`));
  const axe = await new AxeBuilder({ page }).analyze()
    .then((r) => r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical'))
    .catch((e) => [{ id: `axe-error: ${oneLine(e.message)}` }]);
  const empty = await page.evaluate(() => {
    const root = document.querySelector('main') ?? document.body;
    return root.innerText.trim().length < 20 && !root.querySelector('img, canvas, svg');
  }).catch(() => true);
  await ctx.close();
  return { route, size: `${w}x${h}`, errors, axe, empty, png };
}

function report(s) {
  const fail = s.errors.length > 0 || s.axe.length > 0 || s.empty;
  console.log(`${s.route} ${s.size} console=${s.errors.length} axe=${s.axe.length} empty=${s.empty ? 'yes' : 'no'} ${s.png}`);
  if (!fail) return false;
  for (const v of s.axe.slice(0, MAX_DETAIL)) console.log(`  axe ${v.id}${v.impact ? ` (${v.impact})` : ''}`);
  for (const m of s.errors.slice(0, MAX_DETAIL)) console.log(`  console ${oneLine(m)}`);
  return true;
}

async function main() {
  const opt = parseArgs(process.argv.slice(2));
  if (!opt.url) die(USAGE);
  const { chromium, AxeBuilder } = loadDeps();
  const child = opt.start ? startServer(opt.start) : null;
  if (!(await waitUp(opt.url, opt.start ? Number(opt.wait) : 0, child))) die(`not reachable: ${opt.url}`);
  fs.mkdirSync(opt.out, { recursive: true });
  const browser = await chromium.launch();
  let failed = 0;
  let total = 0;
  for (const route of opt.routes) {
    for (const vp of VIEWPORTS) {
      total++;
      if (report(await shootScreen(browser, AxeBuilder, opt.url, route, vp, opt.out))) failed++;
    }
  }
  await browser.close();
  console.log(`SHOOT ${failed ? 'FAIL' : 'PASS'} ${total} screens`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => die(`shoot error: ${e.message}`));
