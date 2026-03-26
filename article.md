# Stop Vibing, Start Shipping: A Spec-Driven Pipeline for AI-Powered Development

*How I built a 13-step workflow that turns a one-sentence idea into agent-executable tasks — with token budgets, multi-agent coordination, and build-evaluate-fix loops.*

---

Hey everyone, how's it going?

This article is me formalizing something that has been growing organically for a while. I didn't sit down one day and design a system. I started by fixing one thing, that led to fixing another, and before I knew it I had a concrete workflow. I'm writing this now because I think it's mature enough to be useful to other people.

Let me tell you how it started.

---

## Where This All Came From

The first real pain I felt was with code review. AI agents, when asked to evaluate their own work, are terrible at it. They confidently praise themselves. "The implementation looks great, all features are working correctly." Meanwhile, half the buttons don't do anything.

So I started by fixing that: I created a separate **code reviewer agent** whose only job was to be skeptical. That alone improved output quality significantly. But it exposed the next problem.

Once you have multiple agents — a builder, a reviewer, maybe a planner — they all need to know what's been done, what's in progress, and what comes next. And every agent was solving this problem in its own way: one creating a `TODO.md`, another a `plan.md`, another a `PROGRESS.md`. Context was scattering everywhere.

So I built **dagRobin** to fix that. A single external storage (think Redis-style) where all tasks live, with a standard format for tickets, dependency tracking, and state updates. Agents claim tasks, do the work, update the state. No more file sprawl.

Then I realized that without a shared prompt structure, agents were still duplicating logic and losing context between steps. So I formalized a **skills system** — a set of markdown files that encode exactly what each agent knows how to do, loaded into context when needed.

One thing led to another. What started as "let me fix the reviewer" turned into a full pipeline.

---

## The Problem with Vibe Coding

Here's how most developers use AI coding tools today: open Claude Code or Cursor, type a prompt, watch the magic happen, realize the magic produced something slightly wrong, type another prompt to fix it, watch it break something else, and repeat until you either ship something half-working or run out of patience — and tokens.

This is vibe coding. It's fun for toy projects and weekend prototypes. But if you want to ship something real — something with multiple features, proper architecture, and code that actually works when users click things — vibe coding falls apart fast.

I burned through sessions where the AI confidently produced applications that looked done on the surface but fell apart on the first interaction. Buttons that did nothing. API endpoints wired to nothing. Features that were technically present in the code but never connected to the UI.

The root problem isn't that AI is bad at coding. It's that AI is bad at planning. LLMs are powerful executors — give them a clear, detailed specification and they'll build it. But ask them to simultaneously figure out what to build, how to build it, and whether it works, and they'll confidently produce something mediocre.

The fix isn't to stop using AI. It's to stop asking AI to do everything at once.

---

## The Pipeline: 13 Steps in 3 Phases

The full process breaks down into three phases:

**Phase 1 — Ideation (Steps 1-5): Human-driven**
```
1. Brain-dump all ideas freely
2. Ask AI for stack and tool suggestions
3. Decide the stack
4. Define architecture decisions
5. Refine the idea into a system description
```

**Phase 2 — Specification (Steps 6-9): Human + AI collaboration**
```
6. Define the basic system flow
7. Read and iterate on AI outputs
8. Generate a development roadmap
9. Break the roadmap into mini-steps
```

**Phase 3 — Execution (Steps 10-13): AI-driven with human oversight**
```
10. Define folder and file structure
11. Register all tasks in a task system
12. Organize tasks with dependencies and priorities
13. Send to an orchestrator agent for implementation
```

The key insight: Phase 1 and 2 are where you spend 30% of the time but create 80% of the value. Rushing past them is exactly why vibe coding fails.

---

## Phase 1: From Idea to Decision (Steps 1-5)

### Step 1: Brain-Dump Freely

Start with a blank document and write everything. Requirements, half-formed ideas, constraints, the feature you're not sure about. Don't filter. Don't format. Just dump.

