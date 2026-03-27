# RTK (Rust Token Killer) — Standards & Best Practices

RTK filters command output for token efficiency. Use it for all lint, test, build, and git operations.

## Installation

```bash
# In any project:
rtk init
```

This creates `.rtk/filters.toml` in the project.

## Core Commands

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check   # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (90-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk vitest run          # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk test <cmd>         # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>         # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk summary <cmd>      # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Infrastructure | docker, kubectl | 85% |

## Best Practices

1. **Always use `rtk` prefix** — Even in command chains: `rtk git add . && rtk git commit -m "msg"`
2. **Use for every lint/test/build command** — Not just for viewing, but also in scripts
3. **Add to Makefile targets** — Use `rtk make <target>` patterns
4. **RTK passes through unknown commands** — Safe to use with anything

## Extending RTK

Add custom filters in `.rtk/filters.toml`:

```toml
[filter.<tool-name>]
command = "tool-name"
# Define output transformation rules
```
