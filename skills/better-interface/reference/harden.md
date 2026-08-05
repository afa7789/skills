# Harden a frontend surface

Make the implemented flow resilient without redesigning it.

Check, in order:

1. Navigation and entry points: every action reachable from the entry point, unknown URLs rendering an explicit not-found view, content re-rendering when only a URL parameter changes, back/forward preserving state, and no action offered from more than one canonical surface. Run `check-wiring.mjs` from `frontend-audit` rather than inspecting this by eye.
2. Runtime and request failures: preserve user input, provide recovery, prevent duplicate submission, and handle stale or partial responses.
3. Content extremes: empty, one item, many items, long unbroken values, missing media, large numbers, and slow responses.
4. Localization: translated string growth, pluralization, date/number formats, RTL, and mixed-direction values.
5. Interaction boundaries: rapid actions, double clicks, cancellation, navigation during work, expired sessions, offline/reconnect, and permission changes.
6. Accessibility resilience: focus restoration, announcements, zoom/text resize, reduced motion, and keyboard completion.
7. Performance resilience: large lists, expensive effects, layout shift, and visible loading progress.

Load the owning `better-*` skills for each confirmed issue. Add focused tests for failures that can regress. Run the quick visual gate when implementation changes.
