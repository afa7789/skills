#!/usr/bin/env bash
#
# discover-screens.sh — evidence collector for Phase 1/2 of the frontend-ux-loop skill.
#
# Emits candidates with file:line evidence for every screen/route/navigation/preview
# pattern across web and mobile stacks. It does NOT decide what a screen is — read
# reference/discovery.md, then read the files it points at, and build the catalog.
#
# Usage:
#   bash discover-screens.sh [--root DIR] [--detect-only] [--out DIR] [--limit N] [--no-rg]
#
#   --root DIR      project root to scan (default: cwd)
#   --detect-only   print only the stack detection block (Phase 1)
#   --out DIR       also write the full report to DIR/discovery.raw.md
#   --limit N       max matches printed per pattern (default 60)
#   --no-rg         force the grep engine (both engines are equivalent; for testing)
#
# Engines: file selection is ALWAYS done here (one `find`, path-aware globs), so
# ripgrep and grep receive the same explicit file list and produce the same output.
# ripgrep is used only when a real ripgrep binary exists; grep is not a degraded mode.
#
# Requires: POSIX find/grep/sed/xargs. No project dependencies, no network.

set -uo pipefail   # deliberately no -e: "no matches" is a normal grep exit code

ROOT="$PWD"
OUT=""
DETECT_ONLY=0
LIMIT=60
ALLOW_RG=1

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --out)         OUT="${2:?--out needs a directory}"; shift 2 ;;
    --limit)       LIMIT="${2:?--limit needs a number}"; shift 2 ;;
    --detect-only) DETECT_ONLY=1; shift ;;
    --no-rg)       ALLOW_RG=0; shift ;;
    -h|--help)     sed -n '2,25p' "$0"; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$ROOT" ] || { echo "root not found: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

EXCLUDE_DIRS="node_modules .git dist build out .next .nuxt .svelte-kit .output .astro
coverage vendor target Pods Carthage .dart_tool .gradle .idea .expo .venv __pycache__
storybook-static .ux-review DerivedData .turbo .parcel-cache"

# ── engine selection ─────────────────────────────────────────────────────────
#
# `rg` is a shell function in some environments (Claude Code ships one), and a
# function is invisible to a non-interactive script — worse, a wrapper that is not
# ripgrep would break every search silently. So: resolve a real executable, then
# prove it is ripgrep by asking it. Also probe the usual install dirs, because a
# non-interactive PATH often misses them.
ENGINE="grep"
RGBIN=""
if [ "$ALLOW_RG" -eq 1 ]; then
  for _c in "$(command -v rg 2>/dev/null || true)" \
            /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg /opt/local/bin/rg \
            /snap/bin/rg "$HOME/.cargo/bin/rg" "$HOME/.local/bin/rg"; do
    [ -n "$_c" ] && [ -f "$_c" ] && [ -x "$_c" ] || continue
    if "$_c" --version 2>/dev/null | grep -qi '^ripgrep'; then
      ENGINE="ripgrep"; RGBIN="$_c"; break
    fi
  done
fi

# ── the file index: one find, reused by every search ─────────────────────────
#
# Paths are stored with a LEADING SLASH relative to ROOT (`/src/router/index.ts`),
# so a path glob like `*/app/*page.tsx` matches a top-level `app/` too.
FILELIST="$(mktemp "${TMPDIR:-/tmp}/uxloop.XXXXXX")" || { echo "cannot create temp file" >&2; exit 1; }
trap 'rm -f "$FILELIST"' EXIT HUP INT TERM

build_index() {
  local prune=() first=1 d
  for d in $EXCLUDE_DIRS; do
    if [ $first -eq 1 ]; then first=0; else prune+=(-o); fi
    prune+=(-name "$d")
  done
  find "$ROOT" \( "${prune[@]}" \) -prune -o -type f -print 2>/dev/null \
    | sed "s|^$ROOT||" | sort > "$FILELIST"
}

