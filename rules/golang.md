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

## Patterns

### Functional Options
```go
type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.port = port }
}

func NewServer(opts ...Option) *Server {
    s := &Server{port: 8080}
    for _, opt := range opts { opt(s) }
    return s
}
```

### Dependency Injection
```go
func NewUserService(repo UserRepository, logger Logger) *UserService {
    return &UserService{repo: repo, logger: logger}
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

## Hooks

- **gofmt/goimports**: Auto-format `.go` files after edit
- **go vet**: Run static analysis after editing `.go` files
- **staticcheck**: Run extended static checks on modified packages
