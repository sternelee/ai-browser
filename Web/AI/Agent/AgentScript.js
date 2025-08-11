(function() {
  'use strict';

  // M0: Minimal agent runtime scaffold. Validates presence and offers a ping.
  const CHANNEL = 'agentBridge';

  if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers[CHANNEL]) {
    console.warn('[AgentScript] agentBridge handler not available');
    return;
  }

  // Basic API surface to be expanded in M1+.
  window.__agent = window.__agent || {};
  window.__agent.ping = function() {
    try {
      window.webkit.messageHandlers[CHANNEL].postMessage({ type: 'ping', ts: Date.now() });
    } catch (e) {
      console.error('[AgentScript] ping failed', e);
    }
  };

  // Acknowledge injection
  try {
    window.webkit.messageHandlers[CHANNEL].postMessage({ type: 'runtime_ready', version: 'm0' });
  } catch (e) {
    console.error('[AgentScript] ready post failed', e);
  }
})();