# glob_to_re <glob> — shell glob to ERE, matched against a leading-slash path.
# A glob without `/` matches the BASE NAME; a glob with `/` matches the whole path.
# `*` crosses directory separators, exactly like find -path.
glob_to_re() {
  local g="$1" re
  re=$(printf '%s' "$g" | sed -e 's/[]^$.+?(){}|[]/\\&/g' -e 's/\*/.*/g')
  case "$g" in
    */*) printf '^%s$' "$re" ;;
    *)   printf '.*/%s$' "$re" ;;
  esac
}

# pick_files <glob...> — the indexed paths matching any glob, one per line,
# leading slash stripped is done by the callers that print.
pick_files() {
  local re="" g
  for g in "$@"; do
    if [ -z "$re" ]; then re="$(glob_to_re "$g")"; else re="$re|$(glob_to_re "$g")"; fi
  done
  [ -z "$re" ] && { cat "$FILELIST"; return 0; }
  grep -E "$re" "$FILELIST" 2>/dev/null
}

# ── output helpers ───────────────────────────────────────────────────────────

# search <label> <extended-regex> [file-glob ...]
search() {
  local label="$1" pat="$2"; shift 2
  local list out n
  list=$(pick_files "$@")
  [ -z "$list" ] && return 0

  # NUL-separate so paths with spaces survive xargs; -H so a single-file batch
  # still prints the filename (both engines omit it otherwise).
  if [ "$ENGINE" = ripgrep ]; then
    out=$(printf '%s\n' "$list" | sed "s|^|$ROOT|" | tr '\n' '\0' \
          | xargs -0 "$RGBIN" -H --line-number --no-heading --color never --no-messages -e "$pat" 2>/dev/null)
  else
    out=$(printf '%s\n' "$list" | sed "s|^|$ROOT|" | tr '\n' '\0' \
          | xargs -0 grep -HnEIs --color=never -e "$pat" 2>/dev/null)
  fi

  out=$(printf '%s' "$out" | sed "s|^$ROOT/||")
  n=$(printf '%s' "$out" | grep -c . 2>/dev/null || true)
  [ "${n:-0}" -eq 0 ] && return 0
  printf '\n#### %s — %s match(es)\n```\n' "$label" "$n"
  printf '%s\n' "$out" | head -n "$LIMIT"
  [ "$n" -gt "$LIMIT" ] && printf '... (%s more, re-run with --limit %s)\n' "$((n - LIMIT))" "$((n * 2))"
  printf '```\n'
}

# files <label> <file-glob ...> — list matching files, no content search
files() {
  local label="$1"; shift
  local out n
  out=$(pick_files "$@" | sed 's|^/||')
  n=$(printf '%s' "$out" | grep -c . 2>/dev/null || true)
  [ "${n:-0}" -eq 0 ] && return 0
  printf '\n#### %s — %s file(s)\n```\n' "$label" "$n"
  printf '%s\n' "$out" | head -n "$LIMIT"
  [ "$n" -gt "$LIMIT" ] && printf '... (%s more)\n' "$((n - LIMIT))"
  printf '```\n'
}

exists() { [ -e "$ROOT/$1" ]; }

# has_match <extended-regex> <file-glob ...> — quiet presence test, same engine
has_match() {
  local pat="$1"; shift
  local list
  list=$(pick_files "$@")
  [ -z "$list" ] && return 1
  if [ "$ENGINE" = ripgrep ]; then
    printf '%s\n' "$list" | sed "s|^|$ROOT|" | tr '\n' '\0' \
      | xargs -0 "$RGBIN" --quiet --no-messages -e "$pat" >/dev/null 2>&1
  else
    printf '%s\n' "$list" | sed "s|^|$ROOT|" | tr '\n' '\0' \
      | xargs -0 grep -qEIs -e "$pat" >/dev/null 2>&1
  fi
}

# dep_in_any_package_json <dep> — monorepo-aware, uses the index
any_pkg_has() {
  local f
  pick_files 'package.json' | while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -q "\"$1\"" "$ROOT$f" 2>/dev/null; then printf '%s' "$ROOT$f"; return 0; fi
  done
}

# ── Phase 1: stack detection ─────────────────────────────────────────────────

