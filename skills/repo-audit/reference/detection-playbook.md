# Detection playbook

Systematic techniques every scope agent applies. Language, framework and architecture agnostic — translate the vocabulary to whatever the repo actually uses.

## The deletion-first ladder

Before proposing any new abstraction, layer, helper, interface, adapter, service, component, state machine, configuration entry or file, consider in this order:

1. **remove**
2. **inline**
3. **consolidate**
4. **reuse something existing**
5. **simplify the flow**
6. only then **introduce a new abstraction**

An abstraction stays only when there is a concrete justification:

- security requirement;
- independent business rule;
- isolation of an external integration or boundary;
- multiple real implementations;
- significant reduction of duplication;
- an existing architectural requirement;
- concrete correction or prevention of bugs.

Not sufficient on their own:

- "might be useful in the future";
- "it is more extensible";
- "it is more enterprise";
- "it enables future implementations";
- "it separates concerns", without a demonstrated concrete gain.

---

## 1. Single-use abstractions

Look for: interfaces with one implementation; factories producing one type; strategies/providers/adapters with one real implementation; wrappers with one consumer; helpers with one call site; hooks/composables that only displace trivial logic; services that only forward calls.

Mandatory question:

> Would removing this abstraction keep the behavior equally correct **and** make the flow easier to understand?

If yes, consider inline or consolidation.

## 2. Pass-through layers

Look for chains like `controller -> service -> manager -> adapter -> client`, or the equivalent in any architecture.

An intermediate layer must justify itself with at least one real responsibility: business rule, data transformation, security, validation, caching, retry, meaningful observability, or isolation of an external boundary. If it only forwards parameters and return values, consider removing it.

## 3. Excessive fragmentation

Look for: trivial files; components that only wrap another component; modules that always change together; several files needed to understand one simple operation; files that exist only to re-export other files; architectural separations with no independent responsibility.

Prefer high cohesion over artificial fragmentation.

## 4. Indirection budget

For important flows, count the levels between `input -> business rule -> effect`. Investigate simple flows that require navigating many interfaces, factories, services, managers, adapters, repositories or wrappers.

No hard limit — treat excess hops as a signal of accidental complexity.

## 5. Premature generalization

Look for machinery built for scenarios that do not exist: plugin systems, registries, generic repositories, event buses, configurable pipelines, hand-rolled dependency injection, strategy engines, generic factories, state machines, multi-provider abstractions.

Determine how many concrete variants exist **today**. Infrastructure supporting many hypothetical scenarios with exactly one real one is a simplification candidate.

## 6. Configuration surface

Audit configuration and environment variables for: variables with no consumers; old aliases; flags permanently on or off; options with only one currently valid value; duplicated configuration; conflicting defaults; flags tied to completed migrations; configuration exposed with no real operational need.

Reduce configuration when direct behavior suffices.

## 7. Legacy compatibility

Search explicitly for: `deprecated`, `legacy`, `fallback`, `compat`, `old`, `temporary`, `migration`, removal TODOs, old aliases, old routes, old schemas, compatibility adapters, previous versions kept in parallel.

Determine whether a known consumer still exists. If not, prefer complete removal over maintaining two paths indefinitely.

## 8. Dead code by reachability

Do not stop at symbols the compiler marks unused. Look for: exports with no consumers; unregistered handlers; unmounted routes; impossible branches; dead feature flags; unreachable components; types not participating in any executable flow; code referenced only by dead code; documentation of features with no reachable implementation.

## 9. Conceptual duplication

Look for multiple representations of one concept: equivalent types; identical DTO/model/entity; duplicated enums; different error formats; multiple status representations; several abstractions for money, IDs, dates or other core values; repeated conversions between equivalent structures.

With no real boundary between them, prefer one canonical representation.

## 10. State simplification

Check for: stored derived state; correlated booleans; impossible states; data duplicated across stores; local cache with no need; manual synchronization of values that could be derived; global state used only locally; state machines for flows that are simple enough without one.

Prefer derivation over synchronization.

## 11. Error-path simplification

Look for: catch + rethrow adding no information; errors converted repeatedly between layers; enums that only mirror a dependency's errors; Result wrappers with no concrete benefit; multiple messages for the same condition; abstractions created solely to transport errors.

Keep error translation mainly at the boundaries where it is necessary.

## 12. Dependency audit

Identify dependencies that: serve trivial functionality; duplicate native platform APIs; introduce a large conceptual surface; require a bespoke adapter with no clear benefit; remain installed with no consumers.

Judge total complexity, not dependency count. Do not propose replacing mature libraries with in-house implementations when that increases risk or maintenance.

## 13. Test complexity

Look for tests that exist only as a consequence of over-fragmented architecture: cascading mocks; tests of pass-through wrappers; tests of trivial factories; tests asserting internal details; mocking several layers to exercise one simple operation.

Prefer behavior tests at real boundaries.

## 14. Documentation as a complexity detector

Compare documentation against the current code. Look for: documented components that do not exist; planned features described as implemented; different names for the same concept; diagrams with layers that carry no concrete responsibility; specifications with no implementation; documentation of legacy paths; documentation that is far more complex than the flow it explains.

The current code is the source of truth for implemented behavior.

---

## 15. No-ops

An instruction the model already obeys by default pays load to say nothing. Go sentence by
sentence and ask: **does this change behaviour versus the default?**

The test is model-relative, not reader-relative. Two people disagreeing about a no-op disagree
about the default, and they settle it by running the document, not by arguing. When a sentence
fails, delete the whole sentence rather than trimming words from it.

