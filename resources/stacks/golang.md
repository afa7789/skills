# Go Rules

## Coding Style

- **gofmt** and **goimports** are mandatory — no style debates
- Accept interfaces, return structs
- Keep interfaces small (1-3 methods)
- Define interfaces where they are used, not where they are implemented

## Error Handling

Always wrap errors with context:
```go
if err != nil {
    return fmt.Errorf("failed to create user: %w", err)
}
```

## Testing

- Use standard `go test` with **table-driven tests**
- Always run with `-race` flag: `go test -race ./...`
- Coverage: `go test -cover ./...`

## Security

- Use `os.Getenv()` for secrets, fail fast if missing
- Use **gosec** for static security analysis: `gosec ./...`
- Always use `context.Context` for timeout control:
```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```

## Complexity gate

- golangci-lint: enable `gocyclo` (cyclomatic) — set `linters-settings.gocyclo.min-complexity: 10`. `gocognit` (cognitive) is the alternative; its default `min-complexity` is 30, set 10–15 when using it.
- Done = `golangci-lint run` exits 0. Prefer `switch` and early returns; splitting to dodge the metric is gaming it.

## Hooks

- **gofmt/goimports**: Auto-format `.go` files after edit
- **go vet**: Run static analysis after editing `.go` files
- **staticcheck**: Run extended static checks on modified packages
