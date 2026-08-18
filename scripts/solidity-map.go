// solidity-map.go — Static project mapper for Solidity / Foundry / Hardhat repos.
//
// Walks a repo, classifies every .sol file (and every deploy/config artifact)
// into a small taxonomy, and emits a single map.json describing the surface
// the audit must cover. No external deps, no LLM — runs in well under a second
// on real-world repos. The output is the input the rest of solidity-audit.sh
// scopes itself against: which contracts are core vs mock vs external, where
// deploy scripts live, what oracles/keepers/proxies the system has, etc.
//
// Usage:
//
//	go run scripts/solidity-map.go <repo-path> --output findings/map.json
//	# or build once:
//	go build -o scripts/solidity-map scripts/solidity-map.go
//	./scripts/solidity-map <repo-path> --output findings/map.json
//
// Output schema (findings/map.json):
//
//	{
//	  "generated_at": "...",
//	  "repo": "/abs/path",
//	  "foundry": { "root": "...", "src": "...", "test": "..." },
//	  "summary": { "core": N, "interface": N, "library": N,
//	               "mock": N, "abstract": N, "deploy_script": N,
//	               "test": N, "external": N, "oracle": N, ... },
//	  "parts": [
//	    { "path": "src/Vault.sol", "category": "core",
//	      "role": "core_contract", "loc": 312,
//	      "external_deps": ["openzeppelin-contracts/..."],
//	      "contracts": ["Vault"], "kind": ["upgradeable", "payable"] },
//	    ...
//	  ]
//	}
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// --- taxonomy ------------------------------------------------------------

type Category string

const (
	CatCore         Category = "core"
	CatInterface    Category = "interface"
	CatLibrary      Category = "library"
	CatAbstract     Category = "abstract"
	CatMock         Category = "mock"
	CatDeployScript Category = "deploy_script"
	CatTest         Category = "test"
	CatInvariant    Category = "invariant"
	CatFuzz         Category = "fuzz"
	CatExternal     Category = "external"
	CatOracle       Category = "oracle"
	CatKeeper       Category = "keeper"
	CatProxy        Category = "proxy"
	CatConfig       Category = "config"
	CatUnknown      Category = "unknown"
)

type Part struct {
	Path        string   `json:"path"`
	Category    Category `json:"category"`
	Role        string   `json:"role"`
	Loc         int      `json:"loc"`
	ExternalDeps []string `json:"external_deps,omitempty"`
	Contracts   []string `json:"contracts,omitempty"`
	Kind        []string `json:"kind,omitempty"`
	Reason      string   `json:"reason,omitempty"`
}

type Foundry struct {
	Root string `json:"root"`
	Src  string `json:"src,omitempty"`
	Test string `json:"test,omitempty"`
	Script string `json:"script,omitempty"`
}

type Summary map[Category]int

type Output struct {
	GeneratedAt string   `json:"generated_at"`
	Repo        string   `json:"repo"`
	Foundry     Foundry  `json:"foundry"`
	Summary     Summary  `json:"summary"`
	Parts       []Part   `json:"parts"`
	Warnings    []string `json:"warnings,omitempty"`
}

// --- regexes (compiled once) --------------------------------------------

var (
	reContract     = regexp.MustCompile(`(?m)^\s*(?:abstract\s+)?(?:interface|library|contract)\s+([A-Za-z_][A-Za-z0-9_]*)`)
	reLibrary      = regexp.MustCompile(`(?m)^\s*library\s+([A-Za-z_][A-Za-z0-9_]*)`)
	reInterface    = regexp.MustCompile(`(?m)^\s*interface\s+([A-Za-z_][A-Za-z0-9_]*)`)
	reAbstract     = regexp.MustCompile(`(?m)^\s*abstract\s+contract\s+([A-Za-z_][A-Za-z0-9_]*)`)
	reImportExt    = regexp.MustCompile(`(?m)^\s*import\s+(?:[^"';]+\s+from\s+)?["']([^"']+)["']`)
	reInvariant    = regexp.MustCompile(`function\s+invariant_\w+`)
	reFuzz         = regexp.MustCompile(`function\s+testFuzz_\w+`)
	rePayable      = regexp.MustCompile(`\bpayable\b`)
	reUpgradeable  = regexp.MustCompile(`\b(?:Initializable|UUPS|TransparentUpgradeable|Upgradeable)\b`)
	// owned catches OpenZeppelin Ownable, OwnableUpgradeable, AccessControl,
	// and the onlyOwner/onlyRole modifiers — these all signal that some
	// access-control plumbing exists in the file.
	reOwnable      = regexp.MustCompile(`\b(?:Ownable[A-Za-z]*|AccessControl|onlyOwner|onlyRole)\b`)
)

