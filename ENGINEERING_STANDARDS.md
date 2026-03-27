# Engineering Standards (Non-Negotiable)

Apply the following principles throughout **every phase** of the roadmap. These are hard constraints, not suggestions:

| Principle | Expectation |
|---|---|
| **DRY** | No duplicated logic. Extract shared behavior into utilities, helpers, or base abstractions. |
| **KISS** | Favor the simplest solution that works. Avoid over-engineering. |
| **SOLID** | Apply all five principles — especially Dependency Inversion for infrastructure layers. |
| **SoC** | Clear separation between transport, business logic, domain, and data layers. |
| **TDD** | Tests are written before or alongside implementation — never after. |
| **Coverage ≥ 90%** | Unit + integration coverage must meet or exceed 90%. |
| **Clean Architecture** | The database provider must be swappable (Postgres, MySQL, CockroachDB, etc.) via interface/adapter — only the initially scoped providers will be implemented, but the structure must support future additions with zero core changes. |
| **Caching** | If the product is web-based, implement caching strategy (HTTP cache headers, Redis, in-memory, etc.) where appropriate. |
| **CI/CD Pipeline** | Must include: `lint → format → test → coverage report`. Fail fast on any violation. |
| **Makefile** | Provide targets at minimum: `build`, `run`, `clean`, `lint`, `test`. |
| **Test folder mirroring** | The test directory must mirror the source directory tree exactly. |