detect() {
  printf '## Stack detection\n\n'
  printf 'Root: `%s`\n\n' "$ROOT"

  printf '### Platform\n'
  local found=0
  for probe in \
    "react:React (web)" "react-native:React Native" "expo:Expo" \
    "vue:Vue" "nuxt:Nuxt" "svelte:Svelte" "@sveltejs/kit:SvelteKit" \
    "@angular/core:Angular" "next:Next.js" "astro:Astro" "solid-js:Solid"
  do
    dep="${probe%%:*}"; label="${probe#*:}"
    if [ -n "$(any_pkg_has "$dep")" ]; then printf -- '- %s (`%s`)\n' "$label" "$dep"; found=1; fi
  done
  exists pubspec.yaml && { printf -- '- Flutter/Dart (`pubspec.yaml`)\n'; found=1; }
  { exists build.gradle || exists build.gradle.kts || exists app/build.gradle || exists app/build.gradle.kts; } \
    && { printf -- '- Android (Gradle)\n'; found=1; }
  [ -n "$(pick_files '*.xcodeproj/*' '*.xcworkspace/*' | head -1)" ] \
    && { printf -- '- iOS/macOS (Xcode project)\n'; found=1; }
  exists Package.swift && { printf -- '- Swift package\n'; found=1; }
  [ $found -eq 0 ] && printf -- '- **unknown — no known frontend manifest found**\n'

  printf '\n### Package manager / build\n'
  exists pnpm-lock.yaml    && printf -- '- pnpm\n'
  exists yarn.lock         && printf -- '- yarn\n'
  exists package-lock.json && printf -- '- npm\n'
  exists bun.lockb         && printf -- '- bun\n'
  exists pubspec.lock      && printf -- '- flutter pub\n'
  exists Podfile           && printf -- '- CocoaPods\n'
  exists gradlew           && printf -- '- Gradle wrapper\n'

  printf '\n### Routing mechanism\n'
  [ -n "$(pick_files '*/app/*page.tsx' '*/app/*page.jsx' '*/app/*page.js' '*/app/*_layout.tsx' | head -1)" ] \
    && printf -- '- file-based: `app/` (Next App Router or Expo Router)\n'
  { exists pages || exists src/pages; } && printf -- '- `pages/` directory (Next Pages Router, Nuxt, or Astro)\n'
  exists src/routes && printf -- '- file-based: `src/routes/` (SvelteKit)\n'
  [ -n "$(any_pkg_has react-router)" ]             && printf -- '- React Router\n'
  [ -n "$(any_pkg_has vue-router)" ]               && printf -- '- Vue Router\n'
  [ -n "$(any_pkg_has @tanstack/react-router)" ]   && printf -- '- TanStack Router\n'
  [ -n "$(any_pkg_has @react-navigation/native)" ] && printf -- '- React Navigation\n'
  [ -n "$(any_pkg_has expo-router)" ]              && printf -- '- Expo Router\n'
  exists pubspec.yaml && grep -qE 'go_router|auto_route' "$ROOT/pubspec.yaml" 2>/dev/null \
                      && printf -- '- Flutter router (go_router / auto_route)\n'

  printf '\n### Existing catalog / preview harness (reuse it — do not build a second one)\n'
  local cat_found=0
  exists .storybook   && { printf -- '- Storybook (`.storybook/`)\n'; cat_found=1; }
  exists .rnstorybook && { printf -- '- Storybook for React Native (`.rnstorybook/`)\n'; cat_found=1; }
  [ -n "$(any_pkg_has @storybook/react-native)" ] && { printf -- '- Storybook for React Native (dep)\n'; cat_found=1; }
  [ -n "$(any_pkg_has histoire)" ] && { printf -- '- Histoire\n'; cat_found=1; }
  exists pubspec.yaml && grep -q 'widgetbook' "$ROOT/pubspec.yaml" 2>/dev/null \
    && { printf -- '- Widgetbook\n'; cat_found=1; }
  has_match '@Preview' '*.kt' && { printf -- '- Compose @Preview\n'; cat_found=1; }
  has_match '#Preview|PreviewProvider' '*.swift' && { printf -- '- SwiftUI previews\n'; cat_found=1; }
  [ $cat_found -eq 0 ] && printf -- '- none found — Phase 4 must create one\n'

  printf '\n### Existing capture / test tooling\n'
  local cap_found=0
  [ -n "$(any_pkg_has @playwright/test)" ] && { printf -- '- Playwright\n'; cap_found=1; }
  [ -n "$(any_pkg_has cypress)" ]          && { printf -- '- Cypress\n'; cap_found=1; }
  [ -n "$(any_pkg_has detox)" ]            && { printf -- '- Detox\n'; cap_found=1; }
  [ -n "$(any_pkg_has msw)" ]              && { printf -- '- MSW (mocking already available)\n'; cap_found=1; }
  [ -n "$(pick_files '*maestro*' | head -1)" ] && { printf -- '- Maestro flows\n'; cap_found=1; }
  exists integration_test && { printf -- '- Flutter integration_test\n'; cap_found=1; }
  [ $cap_found -eq 0 ] && printf -- '- none found\n'

  printf '\n### Design system / tokens (audit against THESE first)\n'
  local ds=0 tok
  for probe in "@mui/material:MUI (Material)" "vuetify:Vuetify (Material)" \
               "react-native-paper:React Native Paper (Material)" "@angular/material:Angular Material" \
               "tailwindcss:Tailwind" "@shopify/polaris:Polaris" "antd:Ant Design" \
               "@chakra-ui/react:Chakra" "bootstrap:Bootstrap" "@fluentui/react:Fluent"
  do
    dep="${probe%%:*}"; label="${probe#*:}"
    [ -n "$(any_pkg_has "$dep")" ] && { printf -- '- %s\n' "$label"; ds=1; }
  done
  exists pubspec.yaml && grep -q 'material' "$ROOT/pubspec.yaml" 2>/dev/null && { printf -- '- Flutter Material\n'; ds=1; }
  tok=$(pick_files 'tokens*' 'theme.*' 'tailwind.config.*' 'design-tokens*' '*/theme/*' | sed 's|^/|  - |' | head -10)
  [ -n "$tok" ] && { printf -- '- token/theme files present:\n%s\n' "$tok"; ds=1; }
  [ $ds -eq 0 ] && printf -- '- none detected — ask the user which standard applies\n'
}

