# Tauri Rules

## Project Structure

```
src/               # Frontend (web)
src-tauri/
  src/
    lib.rs         # Commands, state, plugin registration
    main.rs        # Entry point
  capabilities/    # Permission definitions
  tauri.conf.json  # App config, CSP, window settings
```

- **Naming**: snake_case for Rust files, PascalCase for components, kebab-case for CSS/HTML
- Separate frontend and backend concerns strictly

## Commands

- Use `#[tauri::command]` to expose Rust functions to frontend
- Register in `tauri::generate_handler![]`
- Invoke from frontend via `@tauri-apps/api/core`
- Keep commands focused and async — delegate complex logic to services
- Return `Result<T, E>` where E implements `serde::Serialize`

```rust
#[tauri::command]
async fn get_data(state: tauri::State<'_, AppState>) -> Result<Data, AppError> {
    state.service.fetch_data().await
}
```

## State Management

- Use `tauri::State<T>` with `Arc<Mutex<T>>` for shared mutable state
- Register state with `.manage()` in builder
- Never use unsafe global statics

## Error Handling

- Custom serializable error types with `thiserror`
- Errors cross the IPC boundary — make them meaningful, not generic strings

```rust
#[derive(Debug, thiserror::Error, serde::Serialize)]
pub enum AppError {
    #[error("Not found: {0}")]
    NotFound(String),
    #[error("Internal error")]
    Internal,
}
```

## Security

- **CSP**: Enforce strict Content Security Policy in `tauri.conf.json`
- **Capabilities**: Apply principle of least privilege — only enable permissions you need
- Keep secrets and sensitive logic in Rust backend only
- Validate all IPC inputs from frontend
- Use parameterized queries for any database access
- Regular dependency audits: `cargo audit`

## Events & IPC

- Use Tauri's event system for backend → frontend communication
- Commands for frontend → backend requests
- Keep payloads serializable and minimal

## Performance

- Offload CPU-intensive work to Rust backend
- Use `spawn_blocking` for heavy sync operations
- Async/await for I/O to avoid blocking the UI

## Testing

- Unit test Rust modules independently
- Integration tests simulating frontend interactions
- E2E tests with Playwright or Cypress
- Run `cargo test` for backend, framework test runner for frontend

## Build & Dev

```bash
pnpm tauri dev      # Full dev environment with hot reload
pnpm dev            # Vite server only (port 1420)
pnpm build          # Production build
cargo test          # Backend tests
cargo clippy        # Lint
```

## Cross-Platform

- Test on Windows, macOS, and Linux
- Use conditional compilation (`#[cfg(target_os = "...")]`) for platform-specific code
- Aim for minimal bundle sizes — audit dependencies
