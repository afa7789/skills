# Svelte 5 / SvelteKit Rules

## Svelte 5 Runes

- `$state` for reactive state, `$derived` for computed values, `$effect` for side effects
- `$props()` for component props (not `export let`)
- `$bindable()` for two-way binding props
- Reactive state files go in `.svelte.ts` in `$lib/state/` — never mix with pure `.ts` utils

```svelte
<script lang="ts">
  let { name, count = $bindable(0) } = $props()
  let doubled = $derived(count * 2)

  $effect(() => {
    console.log('count changed:', count)
  })
</script>
```

## Event Handlers

- Use `onclick` not `on:click` (Svelte 5 syntax)
- Prefix handler functions with "handle" (e.g., `handleClick`, `handleSubmit`)

## SvelteKit Routing

- File-based: `+page.svelte`, `+layout.svelte`, `+error.svelte`, `+server.ts`
- Data loading: `+page.ts` (universal) or `+page.server.ts` (server-only)
- Form actions with progressive enhancement via `use:enhance`
- Never share mutable state on the server between requests

## Control Flow

```svelte
{#if condition}...{:else}...{/if}
{#each items as item (item.id)}...{/each}
{#await promise}...{:then value}...{:catch error}...{/await}
{#snippet name()}...{/snippet}
{@render name()}
```

## Component Patterns

- Props: destructure with `$props()`
- Children: `let { children } = $props()` then `{@render children?.()}`
- Path aliases: `$lib/components`, `$lib/utils`, `$lib/types`

## Styling

- Prefer Tailwind classes over `<style>` tags
- Use `class:` directives over ternary operators for conditional classes
- `h-dvh` not `h-screen` for full-height layouts
- Animations with `motion-safe:` prefix
- Content grids: `lg:grid-cols-2`, page content: `max-w-7xl mx-auto`

## TypeScript

- Strict mode mandatory (`noUncheckedIndexedAccess: true`)
- Guard all array/object index access
- Use `lang="ts"` in all script blocks

## API & Error Handling

- File uploads: native `fetch()` with `FormData` (openapi-fetch breaks with multipart)
- Use helper functions for error handling (e.g., `getErrorMessage(error, fallback)`)

## Testing

- Co-locate tests with components: `.svelte.test.ts`, `.ssr.test.ts`
- Use `page.getBy*()` locators — avoid container queries
- For multiple elements: `.first()`, `.nth()`, `.last()`
- Wrap `$derived` access with `untrack()` in tests
- Use real `FormData`/`Request` objects, not mocks

## i18n (Paraglide)

- Keys: `{domain}_{feature}_{element}`
- Import: `import * as m from '$lib/paraglide/messages'`
- Add keys to ALL locale directories

## Dev Commands

```bash
pnpm dev          # Dev server
pnpm build        # Production build
pnpm check        # svelte-check (type checking)
pnpm lint         # Lint
pnpm test         # Run tests
```