This raw material becomes the input for everything that follows. The messier and more complete it is, the better.

### Step 2: Strategic Analysis

Once you have the brain dump, feed it to an AI with a structured analysis framework. I use a prompt I call the **Deep Strategic Analysis & Solution Framework** ([gist](https://gist.github.com/afa7789/c50eedb387adc79e22901db225b08053)).

It forces the AI through six structured sections:

1. **Situation Assessment** — What's the current state? Root causes? Stakeholders? Constraints?
2. **Problem Definition** — What exactly are we solving? What's in scope? What does success look like?
3. **Strategic Options** — Generate 4-6 approaches. Evaluate pros, cons, risks. Recommend one.
4. **Implementation Roadmap** — Quick wins (0-30 days), short-term (1-3 months), medium-term (3-12 months), long-term (1-3 years).
5. **Risk & Mitigation** — What could go wrong? How bad? How to prevent it? Backup plans?
6. **Success Metrics** — KPIs, milestones, monitoring approach.

This turns a vague "I want to build X" into a structured understanding of the problem space. You often discover that what you thought was one problem is actually three, or that the obvious solution has a fatal constraint you hadn't considered.

### Steps 3-4: Stack and Architecture Decisions

The AI's analysis will suggest technology options. But **the human makes the final call**. The AI doesn't know your team's expertise, your deployment constraints, or your personal preferences for debugging at 2 AM.

Decide the stack. Decide the high-level architecture (monolith vs. services, database choice, auth strategy). Document these decisions. They become constraints for everything that follows.

Rust has become my go-to for tools in this pipeline. It compiles, generates a single binary, runs fast, no runtime dependencies. For CLIs and coordination tools that agents interact with constantly, that matters.

### Step 5: Iterative Prompt Refinement

Before generating the roadmap, I refine my description of the system using a meta-prompting technique. I use the **Expert Prompt Creator** ([gist](https://gist.github.com/afa7789/c50eedb387adc79e22901db225b08053)) — a prompt that creates an iterative loop:

1. The AI generates a prompt draft based on your description
2. It provides a self-critique of that draft (constructively harsh)
3. It asks 3 clarifying questions
4. You give feedback
5. Repeat until the prompt is sharp

The result is a polished, domain-specific prompt that captures exactly what you want. The quality of the roadmap in the next phase depends entirely on the quality of the prompt that generates it.

---

## Phase 2: From Description to Roadmap (Steps 6-9)

### Steps 6-7: Flow Definition and Iteration

Define the basic system flow. What happens when a user opens the app? What's the primary interaction loop? What data flows where?

Then — and this is critical — **read the AI's outputs multiple times and iterate**. The first draft is never right. The AI will include things you didn't ask for, miss things you assumed were obvious, and make architecture decisions you didn't authorize. Read carefully. Refine. Regenerate. This iteration loop is part of the process, not a failure of it.

### Step 8: The Roadmap (The Most Important Step)

I use the **Product Roadmap & Task Breakdown** prompt ([gist](https://gist.github.com/afa7789/c50eedb387adc79e22901db225b08053)) — the most important of the three prompts.

It enforces engineering standards as hard constraints:

| Principle | Expectation |
|---|---|
| **DRY** | No duplicated logic. Extract shared behavior. |
| **KISS** | Favor the simplest solution that works. |
| **SOLID** | All five principles, especially Dependency Inversion. |
| **TDD** | Tests written before or alongside implementation. |
| **Coverage >= 90%** | Unit + integration tests must meet this bar. |
| **Clean Architecture** | Database provider must be swappable via interfaces. |
| **CI/CD Pipeline** | lint -> format -> test -> coverage report. Fail fast. |

The output is a phased development roadmap:

- **Phase 1 — Foundation**: Environment, scaffold, folder structure, CI skeleton
- **Phase 2 — Domain**: Entities, interfaces, use cases, repository contracts
- **Phase 3 — Core**: Feature implementation in dependency order
- **Phase 4 — Testing**: Unit, integration, E2E tests, coverage enforcement
- **Phase 5 — Integration**: Wire everything, configure the full pipeline
- **Phase 6 — Refinement**: Performance, observability, documentation, launch

Each step follows a strict structure:

```
### [Phase X - Step N] Task Name

**Description:** What needs to be done and why.
**Prerequisites:** Steps that must be completed first.
**Folder / File Changes:** List of files to create/modify.
**Expected Output:** How to verify this step is complete.
**Engineering Notes:** Relevant patterns or constraints.
```

### Step 9: Mini-Steps

Break the roadmap into atomic tasks. Each task should be completable in 1-2 hours, have clear inputs and outputs, and be independently verifiable. If a task takes longer than 2 hours, it's too big — split it.

---

## Token Estimation: The Budget Meeting Before Construction

Here's something most developers skip: estimating how much the AI implementation will actually cost in tokens before starting.

You wouldn't start building a house without a cost estimate. But developers routinely send massive projects to AI agents with no idea whether they'll cost $5 or $500 in API calls.

I built an estimator tool that analyzes a project and produces intermediate results at each step:

- **`{slug}-paths.md`** — File inventory and metadata
- **`{slug}-plan.md`** — Analysis findings, duplicates, deprecations
- **`{slug}-steps.md`** — Step-by-step progress log
- **`{slug}-estimative.md`** — Final estimation

The estimation output looks like this:

```markdown
## Tokens Estimation
- Input tokens: ~45,000
- Reasoning tokens: ~120,000
- Output tokens: ~35,000

## Cost Estimation (USD)
- Claude Opus: $18.40
- With prompt caching: $11.20

## Issues Found
- Duplicates: 3 (shared validation logic)
- Deprecations: 1 (outdated auth library)
```

The power is in the feedback loop:

```
Estimate → Too expensive → Rearchitect → Re-estimate → Acceptable → Proceed
```

If Phase 3 alone would cost $80 in tokens, maybe you simplify the data model, reduce the feature count, or pick a lighter stack. The estimate gives you the information to make that decision *before* burning the tokens, not after.

---

## Phase 3: From Tasks to Agents (Steps 10-13)

### Step 10: Folder Structure

The AI proposes the project structure. The human approves. This happens before any code is written because a bad folder structure cascades into bad architecture.

### Steps 11-12: Register and Organize Tasks — Enter dagRobin

This is where the problem I mentioned at the beginning fully surfaces.

When you have multiple agents working in parallel, each one needs to know: what tasks exist, which ones are available right now (dependencies met), which ones are already claimed by another agent, and how to mark completion in a way that unblocks the next step.

The naive solution — markdown files — doesn't scale. Agents create `TODO.md`, `PROGRESS.md`, `PLAN.md`. State scatters. Agents lose track of what others are doing. You end up with duplicate work, missed dependencies, and a lot of token waste re-reading files that may or may not be up to date.

My hypothesis: **the bottleneck in multi-agent systems isn't just the agents. It's the infrastructure that organizes tasks, dependencies, state, and memory.**

To test this, I built [dagRobin](https://github.com/afa7789/dagRobin).

The core ideas:

- **A standard ticket format for TODOs/TASKS** — so every agent speaks the same language when reading and writing task state
- **External storage** (Redis-style) instead of scattered markdown files — O(1) access, no file search, no ambiguity about which file is the source of truth
- **An orchestrator** that reads from this storage and distributes tasks to agents
- **Agents update task state directly** in the storage — when they start, when they finish, when they're blocked
- **Dependencies structured as a DAG** (Directed Acyclic Graph) — the `ready` command returns only tasks whose dependencies are fully resolved
- **Claim-based coordination** — before an agent starts a task, it claims it. If another agent already claimed it, the claim fails. No duplicate work.

```bash
# Import tasks from the roadmap
dagRobin import .claude/tasks.yaml

# See what's ready to work on (pending, dependencies met)
dagRobin ready

# Agent claims a task before starting
dagRobin claim setup-auth --metadata "agent=builder"

# Agent marks it done when finished
dagRobin update setup-auth --status done

# Visualize the dependency graph
dagRobin graph
```

Tasks are defined in YAML with explicit dependencies:

```yaml
- id: setup-db
  title: Setup PostgreSQL and migrations
  status: Pending
  priority: 1
  deps: []
  files: [db/setup.sql, Cargo.toml]

- id: setup-auth
  title: Setup JWT authentication
  status: Pending
  priority: 2
  deps: [setup-db]
  files: [src/auth/mod.rs]

- id: api-users
  title: Implement user API endpoints
  status: Pending
  priority: 3
  deps: [setup-auth]
  files: [src/api/users.rs]
```

The benefits I'm validating:

- **Reduced token cost** — less context loss, agents don't re-read stale files to understand state
- **Better parallelization** — claim-based coordination prevents conflicts without manual coordination
- **Model switching mid-process** — because state lives externally, you can swap models between tasks without losing progress
- **Human observability** — you can see the full task graph at any point, not just infer it from scattered files
- **Agents as workflow workers** — treating agents more like workers in a workflow engine than isolated chat sessions

I'm still testing and validating this. But the early results suggest that the bottleneck in multi-agent systems really isn't primarily the model — it's orchestration, memory, and task management.

### Step 13: The Orchestrator

The orchestrator is the conductor. It reads from dagRobin, assesses project complexity, and selects the appropriate workflow:

**Simple** (bug fixes, single-file changes):
```
builder only → done
```

**Medium** (multi-file features, refactors):
```
architect → builder → code-reviewer → done
```

**Complex** (full applications, products from short prompts):
```
planner → architect → builder ↔ qa-evaluator (loop) → done
```

For Complex projects, the orchestrator runs a **build-evaluate-fix loop**: the builder implements a feature, the QA evaluator tests it, and if it fails, the builder fixes the specific issues and resubmits. Maximum 3 rounds per feature.

Before each major feature, the builder and QA evaluator negotiate a **sprint contract** — agreeing on what "done" looks like before any code is written:

```markdown
# Sprint Contract: User Authentication

## What will be built
- Login/register pages with form validation
- JWT token flow (issue, refresh, revoke)
- Protected route middleware

## Testable behaviors
1. User can register with email/password → receives JWT
2. User can login → receives JWT
3. Invalid credentials → 401 with error message
4. Expired token → 401, refresh endpoint issues new token
5. Protected route without token → redirects to login
```

The QA evaluator grades against this contract, not against vague expectations.

---

## The Multi-Agent Architecture

The pipeline uses six specialized agent roles:

| Agent | Responsibility | Does NOT |
|-------|---------------|----------|
| **Planner** | Expands short prompts into product specs (10-20 features, user stories, design direction) | Make technical decisions |
| **Architect** | Makes technical decisions, creates implementation plan | Write production code |
| **Builder** | Implements features based on the plan | Self-certify quality |
| **QA Evaluator** | Tests running app via Playwright, grades against weighted criteria | Implement fixes |
| **Code Reviewer** | Static code review with weighted scoring | Implement fixes |
| **Orchestrator** | Coordinates everything, manages the loop | Do the actual work |

### The Separation Principle

The single most impactful architectural decision: **the agent that builds should never be the agent that evaluates.**

This is where it all started for me. When you ask an AI to evaluate its own work, it confidently praises itself. "The implementation looks great, all features are working correctly." Meanwhile, half the buttons don't do anything.

Anthropic's research team independently documented the same finding: when asked to evaluate work they've produced, agents tend to respond by confidently praising the work — even when, to a human observer, the quality is obviously mediocre.

The fix is structural: a separate QA evaluator that is **skeptical by default**.

### Weighted Grading Criteria

The QA evaluator grades against five criteria, each with a hard fail threshold:

| Criterion | Weight | Threshold | What it measures |
|-----------|--------|-----------|-----------------|
| Feature Completeness | HIGH | 7/10 | Does every feature actually work end-to-end? |
| Product Depth | HIGH | 6/10 | Does the app feel like a real product or a demo? |
| Visual Design | MEDIUM | 5/10 | Coherent identity or generic template? |
| Code Quality | LOW | 5/10 | Console errors, crashes, unhandled exceptions |
| UX & Usability | MEDIUM | 6/10 | Can users complete tasks without guessing? |

**One failed criterion = overall FAIL.** No exceptions.

Feature Completeness and Product Depth are weighted highest because that's where AI agents fail most consistently. The AI reliably produces code that compiles and looks reasonable — but features are often stubbed, display-only, or disconnected from the backend.

### Anti-Leniency Calibration

The evaluator is explicitly prompted against the rationalization trap:

**Bad evaluation (too lenient):**
> "The dashboard looks great overall. Some buttons don't seem to work but the general layout is clean. Score: 8/10."

**Good evaluation (appropriately skeptical):**
> "Feature Completeness: 4/10 — FAIL. The 'Export CSV' button logs to console but doesn't trigger download. Filter dropdowns populate but selecting a filter doesn't update the table. Pagination buttons exist but clicking 'Next' doesn't change the data. Three of five interactive features are non-functional."

The code reviewer follows the same pattern with its own criteria: Correctness (threshold 7), Security (threshold 7), Completeness (threshold 6), Maintainability (threshold 5), Performance (threshold 5).

---

## The Supporting Tools

### dagRobin

[dagRobin](https://github.com/afa7789/dagRobin) is the coordination backbone. It's a Rust binary — zero overhead, no server, just a local SQLite database that can be backed by external storage. Tasks have IDs, dependencies, priorities, and metadata. The `ready` command returns only tasks whose dependencies are all met. The `claim` command prevents two agents from working on the same task.

For multi-agent parallel work, this is the difference between ordered execution and chaos.

### differ_helper

[differ_helper](https://github.com/afa7789/differ_helper) analyzes git diffs and extracts structured information: variables, functions, tests, imports. It identifies duplicates and deprecated dependencies automatically. I use it as part of the estimation pipeline and for code quality checks after implementation.

### RTK (Rust Token Killer)

[RTK](https://github.com/rtk-ai/rtk) is a CLI proxy that sits between the AI agent and shell commands, filtering output to reduce token consumption by 60-90%:

```
Without RTK: Claude --git status--> shell --> git (~2,000 tokens)
With RTK:    Claude --git status--> RTK  --> git (~200 tokens)
```

It uses smart filtering, grouping, truncation, and deduplication. When you're running multi-hour agent sessions, the savings compound fast.

---

## A Real Example: xmpp-start

To make this concrete: I used this pipeline to build [xmpp-start](https://github.com/afa7789/xmpp-start) — a native XMPP desktop messenger in pure Rust using the `iced` GUI framework.

**The idea:** A modern XMPP client, native, cross-platform, full XEP support, no Electron.

**Brain dump:** SASL login, contact roster, 1:1 chat with MAM history, group chat/MUC, message corrections, retractions, reactions, file upload, avatars, message carbons, stream management, presence indicators, dark/light theme, i18n, desktop notifications. A mess. Perfect.

**Strategic analysis:** Evaluated web app, Electron, GTK native, and iced/Rust. Recommended Rust + iced: single binary, real native performance, no runtime dependencies.

**Stack decision:** Rust + iced for GUI, tokio-xmpp + xmpp-parsers for protocol, tokio for async, rustls for TLS, SQLite via sqlx for storage, keyring for credentials, fluent-rs for i18n.

**Roadmap:** 6 phases, 40+ atomic tasks. Phase 1: scaffold, CI setup, basic XMPP connection. Phase 3: core XEP implementation (MAM, carbons, stream management).

**Token estimation:** ~$22 with Claude Sonnet. Acceptable. Proceed.

**Execution:** Tasks imported into dagRobin. Orchestrator assesses: Complex. Runs planner → architect → build-evaluate-fix loop. QA evaluator fails first sprint on Feature Completeness (typing indicators existed in code but never rendered in UI). Builder fixes. Second evaluation passes.

The result is what you see in the repository: a working messenger with support for dozens of XEPs, integration tests, CI/CD, i18n, privacy toggles, the whole thing.

---

## Alignment with Anthropic's Research

Anthropic recently published ["Harness design for long-running application development"](https://www.anthropic.com/engineering/harness-design), documenting their findings from building a multi-agent system for autonomous coding. Their conclusions independently validate the same patterns in this pipeline:

| Anthropic's Finding | This Pipeline's Implementation |
|---|---|
| Multi-agent architecture (planner → generator → evaluator) | planner → architect → builder → qa-evaluator |
| Separating the builder from the evaluator | Builder cannot self-certify; QA evaluator is skeptical by default |
| Sprint contracts before building | `.claude/SPRINT_CONTRACT.md` negotiated between builder and QA |
| Build-evaluate-fix loops (2-3 rounds) | Max 3 iterations with specific feedback each round |
| Complexity-based harness selection | Simple / Medium / Complex tiers with different agent compositions |
| Weighted grading criteria with hard fail thresholds | 5 criteria, each with minimum scores that trigger FAIL |
| Context resets with structured handoffs | dagRobin export/import for state persistence across sessions |

Their key observation resonates: "Every component in a harness encodes an assumption about what the model can't do on its own, and those assumptions are worth stress testing." As models improve, the pipeline should evolve — removing scaffolding that's no longer needed, adding new components that push further.

---

## What I Learned

**The spec is the product.** Spend 30% of your time on Steps 1 through 9. A precise spec with a mediocre implementation beats a vague spec with brilliant code. The spec is what you're actually building — the code is just the rendering.

**Never let the builder evaluate itself.** This is the single most impactful architectural decision. External evaluation with hard fail thresholds catches the exact bugs that self-evaluation misses: features that exist in code but don't work in practice.

**Token estimation is not optional.** It's the budget meeting before construction. Run it before every Complex project. If the estimate is too high, rearchitect — don't just hope it works out.

**The bottleneck in multi-agent systems isn't only the model.** It's the infrastructure around it — how tasks are organized, how state is shared, how dependencies are tracked, how agents hand off to each other. Treat agents like workers in a workflow engine, not like isolated chat sessions.

**Know when NOT to use this.** Single-file bug fixes, quick scripts, exploratory prototypes — just use the Simple tier. The full pipeline is for projects where getting it wrong is expensive. Match the process to the problem.

---

## Get Started

Everything is open source:

- **Skills system** (13 agent skills): [github.com/afa7789/skills](https://github.com/afa7789/skills)
- **dagRobin** (task coordination): [github.com/afa7789/dagRobin](https://github.com/afa7789/dagRobin)
- **differ_helper** (diff analysis): [github.com/afa7789/differ_helper](https://github.com/afa7789/differ_helper)
- **RTK** (token savings): [github.com/rtk-ai/rtk](https://github.com/rtk-ai/rtk)
- **xmpp-start** (real example): [github.com/afa7789/xmpp-start](https://github.com/afa7789/xmpp-start)
- **Prompt templates**: [gist](https://gist.github.com/afa7789/c50eedb387adc79e22901db225b08053)

The space of useful agent harnesses doesn't shrink as models improve. It moves. The interesting work is to keep finding the next combination that pushes further.

Stop vibing. Start shipping.

GL HF