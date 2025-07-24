# Page Context Enhancement Spec

## Objective
Provide richer, structured webpage context to the local LLM so that answers can be more accurate and grounded in the current page. This spec documents the strategy, data format and implementation details introduced in commit *context-enhancement*.

## Motivation
While the model is now very fast, the previous prompt only included the raw cleaned body text. By exposing additional signals (headings, links, word-count, etc.) and a short preview summary, we enable better reasoning and quoting without increasing prompt-engineering complexity. The 2B Gemma model handles larger contexts comfortably on Apple Silicon.

## Implementation Overview
1. **`maxContentLength` set to `0` (unlimited)** – no truncation; we trust downstream summarisation/prompt-building to stay within limits.
2. **New helper: `formatWebpageContext(_:)`** inside `ContextManager` that builds the structured section.
3. **`getFormattedContext`** now delegates to the helper and prepends history context after a separator.
4. Preview summarizer: first three sentences extracted naïvely for quick guidance.
5. Headings (max 12) & links (max 10) listed as bullet points for fast scanning.
6. All changes live in `Web/Services/ContextManager.swift`.

### Structured Section Example
```text
Current webpage context:
Title: A Deep Dive into Swift Concurrency
URL: https://swift.org/blog/concurrency
Word Count: 4 231

Outline (headings):
- h1: A Deep Dive into Swift Concurrency
- h2: Structured Concurrency
- h2: Async / Await
(...)

Prominent links:
- Swift Forums (https://forums.swift.org)
- Proposal SE-0300 (https://github.com/apple/swift-evolution)

Preview:
Swift 5.5 introduced first-class concurrency support. This article explores the key building blocks of the new model. You will learn how tasks, actors and structured concurrency fit together.

Full content (truncated to 24000 chars):
<cleaned body text>
```
> Note: `truncateContent` now returns the full text when the limit is 0, effectively disabling truncation. We can re-enable by setting a non-zero value if memory pressure becomes an issue.

## File Tree Changes
```
Web/Services/ContextManager.swift   # core logic updates
specs/page-context-enhancement-spec.md  # this document
```

## Roll-out Plan
1. Code merged → run full test suite.
2. Manually browse a complex site (e.g. Reddit thread) and verify the structured context in debug logs.
3. Monitor token usage to ensure prompts stay within 8 k tokens.

## Future Work
* Implement smarter extractive summariser (MMR) when we upgrade to Phase 11 (Context Processing).
* Allow per-site context rules via plug-ins. 