// --- classify a single .sol file ----------------------------------------

func classifyFile(absPath, relPath string, info os.FileInfo) (Part, []string) {
	warnings := []string{}
	p := Part{Path: relPath, Loc: countLines(absPath)}

	// External dependency?
	if isExternalPath(relPath) {
		p.Category = CatExternal
		p.Role = "external_lib"
		p.Reason = "path under lib/, node_modules/, or dependencies/"
		return p, warnings
	}

	// Read first ~200 lines for cheap content heuristics.
	head := readHead(absPath, 200)

	// Test?
	if isTestPath(relPath) || strings.Contains(relPath, "/test/") || strings.HasPrefix(relPath, "test/") {
		p.Category = CatTest
		p.Role = "test"
		p.Contracts = findContracts(head)
		if reInvariant.MatchString(head) || strings.Contains(relPath, "invariant") {
			p.Category = CatInvariant
			p.Role = "invariant"
		} else if reFuzz.MatchString(head) || strings.Contains(relPath, "fuzz") {
			p.Category = CatFuzz
			p.Role = "fuzz"
		}
		return p, warnings
	}

	// Deploy script?
	if isDeployScript(relPath, head) {
		p.Category = CatDeployScript
		p.Role = "deploy_script"
		p.Contracts = findContracts(head)
		return p, warnings
	}

	// Mock?
	if isMock(relPath) {
		p.Category = CatMock
		p.Role = "mock"
		p.Contracts = findContracts(head)
		return p, warnings
	}

	// Interface / library / abstract detected purely by content. Only classify
	// as such when EVERY top-level declaration in the file matches that kind
	// — mixed files (e.g. library + concrete contract) fall through to core.
	contracts := findContracts(head)
	if reLibrary.MatchString(head) && len(contracts) > 0 && !hasConcreteContract(head) {
		p.Category = CatLibrary
		p.Role = "library"
		p.Contracts = contracts
		return p, warnings
	}
	if reInterface.MatchString(head) && len(contracts) > 0 && !hasConcreteContract(head) {
		p.Category = CatInterface
		p.Role = "interface"
		p.Contracts = contracts
		return p, warnings
	}
	if reAbstract.MatchString(head) && !hasConcreteNonAbstractContract(head) {
		p.Category = CatAbstract
		p.Role = "abstract"
		p.Contracts = contracts
		return p, warnings
	}

	// Filename heuristic for I<Name>.sol (interface) — even if the file is
	// empty or doesn't match the body regex (e.g. very short stubs).
	base := strings.TrimSuffix(filepath.Base(relPath), ".sol")
	if strings.HasPrefix(base, "I") && len(base) > 1 && isUpper(base[1]) {
		p.Category = CatInterface
		p.Role = "interface_by_name"
		p.Contracts = []string{base[1:]}
		p.Reason = "filename matches I<Name>.sol convention"
		return p, warnings
	}

	// Concrete contract in src/ = core.
	if len(contracts) > 0 {
		p.Category = CatCore
		p.Role = "core_contract"
		p.Contracts = contracts
		// Domain role hints based on naming.
		lower := strings.ToLower(base)
		switch {
		case strings.Contains(lower, "oracle") || strings.Contains(lower, "pricefeed") || strings.Contains(lower, "aggregator"):
			p.Category = CatOracle
			p.Role = "oracle"
		case strings.Contains(lower, "keeper") || strings.Contains(lower, "automation") || strings.Contains(lower, "upkeep"):
			p.Category = CatKeeper
			p.Role = "keeper"
		case strings.Contains(lower, "proxy") || strings.Contains(lower, "upgradeable"):
			p.Category = CatProxy
			p.Role = "proxy"
		}
		// Tags.
		if rePayable.MatchString(head) {
			p.Kind = append(p.Kind, "payable")
		}
		if reUpgradeable.MatchString(head) {
			p.Kind = append(p.Kind, "upgradeable")
		}
		if reOwnable.MatchString(head) {
			p.Kind = append(p.Kind, "owned")
		}
		return p, warnings
	}

	p.Category = CatUnknown
	p.Role = "unclassified"
	warnings = append(warnings, fmt.Sprintf("no contract/library/interface declaration found in %s", relPath))
	return p, warnings
}

// --- helpers ------------------------------------------------------------

