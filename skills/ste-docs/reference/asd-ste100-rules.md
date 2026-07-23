# ASD-STE100 — Simplified Technical English (Issue 9, January 2025)

A condensed, working reference for rewriting technical documentation. STE has two
parts: **Writing Rules** (53 rules) and a **Dictionary** (~900 approved words).
The goal: every reader — regardless of native language — reads the text the same
way. One meaning per word. One verb per action. No decoration, only instruction.

> This file is guidance for a rewriter. It is a faithful summary, not the legal
> standard. When a real project must certify compliance, use the official
> specification at https://asd-ste100.org.

---

## Core principles (apply everywhere)

1. **Use approved words only**, and only as their approved part of speech.
2. **One word, one meaning.** Never use an approved word with a second meaning.
3. **One thing, one word.** Use the same term for the same concept every time.
   Never introduce a synonym for variety.
4. **Active voice**, always in procedures; strongly preferred in descriptions.
5. **Short sentences.** Procedures ≤ 20 words. Descriptions ≤ 25 words.
6. **One instruction per sentence** in procedures.
7. **Simple tenses only** — infinitive, imperative, simple present, simple past,
   simple future. No progressive/perfect forms, no gerunds used as nouns.
8. **Say it plainly.** No slang, jargon, idioms, or metaphor.

---

## Writing rules by category

### Words (approved vocabulary)
- Choose words from the approved dictionary. If a needed general word is not
  approved, use its approved alternative (see table below).
- Use each approved word only as the part of speech listed for it
  (e.g. "test" as a verb only if listed as a verb).
- Keep to the one approved meaning of a word. Example: "follow" means "come
  after" — do not use it to mean "obey".
- Use approved **Technical Names** freely (nouns that name parts, tools,
  materials, places — e.g. "grease", "carburetor", "database index").
- Use approved **Technical Verbs** for manufacturing/technical processes when a
  general approved verb does not exist (e.g. "to drill", "to solder").
- Do not make a noun into a verb, or a verb into a noun, to get around the
  dictionary.

### Nouns and noun clusters
- **No more than three nouns in a cluster.** Break longer strings with
  prepositions and articles.
  - ✗ "runway light connection resistance calibration"
  - ✓ "calibration of the resistance for the runway-light connections"
- Do not drop articles (a, an, the) to save space. Use them.

### Verbs
- Use the **active voice**. State who does the action.
  - ✗ "The bolt must be removed."
  - ✓ "Remove the bolt." (procedure) / "The mechanic removes the bolt." (description)
- Use only the approved simple verb forms. No "-ing" verb as a noun or adjective
  (a gerund/participle) unless it is an approved Technical Name.
  - ✗ "Before starting the engine…" → ✓ "Before you start the engine…"
- Use a verb, not a noun, to describe an action.
  - ✗ "Do an inspection of the valve." → ✓ "Inspect the valve."
- Do not use helper verbs to make complex tenses. Keep it simple.

### Sentences
- **Procedural sentence: 20 words maximum.**
- **Descriptive sentence: 25 words maximum.**
- **One instruction per sentence.** If a step has two actions, write two
  sentences (or a vertical list).
- Start an instruction with the command word (the verb).
- Connect two related instructions only when they happen at the same time.
- Use a vertical list for a set of conditions or a long sequence of steps.

### Procedures (how-to text)
- Write each step as a command, in the imperative.
- Put only one action in each step, in the order it is done.
- Give a reason with the command only when the reason helps the reader.

### Descriptive writing (explanatory text)
- Keep sentences to 25 words or fewer.
- Use the simple present tense to describe how a thing works.
- Use paragraphs with one topic each.

### Paragraphs
- **One topic per paragraph.** State the topic in the first sentence.
- **Six sentences maximum** per paragraph.
- Do not use a paragraph for more than one idea.

### Warnings, cautions, and notes
- Put a **Warning** or **Caution** before the step it applies to, never after.
- Start it with a **clear command** that tells the reader what to do or not do.
  - ✓ "Warning: Do not touch the wire. The wire has a dangerous voltage."
- A **Note** gives information only. It must not contain an instruction.

### Punctuation and style
- Write **positive** statements. Avoid two negatives in one sentence.
  - ✗ "Do not use a fuse that is not approved." → ✓ "Use an approved fuse only."
- Keep to consistent spelling and hyphenation (as in the dictionary).
- Do not use abbreviations or acronyms that the reader may not know; define them
  on first use, then use them consistently.
- Do not omit words (articles, "that", relative pronouns) to shorten text.

---

## Not approved → approved (common replacements)

Use this table for the most frequent offenders in software/technical docs.

| Not approved | Use instead |
|---|---|
| utilize, employ | use |
| commence, initiate, begin | start |
| terminate, cease | stop / end |
| assist, aid | help |
| attempt | try |
| obtain, acquire | get |
| require | need |
| possess | have |
| indicate, denote | show |
| additional, extra, supplementary | more |
| sufficient, adequate | enough |
| approximately | about |
| prior to, in advance of | before |
| subsequent to, following | after |
| in order to | to |
| in the event that | if |
| in the case of | for / if |
| due to the fact that, because of the fact that | because |
| however, nevertheless, nonetheless | but |
| therefore, thus, hence, consequently | so |
| furthermore, moreover, in addition | also |
| e.g. | for example |
| i.e. | that is |
| via | with / by / through |
| ensure | make sure |
| perform, execute (an action) | do |
| modify, alter | change |
| verify | check / make sure |
| permit | let |
| numerous, several, various | many |
| approximately, roughly | about |
| leverage | use |
| regarding, concerning | about |

> This table is a starting set, not the full dictionary. When a word is not here
> and you are unsure, keep the technical name or **flag the sentence** — do not
> invent an "approved" word.

---

## Self-check (run on every rewritten file)

Read the file once as a whole, then check each item:

- [ ] Every general word is an approved word, used as its approved part of speech.
- [ ] The same term is used for the same thing throughout — no synonyms.
- [ ] Every instruction is in the active, imperative voice.
- [ ] No procedural sentence is longer than 20 words.
- [ ] No descriptive sentence is longer than 25 words.
- [ ] Each procedure step has exactly one instruction.
- [ ] No verb is in a progressive/perfect tense; no gerund used as a noun.
- [ ] No noun cluster has more than three nouns.
- [ ] Each paragraph has one topic, stated first, and ≤ 6 sentences.
- [ ] Warnings/cautions come before the step and start with a command.
- [ ] No double negatives; statements are positive.
- [ ] Articles and connecting words are present (nothing omitted to save space).
- [ ] Code, commands, paths, identifiers, and proper names are unchanged.

Any item that fails and cannot be fixed without changing meaning → **flag it**
with `file:line` and the reason. Never guess.

---

## What STE does NOT change

- Facts, data, numbers, and the meaning of the text.
- Code blocks, inline code, commands, URLs, file paths, and identifiers.
- Proper nouns and product/technical names.
- Front-matter, table data, and doc-tooling tags (`@param`, `:returns:`, etc.).
- The document's language — STE is controlled English; do not translate.
