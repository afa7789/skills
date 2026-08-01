# Optimize frontend performance

Measure before changing code. Preserve behavior and design unless the user approves a tradeoff.

1. Reproduce the slow path with the project's profiler, browser performance tools, bundle report, or platform instrumentation.
2. Name the user-visible symptom and baseline: loading, interaction delay, layout shift, scrolling, memory, or animation jank.
3. Fix the largest verified cause first: payload and image size, render waterfalls, blocking work, repeated renders, unbounded lists, layout-triggering animation, or missing caching.
4. Prefer platform and framework primitives already present over a new optimization layer.
5. Re-measure with the same route, data, device/viewport, and cache condition.

For web, report LCP, INP, and CLS when available; do not invent measurements. Treat performance budgets as project decisions. Run the quick visual gate after changes to catch broken loading states or visual regressions.