func isExternalPath(rel string) bool {
	parts := strings.Split(rel, string(filepath.Separator))
	if len(parts) > 0 {
		switch parts[0] {
		case "lib", "node_modules", "dependencies", "vendor":
			return true
		}
	}
	return false
}

func isTestPath(rel string) bool {
	parts := strings.Split(rel, string(filepath.Separator))
	for _, p := range parts {
		if p == "test" || p == "tests" || p == "test-contracts" {
			return true
		}
	}
	return false
}

func isDeployScript(rel string, head string) bool {
	base := strings.ToLower(filepath.Base(rel))
	if strings.HasSuffix(base, ".s.sol") {
		return true
	}
	parts := strings.Split(rel, string(filepath.Separator))
	for _, p := range parts {
		if p == "script" || p == "scripts" || p == "deploy" || p == "deployment" {
			if strings.HasSuffix(rel, ".sol") {
				return true
			}
		}
	}
	// Forge script: contains `function run()` and `vm.startBroadcast`.
	if strings.Contains(head, "function run") && (strings.Contains(head, "startBroadcast") || strings.Contains(head, "vm.startBroadcast()")) {
		return true
	}
	// Hardhat deploy: exports a default function or named one.
	if strings.Contains(head, "module.exports") || strings.Contains(head, "func deploy") {
		return true
	}
	return false
}

func isMock(rel string) bool {
	parts := strings.Split(rel, string(filepath.Separator))
	for _, p := range parts {
		if p == "mocks" || p == "mock" {
			return true
		}
	}
	base := filepath.Base(rel)
	return strings.HasPrefix(base, "Mock") || strings.HasPrefix(base, "mock")
}

func findContracts(head string) []string {
	matches := reContract.FindAllStringSubmatch(head, -1)
	seen := map[string]bool{}
	out := []string{}
	for _, m := range matches {
		name := m[1]
		if !seen[name] {
			seen[name] = true
			out = append(out, name)
		}
	}
	return out
}

// hasConcreteContract returns true if `head` contains a `contract X {` line
// with neither `abstract ` nor `interface ` / `library ` prefix. That's a
// deployable contract — so a file containing one is "core", not interface.
func hasConcreteContract(head string) bool {
	re := regexp.MustCompile(`(?m)^\s*contract\s+[A-Za-z_][A-Za-z0-9_]*\b`)
	return re.MatchString(head)
}

// hasConcreteNonAbstractContract: same but excludes `abstract contract`.
// Go's regexp doesn't support lookbehind, so we walk lines manually.
func hasConcreteNonAbstractContract(head string) bool {
	re := regexp.MustCompile(`^\s*(?:abstract\s+)?contract\s+[A-Za-z_][A-Za-z0-9_]*\b`)
	for _, line := range strings.Split(head, "\n") {
		m := re.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		// Group 1 is `abstract ` if present; if not, it's a concrete contract.
		if !strings.HasPrefix(strings.TrimSpace(m[0]), "abstract") {
			return true
		}
	}
	return false
}

// containsAny was unused — removing it keeps the surface small.

func isUpper(b byte) bool { return b >= 'A' && b <= 'Z' }

func countLines(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	buf := make([]byte, 32*1024)
	n, _ := f.Read(buf)
	return strings.Count(string(buf[:n]), "\n") + 1
}

func readHead(path string, maxLines int) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	lines := make([]string, 0, maxLines)
	buf := make([]byte, 4096)
	for len(lines) < maxLines {
		n, err := f.Read(buf)
		if n > 0 {
			for _, l := range strings.Split(string(buf[:n]), "\n") {
				lines = append(lines, l)
				if len(lines) >= maxLines {
					break
				}
			}
		}
		if err != nil {
			break
		}
	}
	return strings.Join(lines, "\n")
}

func findImports(head string) []string {
	matches := reImportExt.FindAllStringSubmatch(head, -1)
	seen := map[string]bool{}
	out := []string{}
	for _, m := range matches {
		imp := m[1]
		if !strings.HasPrefix(imp, ".") && !seen[imp] {
			seen[imp] = true
			out = append(out, imp)
		}
	}
	return out
}

// --- main ---------------------------------------------------------------

