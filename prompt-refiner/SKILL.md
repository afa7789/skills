---
name: prompt-refiner
description: Iterative prompt refinement methodology. Sharpens vague ideas into specific, actionable prompts before sending to architect or other agents. Use before Phase 1 of any pipeline.
---

# Prompt Refiner — Iterative Refinement System

Pre-planning methodology for turning vague ideas into sharp, specific prompts that agents can execute against.

## When to Use

- You have a fuzzy idea but not a clear spec
- Before invoking the architect agent
- When requirements are ambiguous or incomplete
- When you want to explore what you actually want before committing to a plan

## Iterative Refinement Cycle

For each iteration, produce these three sections:

### 1. Prompt Draft

Write the best possible prompt based on current understanding. It should include:
- Clear task description
- Expected output format
- Relevant constraints and requirements
- Scope boundaries (what's in, what's out)
- Success criteria

### 2. Critique

Provide a constructive critique of your own draft:
- What assumptions are baked in?
- What ambiguities remain?
- What edge cases aren't covered?
- What would an agent misinterpret?
- What's missing that would cause the wrong output?

Be harsh — even if the prompt looks good, find weaknesses.

### 3. Questions

Ask up to 3 questions to gather information that would improve the prompt:
- Missing context or requirements
- Unclear objectives or scope
- Specific preferences for output
- Domain-specific details needed

## Cycle Rules

1. **Start with questions** — first response is only a greeting + questions to understand what the prompt should be about
2. **Iterate until satisfied** — each round produces a better draft
3. **User controls the loop** — user provides feedback, you refine
4. **Converge on specificity** — each iteration should be more concrete than the last
5. **Stop when actionable** — the prompt is done when an agent could execute it without asking clarifying questions

## Quality Checklist

A refined prompt should have:
- [ ] Clear role/context for the receiving agent
- [ ] Specific deliverables (not "make it good")
- [ ] Constraints stated explicitly (tech stack, timeline, scope)
- [ ] Success criteria that can be verified
- [ ] No ambiguous pronouns or vague references
- [ ] Edge cases acknowledged

## Example Flow

```
User: "I want to build something for managing recipes"

Iteration 1:
  Prompt: "Build a recipe management web app..."
  Critique: No target user, no tech constraints, no scope limit
  Questions: Who uses this? Web or mobile? How many recipes?

User: "It's for home cooks, web only, maybe 100-500 recipes per user"

Iteration 2:
  Prompt: "Build a web app for home cooks to store and organize
           100-500 personal recipes with search and tags..."
  Critique: No data model hints, no mention of import/export
  Questions: Do users share recipes? Import from URLs? Meal planning?

User: "Yes sharing, yes URL import, no meal planning for now"

Iteration 3:
  Prompt: [Specific, scoped, ready for architect]
  Critique: Minor — could specify auth method
  Questions: None critical — ready to ship to architect
```

## Output

The final refined prompt goes directly to the architect agent or into the orchestrator as the project brief. It replaces the vague initial idea with something an agent can plan against without guessing.
