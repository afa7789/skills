# Flow-recording audit

How real users complete real tasks, with evidence. Observe before changing anything: record the
current state first, propose improvements second, implement only when that is also asked.

## Rules

- Read the docs and code first: product, user types, pages, main tasks. Then walk every flow in a
  browser as a user would; never infer a flow from code alone.
- Test environment and fake data only. Never record passwords, tokens or personal data; redact
  them in shots and video. Record the browser context, never the whole desktop.
- Keep facts, evidence, inferences and recommendations apart. Never invent a result or call
  something validated that you did not run.
- Missing environment, test credentials or recorder: write down exactly what was missing. Never
  replace it with an imagined flow.

## 1. Pick flows

Tasks that represent real use: discover the service, sign up, sign in, complete the main action,
pay or submit, recover from an error, change settings, sign out. Include visitor and signed-in
flows when both exist. Per flow: one happy path plus every error, empty, loading, validation and
cancel state you can reproduce.

## 2. Record

A video per flow and a screenshot at every meaningful screen or state change. Without video, keep
sequential screenshots and note the limitation.

```js
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, recordVideo: { dir: os.tmpdir() } });
const page = await ctx.newPage();
const dir = `ux-review/flows/${id}`;
await page.screenshot({ path: `${dir}/screenshots/step-01.png`, fullPage: true }); // after each step
const video = page.video();
await ctx.close(); // the video is finalized on close
await video.saveAs(`${dir}/video.webm`);
```

## 3. `ux-review/flows/<id>/flow.md`

- ID, task name, user profile, goal, done criterion.
- Timestamp, viewport, browser, environment.
- Preconditions: start route, session, test data.
- Steps in order: action, visible response, URL and UI state, relative link to its screenshot.
- Friction: hesitations, detours, clicks with no response, unclear messages, dead ends, recovery.
- Result: completed, completed with difficulty, blocked or not tested, and why.

## 4. Deliverables

1. Screen and state inventory: page, purpose, access, visible states.
2. Current flow map (Mermaid or numbered list) with branches, errors and return points.
3. One `flow.md` per journey with its screenshots and video.
4. Findings: evidence (step and screenshot), impact on the task, estimated reach (marked as an
   estimate), severity.
5. Prioritized fixes: observed problem, change, reason, verifiable acceptance check, risk.
6. Gaps: flows and states not observed, and what is needed to observe them.

Fix task blockers and data loss first, then clarity, accessibility and consistency, visual polish
last. Tie every proposal to evidence and the user's goal, not to taste.
