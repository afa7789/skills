# Rust Rules

## Critical Conventions

- Use `thiserror` for library errors, `anyhow` only in binary crates or tests
- No `.unwrap()` or `.expect()` in production code — propagate errors with `?`
- Prefer `&str` over `String` in function parameters; return `String` when ownership transfers
- Use `clippy` with `#![deny(clippy::all, clippy::pedantic)]` — fix all warnings
- Derive `Debug` on all public types; derive `Clone`, `PartialEq` only when needed
- No `unsafe` blocks unless justified with a `// SAFETY:` comment

## Complexity gate

- `clippy::pedantic` (already denied above) covers `too_many_lines` (default 100 lines). Tighten it via `clippy.toml`: `too-many-lines-threshold = 50`. Lines-per-function is the per-function complexity signal clippy itself maintains as a measurement.
- Add `excessive_nesting` (in the `restriction` group, NOT covered by pedantic): `#![deny(clippy::excessive_nesting)]`. The default threshold (4) is fine.
- The clippy authors explicitly state `cognitive_complexity` is "not something we can calculate using modern technology" and have left it in `restriction` only to avoid misleading users — do not adopt it as a measurement gate. If you want a true cyclomatic/cognitive number, run a third-party tool outside the lint chain.
- Verify with `cargo clippy --all-targets -- -D warnings`. Fix by flattening `match`/guard structure or extracting helpers — not by splitting into trivial fns.

## Error Handling

Define a domain error enum per module with `thiserror`:
```rust
#[derive(Debug, Error)]
pub enum AppError {
    #[error("Resource not found")]
    NotFound,
    #[error("Validation failed: {0}")]
    Validation(String),
    #[error(transparent)]
    Internal(#[from] anyhow::Error),
}
```

Use `tracing` for structured logging — never `println!` or `eprintln!`.

## Code Style

- Max line length: 100 characters (enforced by rustfmt)
- Group imports: `std`, external crates, `crate`/`super` — separated by blank lines
- Modules: one file per module, `mod.rs` only for re-exports
- Types: PascalCase, functions/variables: snake_case, constants: UPPER_SNAKE_CASE

## Database (SQLx)

- All queries use `query!` or `query_as!` macros — compile-time verified
- Migrations via `sqlx migrate` — never alter the database directly
- Use `sqlx::Pool<Postgres>` as shared state — never create connections per request
- Parameterized placeholders (`$1`, `$2`) — never string formatting

## Testing

- Unit tests in `#[cfg(test)]` modules within each source file
- Integration tests in `tests/` with real database (Testcontainers or Docker)
- Use `#[sqlx::test]` for database tests with automatic migration and rollback
- Mock external services with `mockall` or `wiremock`

```bash
cargo test                    # Run all tests
cargo test -- --nocapture     # With output
cargo clippy -- -D warnings   # Lint
cargo fmt -- --check          # Format check
```

## Key Patterns

### Handler → Service → Repository
```rust
// Handler (thin)
async fn create_user(
    State(ctx): State<AppState>,
    Json(payload): Json<CreateUserRequest>,
) -> Result<(StatusCode, Json<UserResponse>), AppError> {
    let user = ctx.user_service.create(payload).await?;
    Ok((StatusCode::CREATED, Json(UserResponse::from(user))))
}

// Service (business logic)
impl UserService {
    pub async fn create(&self, req: CreateUserRequest) -> Result<User, AppError> {
        if self.repo.find_by_email(&req.email).await?.is_some() {
            return Err(AppError::Validation("Email already registered".into()));
        }
        let password_hash = hash_password(&req.password)?;
        self.repo.insert(&req.email, &req.name, &password_hash).await
    }
}
```