func main() {
	// Use a custom parser that stops on the first positional argument, so
	// the user can write either:
	//   solidity-map <repo>
	//   solidity-map --output FILE <repo>
	//   solidity-map <repo> --output FILE
	// without `--output` accidentally eating the repo path as its value.
	repo := ""
	outPath := "-"
	for i := 1; i < len(os.Args); i++ {
		a := os.Args[i]
		switch {
		case a == "--repo":
			if i+1 < len(os.Args) {
				repo = os.Args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--repo="):
			repo = strings.TrimPrefix(a, "--repo=")
		case a == "--output", a == "-o":
			if i+1 < len(os.Args) {
				outPath = os.Args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--output="):
			outPath = strings.TrimPrefix(a, "--output=")
		case strings.HasPrefix(a, "-o="):
			outPath = strings.TrimPrefix(a, "-o=")
		case strings.HasPrefix(a, "--"):
			fmt.Fprintf(os.Stderr, "unknown flag: %s\n", a)
			os.Exit(2)
		case strings.HasPrefix(a, "-") && len(a) > 1:
			fmt.Fprintf(os.Stderr, "unknown short flag: %s\n", a)
			os.Exit(2)
		default:
			repo = a
		}
	}
	if repo == "" {
		fmt.Fprintln(os.Stderr, "usage: solidity-map [--repo PATH | PATH] [--output FILE]")
		os.Exit(2)
	}
	out := outPath
	absRepo, err := filepath.Abs(repo)
	if err != nil {
		fmt.Fprintf(os.Stderr, "abs path: %v\n", err)
		os.Exit(1)
	}
	if st, err := os.Stat(absRepo); err != nil || !st.IsDir() {
		fmt.Fprintf(os.Stderr, "not a directory: %s\n", absRepo)
		os.Exit(1)
	}

	foundry := detectFoundry(absRepo)

	parts := []Part{}
	warnings := []string{}
	summary := Summary{}

	err = filepath.Walk(absRepo, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("walk %s: %v", path, err))
			return nil
		}
		if info.IsDir() {
			// Skip heavy directories explicitly even if not external-path.
			name := info.Name()
			if name == ".git" || name == "out" || name == "cache" || name == "broadcast" || name == ".next" {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(absRepo, path)
		ext := strings.ToLower(filepath.Ext(path))
		switch ext {
		case ".sol":
			part, ws := classifyFile(path, rel, info)
			// Pull external import targets from head.
			head := readHead(path, 200)
			part.ExternalDeps = findImports(head)
			parts = append(parts, part)
			for _, w := range ws {
				warnings = append(warnings, w)
			}
			summary[part.Category]++
		case ".json", ".yaml", ".yml", ".toml":
			// Config files only — surface but don't expand.
			low := strings.ToLower(rel)
			if strings.Contains(low, "deploy") || strings.Contains(low, "addresses") ||
				strings.HasSuffix(low, "foundry.toml") || strings.HasSuffix(low, "hardhat.config.js") ||
				strings.HasSuffix(low, "hardhat.config.ts") {
				parts = append(parts, Part{
					Path: rel, Category: CatConfig, Role: "config",
					Reason: "deployment / network config",
				})
				summary[CatConfig]++
			}
		}
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "walk: %v\n", err)
		os.Exit(1)
	}

	sort.Slice(parts, func(i, j int) bool { return parts[i].Path < parts[j].Path })

	out2 := Output{
		GeneratedAt: time.Now().UTC().Format(time.RFC3339),
		Repo:        absRepo,
		Foundry:     foundry,
		Summary:     summary,
		Parts:       parts,
		Warnings:    warnings,
	}

	js, err := json.MarshalIndent(out2, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal: %v\n", err)
		os.Exit(1)
	}
	if out == "-" || out == "" {
		fmt.Println(string(js))
		return
	}
	if err := os.WriteFile(out, js, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "write: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "wrote %s — %d parts\n", out, len(parts))
}

// --- foundry detection (mirrors scripts/solidity-audit.sh heuristics) ---

func detectFoundry(absRepo string) Foundry {
	out := Foundry{Root: absRepo}
	for _, name := range []string{"src", "contracts"} {
		p := filepath.Join(absRepo, name)
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			out.Src = p
			break
		}
	}
	for _, name := range []string{"test", "tests"} {
		p := filepath.Join(absRepo, name)
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			out.Test = p
			break
		}
	}
	for _, name := range []string{"script", "scripts"} {
		p := filepath.Join(absRepo, name)
		if st, err := os.Stat(p); err == nil && st.IsDir() {
			out.Script = p
			break
		}
	}
	// Verify it's actually a Foundry repo.
	if _, err := os.Stat(filepath.Join(absRepo, "foundry.toml")); err == nil {
		// ok
	} else {
		// Not strictly foundry — caller might still want the map. Don't warn.
	}
	return out
}