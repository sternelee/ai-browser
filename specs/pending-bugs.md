# PENDING TASKS and BUGS

[ ] Need to change the toggle AI sidebar button next to the url bar to be a stars icon not a brain, and make sure it is there in the hoverable url bar as well as the persistent top url bar too
[ ] The AI sidebar must NOT appear/dissapear on hover, remove hover from that, we should only toggle it with the button
[ ] Settings has some hardcoded stuff, and the layout is a bit broken
[ ] AI is working bad, after this ("🚀 Model reloaded from cache: gemma-3n-E2B-it-Q8_0.gguf
🌊 Starting streaming with RAW prompt (preserving conversation context)...
✅ Using raw prompt with embedded conversation context
🌊 Starting REAL token-by-token streaming (ChatGPT-style)..." its stuck for a long time, nothing happens, the loading animation is not animating, and there is absolutely no streaming, and whats worse once its finished even tho in logs says "⚠️ Callback streaming failed, falling back to complete response
✅ RAW prompt streaming response completed: 182 characters
🌊 Streaming token: The union of state employees will strike next Wednesday, mobilizing from the Torre Ejecutiva to the Ministry of Economy and Finance. This strike will affect public services (total: 172 chars)
✅ Streaming completed: 172 characters") The message in the UI is empty
[ ] Delete history item doesn't delete it, and clear history also doesnt work
[ ] Remove the "share" button, it does nothing
[ ] Check that the AI has context of the history
[ ] 'Page content available' should update on every page change, right now as you change pages it doesn't change

--

Fix all the pending tasks and bugs in the pending bugs spec. One by one, first research files and internet for refs, then spin up a subagent to implement a solution, check the task/bug as for review and then move to the next one, 1 by 1, do all of them.
