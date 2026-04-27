# Agents & Skills for Claude Code

![imagem de skills](resources/image.png)

This repository contains **Agents** and **Skills** for Claude Code and OpenCode. Built with [dagRobin](https://github.com/afa7789/dagRobin) and [differ_helper](https://github.com/afa7789/differ_helper).

## Agents vs Skills

| | Agents | Skills |
|---|---|---|
| **What** | Autonomous executors with tool access | Knowledge/methodology injected as context |
| **How** | Invoked as subagents via the Agent tool | Loaded via slash commands |
| **Location** | `~/.claude/agents/<name>.md` | `~/.claude/skills/<name>/SKILL.md` |
| **Format** | Single `.md` with tools/model in frontmatter | `SKILL.md` inside a directory |

## Available Agents (7)

| Agent | Model | Purpose |
|-------|-------|---------|
| **orchestrator** | opus | Multi-agent pipeline coordinator. Assesses complexity, creates task DAGs, dispatches agents, manages build-evaluate-fix loops |
| **architect** | sonnet | Research & planning. Explores codebases, designs architecture, creates implementation plans |
| **builder** | sonnet | Core implementation. TDD, debugging, sprint contracts, code changes |
| **qa-evaluator** | sonnet | Live Playwright testing. Grades builds against weighted criteria, skeptical by default |
| **code-reviewer** | sonnet | Weighted code review with scored verdicts. Two-stage: spec compliance then quality |
| **project-manager** | sonnet | Task coordination via dagRobin. Decomposes specs into tasks with full context |
| **summarizer-auditor** | haiku | Audits .claude/ folders. Creates SUMMARY.md and AUDIT.md |

## Available Skills (5)

| Skill | Purpose |
|-------|---------|
| **reader** | Advanced proofreading methodology. Focuses on flow, succinctness, duplicate detection, and explicit meaning. |
| **prompt-refiner** | Iterative refinement methodology. Sharpens vague ideas into specific prompts before sending to architect |
| **differ-helper** | Git diff analysis workflow: extract entities, find duplicates, check deprecations |
| **estimator** | Token counting methodology, cost estimation formulas, pricing tables |
| **peer-review** | Multi-agent peer review panel. Coordinates specialist agents to analyze, rewrite, and consolidate code/documents |
| **multi-agent-loop** | Infinite execution system. dagRobin-first, gap detection, decision escalation. Coordinates all agents via conversation context |

## For Agents

> This section is written for AI agents (and humans onboarding fast). It tells you **which agent/skill to invoke for which phase**, and **where to enter the pipeline** based on what you already have.

### Phases & Entry Points

You don't have to start from the orchestrator. Each agent maps to a phase of the workflow — pick the entry point that matches what you already have in hand.

### Phases

| Phase | Goal | Agent | Skill (optional) |
|-------|------|-------|------------------|
| **0. Refine** | Sharpen a vague idea into a specific prompt | — | `prompt-refiner` |
| **1. Discovery** | Explore an unknown codebase, answer "how does X work?" | `architect` (research mode) | — |
| **2. Planning** | Turn a spec into a technical plan + task graph | `architect` → `project-manager` | `estimator` (cost/tokens) |
| **3. Implementation** | Write the code (TDD, debug, sprint contracts) | `builder` | `differ-helper` (after diffs) |
| **4. Validation** | Live-test the build against weighted criteria | `qa-evaluator` | — |
| **5. Review** | Scored code review, multi-perspective critique | `code-reviewer` | `peer-review`, `reader` |
| **6. Audit** | Inventory `.claude/` folders, find drift | `summarizer-auditor` | — |
| **∞. Coordinate** | Run multiple phases / agents in parallel | `orchestrator` | `multi-agent-loop` |

### Pick your entry point

| What you already have | Start with | Skip |
|-----------------------|------------|------|
| A vague idea | `prompt-refiner` skill | — |
| A clear spec but no plan | `architect` | refine |
| A plan, no tasks yet | `project-manager` | refine, plan |
| A plan **and** tasks in dagRobin | `builder` (claim and go) | everything before |
| Code already written, want feedback | `code-reviewer` or `peer-review` skill | everything before |
| Code that needs to be tested live | `qa-evaluator` | review |
| Many independent tasks at once | `orchestrator` | nothing — it dispatches |
| Resuming after a context wipe | `orchestrator` ("check dagRobin and continue") | — |

### When NOT to use the orchestrator

The orchestrator is just a **dispatcher** — it assesses complexity and fans out work to other agents. If you already know which agent you need, call it directly. Skip the orchestrator when:

- You have one focused task → call `builder` directly.
- You only need a plan, not implementation → call `architect` directly.
- You only want a review of existing code → call `code-reviewer` or load `peer-review`.
- You're refining a prompt before any work starts → load `prompt-refiner`.

Use the orchestrator when you have **N independent tasks for N agents**, or when you're not sure which phase you're in and want it figured out for you.

### Common scenarios

**"I have a vague idea"**
```
Load the prompt-refiner skill. I want to build something with X and Y.
```

**"I want a plan, not code yet"**
```
Use the architect agent to design a plan for <feature>. Don't implement.
```

**"I have a plan, just build it"**
```
Use the builder agent. The plan is in PLAN.md / .claude/PLAN.md.
```

**"Review what I just wrote"**
```
Use the code-reviewer agent on the current branch.
```
or
```
Load the peer-review skill and run a panel on the current diff.
```

**"Test it like a user would"**
```
Use the qa-evaluator agent against <criteria>.
```

**"Estimate cost before I start"**
```
Load the estimator skill. Estimate tokens/cost for <project description>.
```

**"Full project from scratch, drive everything"**
```
Use the orchestrator agent. Build <full description>.
```

**"Resume after tokens ran out"**
```
Use the orchestrator agent. Check dagRobin for pending tasks and continue.
```

## dagRobin Integration

All agents coordinate through **dagRobin** for multi-agent task management. The workflow varies by complexity:

### Complex Projects (full pipeline)
```
orchestrator assesses -> Complex
  1. architect -> product spec + technical plan
  2. project-manager -> dagRobin tasks
  3. builder <-> qa-evaluator (build-evaluate-fix loop, max 3 rounds)
  4. code-reviewer -> final review
```

### Medium Projects (architect + builder + review)
```
orchestrator assesses -> Medium
  1. architect -> plan
  2. builder -> implements
  3. code-reviewer -> scored review
```

### Simple Tasks (builder only)
```
orchestrator assesses -> Simple
  1. builder -> fix and done
```

## Usage

### Invoke an Agent

Agents are invoked automatically by Claude Code when matching tasks are detected, or explicitly:

```
Use the orchestrator agent to build a Rust API with JWT auth and PostgreSQL.
```

```
Use the code-reviewer agent to review the latest changes.
```

### Load a Skill

Skills inject methodology into the conversation:

```
Load the estimator skill and estimate the token cost of this project.
```

```
Load the differ-helper skill and analyze the current diff.
```

### Multi-Agent Workflow

Load the multi-agent-loop skill for full workload execution:

```
Load the multi-agent-loop skill.

Build a full-stack app with auth, database, and real-time updates.
```

### Peer Review Panel

Load the peer-review skill to get multiple perspectives on code:

```
Load the peer-review skill and review the current changes.
```

### Example: Full Project from Scratch

```
Use the orchestrator agent.

Build a recipe manager app with meal planning and AI suggestions.
```

The orchestrator will:
1. Assess complexity -> Complex
2. Launch architect -> product spec + technical plan
3. Create dagRobin tasks
4. For each feature: sprint contract -> build -> QA evaluate -> fix loop
5. Final review -> done

### Example: Resume After Tokens Ran Out

```
Use the orchestrator agent.

Check dagRobin for pending tasks and continue working on this project.
```

## Installation

### Sync Script (recommended)

```bash
# Create a paths.txt:
# ~/.claude/skills
# /path/to/project1

# Sync agents to ~/.claude/agents/ and skills to target paths
./scripts/sync-skills.sh paths.txt
```

The sync script:
- Copies `agents/*.md` to `~/.claude/agents/`
- Copies skill directories to target paths
- Cleans up old agent entries from skill targets

### Manual Installation

```bash
# Agents -> ~/.claude/agents/
cp agents/*.md ~/.claude/agents/

# Skills -> ~/.claude/skills/
cp -r skills/reader skills/prompt-refiner skills/differ-helper skills/estimator skills/peer-review skills/multi-agent-loop ~/.claude/skills/
```

## RTK (Rust Token Killer)

[RTK](https://github.com/rtk-ai/rtk) reduces LLM token consumption by 60-90% on common dev commands.

```bash
brew install rtk
rtk init -g          # Install hooks
rtk gain             # View token savings
```

## MemPalace

[MemPalace](https://github.com/mempalace/mempalace) is a local-first AI memory system that stores conversation history as verbatim text with semantic search. No summarization, no API calls, 96.6% R@5 on LongMemEval.

```bash
pip install mempalace
mempalace init ~/.claude/projects/    # Initialize for Claude Code sessions

# Mine project context
mempalace mine ~/.claude/projects/ --wing myproject

# Search past sessions
mempalace search "why did we switch to GraphQL"
```

Integrates with Claude Code, MCP, and provides auto-save hooks before context compression.

## Creating Your Own

### Agent

Create `agents/<name>.md`:

```yaml
---
name: my-agent
description: What this agent does and when to use it
tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"]
model: sonnet
---

You are <role>. Your job is to <responsibility>.

## Workflow
...
```

### Skill

Create `<name>/SKILL.md`:

```yaml
---
name: my-skill
description: What this skill provides
---

# Methodology / Reference Data
...
```

## Directory Structure

```
root/
  agents/                    # Autonomous agents (.md files)
    orchestrator.md
    architect.md
    builder.md
    qa-evaluator.md
    code-reviewer.md
    project-manager.md
    summarizer-auditor.md
  skills/                    # Skills (SKILL.md directories)
    reader/
    prompt-refiner/
    differ-helper/
    estimator/
    peer-review/
    multi-agent-loop/
  rules/                     # Language, framework & project rules
    rust.md
    typescript.md
    golang.md
    python.md
    tauri.md
    svelte.md
    engineering.md
    dagrobin.md
    rtk.md
    testing.md
  resources/
  scripts/
    sync-skills.sh
    flatten-all.sh
    install-tools.sh
  CLAUDE.md
```

## Scripts

### sync-skills.sh

Syncs agents and skills to their correct locations.

```bash
./scripts/sync-skills.sh paths.txt
```

### flatten-all.sh

Consolidates all plans, tasks, and markdown files from `.claude` folders.

```bash
./scripts/flatten-all.sh              # All markdown
./scripts/flatten-all.sh -p agents    # Agent definitions only
./scripts/flatten-all.sh -p skills    # Skill definitions only
```

## Adding dagRobin

```bash
git clone https://github.com/afa7789/dagRobin.git
cd dagRobin && cargo build --release
cp target/release/dagRobin ~/.cargo/bin/dagRobin
```

Always gitignore the database:

```bash
grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
```

### Auto-allow dagRobin commands

To avoid approving every dagRobin command manually, add this to your global Claude Code settings:

Add to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(dagRobin:*)"
    ]
  }
}
```

If you already have a `permissions.allow` array, just append `"Bash(dagRobin:*)"` to it. This allows all dagRobin subcommands (`list`, `ready`, `claim`, `update`, `import`, `export`, `graph`, `conflicts`, etc.) globally across all projects.