# ── Phase 2: screen discovery ────────────────────────────────────────────────

discover() {
  printf '\n\n## Screen candidates\n'
  printf '\n> Every block below is a CANDIDATE with evidence. Confirm each by reading the\n'
  printf '> file at the reported line. See reference/discovery.md for what each pattern\n'
  printf '> means and for the things grep cannot see.\n'

  printf '\n### 1. Explicit route tables (highest confidence — read these in full)\n'
  files  "Router / navigation source files" \
    '*/router/*' '*/routers/*' '*/routes/*.ts' '*/routes/*.js' '*/navigation/*' \
    '*router*.ts' '*router*.tsx' '*router*.js' '*routes*.ts' '*routes*.tsx' \
    '*navigation*.ts' '*navigation*.tsx' '*Navigator*.ts' '*Navigator*.tsx' \
    '*routing.module.ts' '*router*.dart' '*routes*.dart' '*NavHost*.kt' '*Navigation*.kt' '*Navigation*.swift'
  search "React Router"   'createBrowserRouter|createHashRouter|<Route[[:space:]]|useRoutes\(|RouterProvider' '*.tsx' '*.jsx' '*.ts' '*.js'
  search "Vue Router"     'createRouter\(|createWebHistory|routes:[[:space:]]*\[' '*.ts' '*.js' '*.vue'
  search "Angular Router" 'RouterModule\.for(Root|Child)|Routes[[:space:]]*=[[:space:]]*\[|loadChildren' '*.ts'
  search "TanStack Router" 'createRoute\(|createFileRoute\(|createRootRoute' '*.ts' '*.tsx'
  search "Svelte SPA router" '<Route[[:space:]]+path|router\.on\(' '*.svelte' '*.ts' '*.js'
  search "Route path literals" "path:[[:space:]]*['\"]/" '*.ts' '*.js' '*.tsx' '*.vue'

  printf '\n### 2. File-based routes (route = path on disk)\n'
  files "Next App Router pages"  '*/app/*page.tsx' '*/app/*page.jsx' '*/app/*page.js'
  files "Next/Expo route helpers (state evidence)" '*/app/*loading.tsx' '*/app/*error.tsx' '*/app/*not-found.tsx' '*/app/*layout.tsx'
  files "Next Pages Router"      '*/pages/*.tsx' '*/pages/*.jsx'
  files "Nuxt / Vue pages dir"   '*/pages/*.vue'
  files "SvelteKit routes"       '*/src/routes/*+page.svelte' '*/src/routes/*+error.svelte' '*/src/routes/*+layout.svelte'
  files "Astro pages"            '*/src/pages/*.astro'
  files "Remix routes"           '*/app/routes/*.tsx' '*/app/routes/*.jsx'

  printf '\n### 3. Mobile navigation\n'
  search "React Navigation" 'createNativeStackNavigator|createBottomTabNavigator|createDrawerNavigator|createMaterialTopTabNavigator|<[A-Za-z]+\.Screen' '*.tsx' '*.jsx' '*.ts'
  search "Navigation calls (reachability)" 'navigation\.(navigate|push|replace)\(|router\.(push|replace)\(|<Link[[:space:]]+href' '*.tsx' '*.jsx' '*.ts'
  search "Flutter routes" 'GoRoute\(|AutoRoute\(|onGenerateRoute|routes:[[:space:]]*\{|Navigator\.(pushNamed|push)\(' '*.dart'
  search "Flutter screen widgets" 'class[[:space:]]+[A-Za-z0-9_]*(Page|Screen|View)[[:space:]]+extends' '*.dart'
  search "Compose navigation" 'composable\(|NavHost\(|navController\.navigate\(' '*.kt'
  search "Android manifest surfaces" '<activity|android:name=".*(Activity|Fragment)"' 'AndroidManifest.xml' '*/res/navigation/*.xml'
  search "SwiftUI navigation" 'NavigationStack|NavigationLink\(|navigationDestination\(|\.sheet\(|\.fullScreenCover\(' '*.swift'
  search "UIKit view controllers" 'class[[:space:]]+[A-Za-z0-9_]*ViewController|pushViewController|present\(' '*.swift'

  printf '\n### 4. Naming conventions (medium confidence — cross-check against §1–3)\n'
  files "Page/Screen/View components" \
    '*Page.tsx' '*Page.jsx' '*Page.vue' '*Page.svelte' '*Page.ts' \
    '*Screen.tsx' '*Screen.jsx' '*Screen.ts' '*View.vue' '*View.swift' \
    '*Activity.kt' '*Fragment.kt' '*Screen.kt' '*_page.dart' '*_screen.dart' '*_view.dart'
  files "screens/ pages/ views/ directories" '*/screens/*' '*/pages/*' '*/views/*'

  printf '\n### 5. Existing catalogs and previews (free inventory — reuse)\n'
  files "Storybook stories" '*.stories.ts' '*.stories.tsx' '*.stories.js' '*.stories.jsx' '*.stories.svelte' '*.stories.vue' '*.stories.mdx'
  search "Story exports (state names)" 'export const [A-Z][A-Za-z0-9_]*[[:space:]]*[:=]' '*.stories.ts' '*.stories.tsx' '*.stories.js' '*.stories.jsx'
  files "Widgetbook use cases" '*.widgetbook.dart' '*widgetbook*'
  search "Widgetbook annotations" '@widgetbook\.(UseCase|App)' '*.dart'
  search "Compose previews" '@Preview|@PreviewLightDark|@PreviewFontScale|@PreviewScreenSizes' '*.kt'
  search "SwiftUI previews" '#Preview|PreviewProvider|previewDevice' '*.swift'

  printf '\n### 6. Tests as a route oracle (real routes, real params, real auth)\n'
  search "Playwright/Cypress visits" 'page\.goto\(|cy\.visit\(' '*.spec.ts' '*.spec.js' '*.spec.tsx' '*.cy.ts' '*.cy.js' '*.test.ts'
  search "Maestro flows" 'launchApp|assertVisible|takeScreenshot' '*.yaml' '*.yml'
  search "Detox" 'device\.launchApp|element\(by\.' '*.e2e.ts' '*.e2e.js' '*.test.ts'
  files  "Flutter integration tests" '*/integration_test/*'

  printf '\n### 7. Visual states (only states with code behind them go in the catalog)\n'
  search "loading" 'isLoading|isPending|<Suspense|Skeleton|CircularProgress|ActivityIndicator|AsyncValue\.loading|\.loading\b' '*.tsx' '*.jsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "empty"   'length[[:space:]]*===?[[:space:]]*0|isEmpty|EmptyState|no results|No results' '*.tsx' '*.jsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "error"   'isError|ErrorBoundary|ErrorState|catch[[:space:]]*\(|AsyncValue\.error|onError' '*.tsx' '*.jsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "disabled" 'disabled[=:]|isDisabled|enabled:[[:space:]]*false' '*.tsx' '*.jsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "permission / 403" 'canActivate|requiresAuth|isAdmin|forbidden|403|permission' '*.ts' '*.tsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "offline"  'navigator\.onLine|ConnectivityResult|NetworkInfo|isOffline|isConnected' '*.ts' '*.tsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  search "validation" 'zodResolver|yupResolver|useForm\(|FormState|validator:|errors\.' '*.ts' '*.tsx' '*.vue' '*.svelte' '*.dart'
  search "dark mode"  'prefers-color-scheme|useColorScheme|ThemeMode|isSystemInDarkTheme|colorScheme' '*.ts' '*.tsx' '*.css' '*.scss' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'

  printf '\n### 8. Guards, params and feature flags (blockers for capture)\n'
  search "Route params (dynamic segments)" "(path|to|href|route|name)[=:][[:space:]]*['\"][^'\"]*:[A-Za-z]" '*.ts' '*.tsx' '*.js' '*.jsx' '*.vue' '*.svelte' '*.dart' '*.kt' '*.swift'
  files  "Dynamic route files (params in the filename)" '*[*]*'
  search "Route guards"    'beforeEnter|canActivate|requiresAuth|loader:|redirectTo|AuthGuard' '*.ts' '*.tsx' '*.js' '*.vue' '*.svelte' '*.dart' '*.kt'
  search "Feature flags"   'useFlag\(|isEnabled\(|featureFlag|LaunchDarkly|remoteConfig' '*.ts' '*.tsx' '*.dart' '*.kt' '*.swift'
  search "Deep links"      'intent-filter|associatedDomains|universalLink|Linking\.|scheme' 'AndroidManifest.xml' '*.plist' '*.ts' '*.tsx' 'app.json'

  printf '\n## Next steps\n'
  printf '1. Read every file:line above that looks like a route table — those are ground truth.\n'
  printf '2. Open each screen component and record the states that actually exist (§7 above).\n'
  printf '3. Write SCREEN_INVENTORY.md (assets/SCREEN_INVENTORY.template.md) with evidence + confidence.\n'
  printf '4. List everything unresolved in UNRESOLVED_SCREENS.md — see reference/discovery.md §9.\n'
  printf '5. Generate ui-catalog.yaml and have the USER confirm it before capturing anything.\n'
}

# ── run ──────────────────────────────────────────────────────────────────────

report() {
  printf '# Screen discovery — raw evidence\n\n'
  printf 'Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'Engine: %s · files indexed: %s\n\n' "$ENGINE" "$(grep -c . "$FILELIST" 2>/dev/null || echo 0)"
  detect
  [ "$DETECT_ONLY" -eq 1 ] || discover
}

build_index

if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
  report | tee "$OUT/discovery.raw.md"
  printf '\nWritten to %s/discovery.raw.md\n' "$OUT"
else
  report
fi
