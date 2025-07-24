# Context Extraction Robustness Upgrade

## Objective
Ensure the AI always receives a rich, accurate representation of the current webpage – even on highly-dynamic sites like Reddit or Twitter that lazy-load content after initial paint.

## Changes Implemented (2025-07-24)
1. **`ContextManager.triggerLazyLoadScroll()`**
   • Programmatically scrolls the page to the bottom (twice) and back to the top to trigger virtualised / lazy-loaded DOM nodes.<br>
   • Executed on the main actor to respect WebKit thread-affinity.
2. **Adaptive Retry Logic** in `performContentExtraction(from:tab:)`
   • After the first retry, if extracted text is still < 300 chars regardless of domain, the lazy-load scroll is triggered, we wait 1.5 s, and a final extraction attempt is made.
3. **Removed Domain Allow-List**
   • The heuristic is now fully domain-agnostic; no hard-coded site names remain.

## Rationale
Many modern websites only render their main post/feed content after a user scrolls. The initial DOM therefore contains negligible text, causing the AI prompt to lack substance. By simulating a quick scroll we:

• Trigger client-side fetches / virtual list rendering.
• Keep the implementation fully client-side – no additional requests or third-party services.
• Maintain privacy (no network calls) and performance (single scroll event).

## Limitations & Future Work
• The 1.5 s wait is heuristic; we could observe `document.readyState` or MutationObservers for finer control.
• Very long infinite-scroll pages are intentionally **not** fetched entirely – we just need enough representative content (~few thousand chars) for the AI to answer questions.

---

_Last updated: 2025-07-24_ 