Common shapes: a rationale clause explaining why a step exists ("— reduces context"); an
instruction the environment already enforces (a prohibition on something the tool makes
impossible); a role restatement of the frontmatter description; trigger phrases restated in the
body, where they steer nothing because the skill has already fired; an aside addressed to a
future editor rather than to the running agent; a claim about the document's own structure.

This also grades leading words: a word too weak to beat the default ("be thorough" when the
agent is already thorough-ish) is a no-op, and the fix is a stronger word, not a different
technique.

## 16. Negation

Steering by prohibition drags the forbidden behaviour into context and makes it **more**
available, not less. The negation is a weak modifier that the strongly-activated concept
overruns, so the ban half-reads as an instruction to do the thing.

For every prohibition, ask whether it can be stated as the target behaviour instead. A
prohibition earns its place only as a hard guardrail that cannot be phrased positively — and
even then it must be paired with the positive target, adjacent, so attention lands on what to
do.

Count the mentions: a document that names one forbidden act four times inside one region has
made that act maximally available in exactly the region where it fires. That count is the
finding, and the fix is usually to delete three of the four and let a structural constraint
carry the rule (an output format with no slot for the forbidden thing beats any number of
sentences forbidding it).

## 17. Leading words

A leading word is a compact concept already in the model's pretraining that the agent thinks
with while running the document. Repeated as a token, never as a sentence, it accumulates a
distributed definition and anchors a whole region of behaviour in the fewest tokens.

Hunt the passages a single token would retire: a triad spelled out at three sites, a rule
restated in six places in slightly different words, a pointer spending a sentence to gesture at
one idea. Prefer a pretrained word over a coined one — a made-up word recruits nothing, so you
pay in definition tokens what an existing word gives free.

Two failure modes to report:
- **Divergent restatements.** When one rule exists in several wordings, one of them is usually
  looser than the rest, and an agent motivated to finish lands on the loosest available. Name
  which copy is the loose one; that is the defect, not the repetition.
- **Wrong prior.** A word recruiting the wrong pretrained meaning is worse than no word. Check
  what the term means in general usage, not only what this document means by it.

## 18. Completion criteria

Every step ends on a condition that tells the agent the work is done. Two properties make it a
lever, and both are auditable:

- **Clarity** — can the agent tell done from not-done? A vague bound invites *premature
  completion*: ending the step early, attention slipping to being done. The worst case is a
  bound no observation could establish, which is satisfied by believing it; flag every one, and
  flag hardest when it sits inside an exit condition.
- **Demand** — how much it requires. "Every modified model accounted for" forces thorough work
  where "produce a change list" does not. Demand is not step-bound: "every rule applied" binds a
  body of flat reference just as "every step done" binds a sequence.

A self-declared boolean (`status: done` written by the agent that decides it is done) has zero
demand. Bind each criterion to an artefact instead: the file, section or command output that
must exist.

Also audit the **post-completion steps**. Steps visible ahead supply the pull toward rushing the
one in front; the criterion's clarity is the resistance. A rendered exit template or a literal
exit token visible from load is maximal pull. Defend in order: sharpen the bound first, and only
split the sequence if it is irreducibly fuzzy *and* you observe the rush — and splitting clears
nothing unless it crosses a real context boundary.

Report the models as well as the defects: name the criteria in the document that are already
both checkable and exhaustive, so a fix has a local style to copy.

## 19. Invocation and the always-on budget

A skill's frontmatter description is the only always-loaded part and the sole trigger mechanism.
It is paid on every turn of every session whether the skill fires or not. Audit it as a
configuration surface:

- **Does every claim resolve?** A description advertising a capability the body does not
  implement fires the skill and answers nothing — worse than silence, because it consumed the
  invocation.
- **Does every phrase do triggering work?** Internal mechanism terms, pipeline summaries,
  coordination rosters and identity the body already carries cost tokens and trigger nothing.
- **Do sibling descriptions collide?** There is no native linter, so read them side by side. The
  generic phrasing usually belongs to the narrowest skill, which then outcompetes the right
  owner. The fix is an explicit negative scope naming the sibling that owns the adjacent case.
- **Must the agent reach it at all?** A skill only ever invoked by a human costs nothing if it is
  user-invoked (`disable-model-invocation: true`), which removes its description from the window
  entirely. Establish the answer by grep: a skill another skill or agent names must stay
  model-invoked, and that dependency chain is what breaks if the call is wrong.

## Heuristics

Signals for investigation, never absolute rules:

- interface with one implementation;
- wrapper with one consumer;
- helper with one call site;
- very small module with no independent responsibility;
- layer that only forwards arguments;
- many hops for one simple operation;
- structurally identical DTO/model/entity;
- configuration with only one effectively supported value;
- permanently fixed feature flag;
- old paths with no consumers;
- several files that always change together;
- abstractions created for future possibilities.

Never recommend a simplification purely because a metric was hit. Analyze the context.

---

## Rule against cosmetic refactors

Do not recommend changes that only move complexity around. Avoid recommending:

- renaming with no relevant gain;
- moving code between files with no simplification;
- swapping one pattern for an equally complex one;
- creating abstractions to "organize" simple code;
- splitting files purely by line count;
- helpers that hide trivial operations;
- introducing architectural frameworks;
- new layers to solve organizational problems.

Every relevant recommendation must reduce at least one of: concepts, files, states, branches, configuration, dependencies, indirection levels, execution paths, representations of the same data, public surface, or the amount of code needed to understand a flow.

The goal is not to minimize LOC. The goal is to reduce **cognitive complexity and maintenance surface without sacrificing correctness, security or clarity.**

Separate **essential complexity** from **accidental complexity**. Not every abstraction is bad — the ones that pay rent get `change_type: "retain"`.
