#!/usr/bin/env node
// Not *.test.mjs on purpose: it installs Playwright, so it must not gate every sync.
import { execSync, spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RECORD = fileURLToPath(new URL('../scripts/record.mjs', import.meta.url));
const html = (body) => `<!doctype html><html lang="en"><head><title>Fixture</title><link rel="icon" href="data:,"></head><body>${body}</body></html>`;
const PAGES = {
  '/': html(`<h1>Home</h1><a href="/two">Go two</a>
    <button onclick="this.textContent = 'Changed'">Change me</button>
    <button>Do nothing</button><button disabled>Disabled</button>
    <button onclick="throw new Error('boom')">Broken</button>
    <button onclick="document.title = 'gone'">Delete account</button>`),
  '/two': html('<h1>Two</h1>'),
  '/form': html(`<form onsubmit="event.preventDefault(); document.getElementById('msg').textContent = 'Welcome'">
    <label for="e">Email</label><input id="e" type="email"><button>Submit</button></form><p id="msg"></p>`),
};
const FLOWS = {
  'signup.json': { name: 'signup', start: '/form', steps: [{ fill: { Email: 'a@b.c' } }, { click: 'Submit' }, { expect: 'Welcome' }, { expect: { url: '/form' } }] },
  'missing.json': { name: 'missing', start: '/form', steps: [{ expect: 'Nope' }] },
  'broken.json': { name: 'broken', start: '/', steps: [{ click: 'Broken' }] },
};

function run(args, cwd) {
  return new Promise((resolve) => {
    const p = spawn(process.execPath, [RECORD, ...args], { cwd });
    let out = '';
    p.stdout.on('data', (d) => (out += d));
    p.stderr.on('data', (d) => (out += d));
    p.on('close', (code) => resolve({ code, out }));
  });
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

let failures = 0;
function check(name, ok, out = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`);
  if (!ok) {
    failures++;
    console.log(out.replace(/^/gm, '    '));
  }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'visual-test-'));
const bare = fs.mkdtempSync(path.join(os.tmpdir(), 'visual-test-bare-'));
fs.writeFileSync(path.join(dir, 'package.json'), '{"private":true}\n');
execSync('npm i -D playwright@1 --silent', { cwd: dir, stdio: 'inherit' });
// A no-op when the browser and ffmpeg are already cached.
execSync('npx playwright install chromium', { cwd: dir, stdio: 'inherit' });
for (const [file, flow] of Object.entries(FLOWS)) fs.writeFileSync(path.join(dir, file), JSON.stringify(flow));

const server = http.createServer((req, res) => {
  const body = PAGES[req.url];
  res.writeHead(body ? 200 : 404, { 'content-type': 'text/html' });
  res.end(body ?? '');
});
const base = `http://127.0.0.1:${await listen(server)}`;
const exists = (...p) => fs.existsSync(path.join(dir, ...p));

const pass = await run(['--url', base, '--flow', 'signup.json'], dir);
const video = path.join(dir, 'ux/flows/signup/flow.webm');
const pngs = ['00-goto', '01-fill', '02-click', '03-expect', '04-expect'].every((s) => exists('ux/flows/signup', `step-${s}.png`));
check('flow fill+submit+expect exit=0', pass.code === 0 && /^FLOW PASS signup /m.test(pass.out) && /^01 fill "Email" ok url=\/form console=0/m.test(pass.out)
  && fs.existsSync(video) && fs.statSync(video).size > 0 && pngs && exists('ux/flows/signup/flow.md') && !exists('ux/flows/signup/.rec'), pass.out);

const fail = await run(['--url', base, '--flow', 'missing.json'], dir);
check('flow missing text exit=1 at that step', fail.code === 1 && /^01 expect "Nope" FAIL /m.test(fail.out) && /^FLOW FAIL missing /m.test(fail.out), fail.out);

const broken = await run(['--url', base, '--flow', 'broken.json'], dir);
check('flow console error fails its step', broken.code === 1 && /^01 click "Broken" FAIL url=\/ console=1 /m.test(broken.out) && /^FLOW FAIL broken /m.test(broken.out), broken.out);

const ex = await run(['--url', base, '--explore', '--routes', '/', '--out', 'explore'], dir);
const lines = [/^\/ "Go two" nav url=\/two /m, /^\/ "Change me" change /m, /^\/ "Do nothing" DEAD /m, /^\/ "Broken" ERROR /m,
  /^\/ "Disabled" skipped \(disabled\)/m, /^\/ "Delete account" skipped \(destructive\)/m,/^EXPLORE FAIL 4 clicks 1 dead 1 errors/m];
check('explore / exit=1 with nav, change, DEAD, ERROR, skipped', ex.code === 1 && lines.every((re) => re.test(ex.out)) && exists('explore/root.webm'), ex.out);
server.close();

const missing = await run(['--url', base, '--explore'], bare);
check('missing playwright exit=2', missing.code === 2 && missing.out.includes('npm i -D playwright'), missing.out);

fs.rmSync(dir, { recursive: true, force: true });
fs.rmSync(bare, { recursive: true, force: true });
console.log(failures ? `E2E FAIL ${failures}` : 'E2E PASS');
process.exit(failures ? 1 : 0);
