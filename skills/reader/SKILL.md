---
name: reader
description: Advanced proofreading methodology for high-level writing analysis. Goes beyond spelling and grammar to identify structural issues, flow, crispness, and implicit meanings. Use with "proofread this", "advanced reading", or when needing deep document critique.
---

# Advanced Reader & Proofreading Methodology

This skill provides a set of high-level heuristics to identify writing mistakes that standard spellcheckers and basic AI proofreading often miss. It focuses on flow, succinctness, structural precision, and explicitness.

## How to Invoke

- "Load the reader skill and proofread this document."
- "Apply the reader methodology to myfile.md."
- "Advanced reading of this text, check for implicature."

---

## The 5 Rules of Advanced Reading

When analyzing a document, execute these steps systematically:

### 1. Contextual Sentence Fit (Flow)
Read every sentence. Determine if the sentence's idea fits logically between the surrounding sentences. 
- **Flag**: Sentences that are factually correct but disrupt the current flow or narrative thread.

### 2. Crispness & Succinctness
Read every sentence. Evaluate if it is as crisp and succinct as possible.
- **Constraint**: Do not suggest making sentences more succinct at the expense of descriptiveness or essential detail.

### 3. Header Precision
Read every header. Assess if it is precise and captures the true essence of the block it delineates.
- **Note**: Sentence fragments in headers are acceptable and should not be flagged as an issue.

### 4. Duplicate Detection (Short-Term Memory)
Read the article from start to finish, then read each sentence individually. 
- **Flag**: Any sentence that is essentially a duplicate of another stated earlier.
- **Exception**: Do not flag intentional reviews or reminders (e.g., "by way of review," "as we discussed earlier," "as a reminder").

### 5. Explicitness & Implicature
Read each sentence. Identify any words, phrases, or comparisons that carry implicature or insinuation. 
- **Flag**: Any non-explicit meaning. All intended meaning must be stated explicitly.

---

## Output Format

For each flagged item, provide:
1. **Location**: (e.g., Line number or section)
2. **Category**: (e.g., "Duplicate Detection", "Contextual Fit")
3. **Problem**: Clear explanation of the violation.
4. **Suggested Fix**: A concrete rewrite or structural change.
