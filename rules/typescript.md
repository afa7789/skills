# TypeScript/JavaScript Rules

## Coding Style

- **Immutability**: Use spread operator for updates, never mutate parameters
- No `console.log` in production code — use proper logging libraries
- Use Zod for schema-based input validation
- Async/await with try-catch for error handling — throw user-friendly error messages

## Patterns

### API Response Format
```typescript
interface ApiResponse<T> {
  success: boolean
  data?: T
  error?: string
  meta?: { total: number; page: number; limit: number }
}
```

### Repository Pattern
```typescript
interface Repository<T> {
  findAll(filters?: Filters): Promise<T[]>
  findById(id: string): Promise<T | null>
  create(data: CreateDto): Promise<T>
  update(id: string, data: UpdateDto): Promise<T>
  delete(id: string): Promise<void>
}
```

## Testing

- Use **Playwright** for E2E testing of critical user flows
- Unit tests with Vitest or Jest

## Security

- Never hardcode secrets — always use environment variables
- Validate all external input at system boundaries
- Use parameterized queries for database access

## Hooks

Configure in `~/.claude/settings.json`:
- **Prettier**: Auto-format JS/TS files after edit
- **TypeScript check**: Run `tsc` after editing `.ts`/`.tsx` files
- **console.log warning**: Warn about `console.log` in edited files
