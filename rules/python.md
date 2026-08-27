# Python Rules

## Coding Style

- Follow **PEP 8** conventions
- Use **type annotations** on all function signatures
- **black** for formatting, **isort** for imports, **ruff** for linting
- No `print()` in production code — use `logging` module

## Immutability

Prefer immutable data structures:
```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str
```

## Patterns

### Protocol (Duck Typing)
```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

### Dataclasses as DTOs
```python
@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

- Use context managers (`with`) for resource management
- Use generators for lazy evaluation and memory-efficient iteration

## Testing

- Use **pytest** as the testing framework
- Coverage: `pytest --cov=src --cov-report=term-missing`
- Use `pytest.mark` for test categorization (`@pytest.mark.unit`, `@pytest.mark.integration`)

## Security

- Use `os.environ["KEY"]` (raises KeyError if missing) over `os.getenv()`
- Use **bandit** for static security analysis: `bandit -r src/`

## Complexity gate

- ruff: enable `C901` (`complex-structure`, mccabe) — add `"C901"` to `select` and set `[lint.mccabe] max-complexity = 10` in `ruff.toml`/`pyproject.toml`.
- No ruff in the project → measure with `radon cc -nc src/` (grade C or worse = finding).
- Done = `ruff check` exits 0. Prefer dict-dispatch and guard clauses over if-chains; never split one messy function into trivia to pass.

## Hooks

- **black/ruff**: Auto-format `.py` files after edit
- **mypy/pyright**: Run type checking after editing `.py` files
