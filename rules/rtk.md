# RTK (Rust Token Killer) — Standards & Best Practices

RTK filters command output for token efficiency. In Claude Code a PreToolUse hook adds the `rtk` prefix automatically (`git status` -> `rtk git status`), so type it by hand only in scripts, Makefiles, or other hosts.

## Standalone commands

The hook cannot derive these from a plain command, so call them by name:

```bash
rtk read <file>         # File contents, filtered
rtk grep <pattern>      # Search, compact output
rtk ls <path>           # Directory listing
rtk find <pattern>      # File search
rtk err <cmd>           # Errors only, from any command
rtk summary <cmd>       # Smart summary of command output
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk proxy <cmd>         # Raw, unfiltered output — for debugging, and for
                        # commands whose output a filter would mangle
rtk gain                # Token savings analytics (--history for per-command)
rtk discover            # Analyse Claude Code history for missed opportunities
```

`rtk proxy` is the escape hatch: reach for it the moment a filter is hiding
something you need, such as JSON you intend to parse.

## Installation check

```bash
rtk --version           # Expect: rtk X.Y.Z
rtk gain                # Expect analytics, not "command not found"
which rtk               # Confirm the binary
```

A `rtk gain` that fails means a name collision with reachingforthejack/rtk
(Rust Type Kit) rather than a broken install.

## Filtered commands

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

## Extending RTK

Add custom filters in `.rtk/filters.toml`:

```toml
[filter.<tool-name>]
command = "tool-name"
# Define output transformation rules
```
