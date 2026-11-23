#!/usr/bin/env node
// Not *.test.mjs on purpose: it installs Playwright, so it must not gate every sync.
import { execSync, spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SHOOT = fileURLToPath(new URL('../scripts/shoot.mjs', import.meta.url));
const TEXT = '<h1>Fixture page</h1><p>This page has enough readable text to count.</p>';
const html = (main) => `<!doctype html><html lang="en"><head><title>Fixture</title></head><body><main>${main}</main></body></html>`;
const PAGES = {
  '/good': html(`${TEXT}<form><label for="e">Email</label><input id="e" type="email"><button>Send</button></form>`),
  '/console': html(`${TEXT}<script>throw new Error('boom')</script>`),
  '/axe': html(`${TEXT}<input type="text">`),
  '/empty': html(''),
};
const CASES = [
  ['/good', 0, /console=0 axe=0 empty=no/],
  ['/console', 1, /console=[1-9]\d* axe=0 empty=no/],
  ['/axe', 1, /console=0 axe=[1-9]\d* empty=no/],
  ['/empty', 1, /console=0 axe=0 empty=yes/],
];

function run(args, cwd) {
  return new Promise((resolve) => {
    const p = spawn(process.execPath, [SHOOT, ...args], { cwd });
    let out = '';
    p.stdout.on('data', (d) => (out += d));
    p.stderr.on('data', (d) => (out += d));
    p.on('close', (code) => resolve({ code, out }));
  });
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

async function isDown(url) {
  for (let i = 0; i < 20; i++) {
    if (await fetch(url).then(() => false, () => true)) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

let failures = 0;
function check(name, ok, out = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`);
  if (!ok) {
    failures++;
    console.log(out.replace(/^/gm, '    '));
  }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-shoot-'));
const bare = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-shoot-bare-'));
fs.writeFileSync(path.join(dir, 'package.json'), '{"private":true}\n');
execSync('npm i -D playwright@1 @axe-core/playwright@4 --silent', { cwd: dir, stdio: 'inherit' });
execSync('npx playwright install chromium', { cwd: dir, stdio: 'inherit' });

const server = http.createServer((req, res) => {
  const body = PAGES[req.url];
  res.writeHead(body ? 200 : 404, { 'content-type': 'text/html' });
  res.end(body ?? '');
});
const base = `http://127.0.0.1:${await listen(server)}`;

for (const [route, code, line] of CASES) {
  const r = await run(['--url', base, '--routes', route, '--out', 'shots'], dir);
  const lines = r.out.split('\n').filter((l) => l.startsWith(`${route} `));
  const slug = route.slice(1);
  const pngs = ['390x844', '1440x900'].every((s) => fs.existsSync(path.join(dir, 'shots', `${slug}__${s}.png`)));
  check(`${route} exit=${code}`, r.code === code && lines.length === 2 && lines.every((l) => line.test(l)) && pngs, r.out);
}
server.close();

const missing = await run(['--url', base, '--routes', '/good'], bare);
check('missing deps exit=2', missing.code === 2 && missing.out.includes('npm i -D playwright @axe-core/playwright'), missing.out);

const free = http.createServer();
const port = await listen(free);
free.close();
fs.writeFileSync(path.join(dir, 'serve.mjs'),
  `import http from 'node:http';\nhttp.createServer((q, s) => s.writeHead(200, { 'content-type': 'text/html' }).end(${JSON.stringify(PAGES['/good'])})).listen(${port});\n`);
const url = `http://127.0.0.1:${port}`;
// npm exec puts the server one process below the shell, like `npm run dev`: the kill must reach it.
const started = await run(['--url', url, '--routes', '/', '--start', 'npm exec -- node serve.mjs', '--out', 'shots'], dir);
check('--start serves, then is killed', started.code === 0 && (await isDown(url)), started.out);

fs.rmSync(dir, { recursive: true, force: true });
fs.rmSync(bare, { recursive: true, force: true });
console.log(failures ? `E2E FAIL ${failures}` : 'E2E PASS');
process.exit(failures ? 1 : 0);
