// Kept as lightweight duplicate for bundling reference. Main injected runtime lives in Swift string.
// M2/M3 enhanced agent runtime (lightweight mirror of Swift-injected version)
(function() {
  'use strict';
  const CHANNEL = 'agentBridge';
  if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers[CHANNEL]) {
    return;
  }

  function isVisible(el) {
    if (!el) return false;
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  }
  function roleFor(el) {
    const tag = (el.tagName || '').toLowerCase();
    if (el.getAttribute && el.getAttribute('role')) return el.getAttribute('role');
    if (tag === 'a') return 'link';
    if (tag === 'button') return 'button';
    if (tag === 'input') return 'input';
    if (tag === 'select') return 'select';
    if (tag === 'textarea') return 'textbox';
    return tag;
  }
  function nameFor(el) {
    return (el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('name'))) || (el.innerText || el.textContent || '').trim();
  }
  function toSummary(el, idx, hint) {
    const rect = el.getBoundingClientRect();
    return {
      id: String(idx),
      role: roleFor(el),
      name: nameFor(el),
      text: (el.innerText || el.textContent || '').slice(0, 200),
      isVisible: isVisible(el),
      boundingBox: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
      locatorHint: hint || null,
    };
  }
  // Generic network activity tracker (agnostic idle detection)
  (function installNetworkTracker(){
    try {
      if (window.__agentNetInstalled) return; window.__agentNetInstalled = true;
      window.__agentNet = { active: 0, lastChangeTs: Date.now() };
      const origFetch = window.fetch;
      if (typeof origFetch === 'function') {
        window.fetch = async function() {
          try { window.__agentNet.active++; window.__agentNet.lastChangeTs = Date.now(); } catch {}
          try { return await origFetch.apply(this, arguments); }
          finally { try { window.__agentNet.active = Math.max(0, window.__agentNet.active - 1); window.__agentNet.lastChangeTs = Date.now(); } catch {} }
        };
      }
      const OrigXHR = window.XMLHttpRequest;
      if (OrigXHR) {
        const Wrapped = function() {
          const xhr = new OrigXHR();
          const dec = () => { try { window.__agentNet.active = Math.max(0, window.__agentNet.active - 1); window.__agentNet.lastChangeTs = Date.now(); } catch {};
            xhr.removeEventListener('loadend', dec); xhr.removeEventListener('error', dec); xhr.removeEventListener('abort', dec);
          };
          xhr.addEventListener('loadstart', () => { try { window.__agentNet.active++; window.__agentNet.lastChangeTs = Date.now(); } catch {} });
          xhr.addEventListener('loadend', dec);
          xhr.addEventListener('error', dec);
          xhr.addEventListener('abort', dec);
          return xhr;
        };
        window.XMLHttpRequest = Wrapped;
      }
      window.__agentNetIsIdle = function(idleMs){
        try {
          const idle = typeof idleMs === 'number' ? idleMs : 500;
          const n = (window.__agentNet && window.__agentNet.active) || 0;
          const last = (window.__agentNet && window.__agentNet.lastChangeTs) || 0;
          return n === 0 && (Date.now() - last) >= idle;
        } catch { return false; }
      };
    } catch {}
  })();
  function findByLocator(locator) {
    if (!locator) return [];
    let nodes = [];
    let hint = '';
    try {
      if (locator.css) {
        nodes = Array.from(document.querySelectorAll(locator.css));
        hint = locator.css;
        // no site-specific fallbacks; remain page-agnostic
      } else {
        const role = (locator.role || '').toLowerCase();
        const hasNeedle = Boolean(locator.text || locator.name);
        const needle = (locator.text || locator.name || '').toLowerCase();

        let selector = 'a,button,input,select,textarea,[role],[contenteditable="true"]';
        if (role === 'textbox' || role === 'input' || role === 'searchbox') {
          selector = 'input, textarea, [contenteditable="true"], [role="textbox"]';
        } else if (role === 'button') {
          selector = 'button, [role="button"]';
        } else if (role === 'link') {
          selector = 'a, [role="link"]';
        } else if (role === 'select') {
          selector = 'select';
        } else if (role === 'article' || role === 'post') {
          // Generic article-like containers with common readable contexts (still agnostic)
          selector = 'article, [role="article"], main';
        }

        const candidates = Array.from(document.querySelectorAll(selector));

        function accessibleName(el) {
          try {
            const direct = (el.getAttribute('aria-label') || el.getAttribute('name') || el.getAttribute('title') || '').trim();
            const placeholder = (el.getAttribute('placeholder') || '').trim();
            const labelledById = el.getAttribute('aria-labelledby');
            let labelledText = '';
            if (labelledById) {
              const labelEl = document.getElementById(labelledById);
              if (labelEl) labelledText = (labelEl.innerText || labelEl.textContent || '').trim();
            }
            return [direct, placeholder, labelledText].filter(Boolean).join(' ').toLowerCase();
          } catch { return ''; }
        }

        nodes = candidates.filter(el => {
          if (!isVisible(el)) return false;
          if (role) {
            const r = roleFor(el).toLowerCase();
            if (role === 'textbox' && !(r === 'textbox' || r === 'input')) return false;
            if (role === 'article' || role === 'post') {
              const articleLike = r === 'article' || (el.matches && el.matches('[role="article"], article'));
              if (!articleLike) return false;
            } else if (role !== 'textbox' && r !== role) {
              return false;
            }
          }
          if (!hasNeedle) return true;
          const inner = ((el.innerText || el.textContent || '')).toLowerCase();
          const name = accessibleName(el);
          return inner.includes(needle) || name.includes(needle);
        });

        if (nodes.length === 0 && (role === 'textbox' || role === 'searchbox' || (!role && !hasNeedle))) {
          const prefer = Array.from(document.querySelectorAll('input[name="q"], input[type="search"], input[type="text"]')).filter(isVisible);
          if (prefer.length) nodes = prefer;
        }

        hint = locator.css || locator.text || locator.name || role || '';
      }

      if (typeof locator.nth === 'number' && nodes[locator.nth]) {
        return [nodes[locator.nth]];
      }
      return nodes;
    } catch (e) { return []; }
  }

  // Safety guards: never read password/PII by default
  function isSensitiveInput(el) {
    const type = (el.type || '').toLowerCase();
    const name = (el.name || '').toLowerCase();
    const id = (el.id || '').toLowerCase();
    const sensitiveNames = ['password', 'passcode', 'totp', 'otp', 'ssn', 'social', 'credit', 'card', 'cvv'];
    if (type === 'password') return true;
    return sensitiveNames.some(k => name.includes(k) || id.includes(k));
  }

  // Public API
  window.__agent = window.__agent || {};
  window.__agent.ping = function() {
    try { window.webkit.messageHandlers[CHANNEL].postMessage({ type: 'ping', ts: Date.now() }); } catch {}
  };
  window.__agent.findElements = function(locator) {
    try {
      let nodes = findByLocator(locator);
      let hint = locator && (locator.css || locator.text || locator.name) || '';
      const out = nodes.slice(0, 50).map((el, i) => toSummary(el, i, hint));
      return out;
    } catch (e) { return []; }
  };
  window.__agent.click = function(locator) {
    try {
      let el = (findByLocator(locator) || []).find(isVisible) || null;
      if (el && isVisible(el)) {
        // If element appears non-interactive, try a visible clickable descendant
        const tag = (el.tagName || '').toLowerCase();
        const role = roleFor(el);
        const isInteractive = tag === 'a' || tag === 'button' || role === 'link' || role === 'button' || typeof el.onclick === 'function';
        if (!isInteractive) {
          const clickable = el.querySelector && Array.from(el.querySelectorAll('a, [role="link"], button, [role="button"]')).find(isVisible);
          if (clickable) { clickable.click(); return { ok: true }; }
        }
        el.click();
        return { ok: true };
      }
      return { ok: false };
    } catch (e) { return { ok: false }; }
  };
  window.__agent.typeText = function(locator, text, submit) {
    try {
      const el = (findByLocator(locator) || []).find(isVisible) || null;
      if (!el || !isVisible(el)) return { ok: false };
      if (el.tagName && (el.tagName.toLowerCase() === 'input' || el.tagName.toLowerCase() === 'textarea' || el.isContentEditable)) {
        if (isSensitiveInput(el)) return { ok: false };
        el.focus();
        if (el.value !== undefined) {
          el.value = String(text || '');
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        } else if (el.isContentEditable) {
          el.textContent = String(text || '');
          el.dispatchEvent(new Event('input', { bubbles: true }));
        }
        if (submit) { const form = el.form || el.closest('form'); if (form) form.requestSubmit ? form.requestSubmit() : form.submit(); }
        return { ok: true };
      }
      return { ok: false };
    } catch (e) { return { ok: false }; }
  };
  window.__agent.select = function(locator, value) {
    try {
      const el = (findByLocator(locator) || []).find(isVisible) || null;
      if (!el || el.tagName.toLowerCase() !== 'select') return { ok: false };
      el.value = String(value || '');
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return { ok: true };
    } catch (e) { return { ok: false }; }
  };
  window.__agent.scroll = function(locator, direction, amountPx) {
    try {
      const amt = typeof amountPx === 'number' ? amountPx : 600;
      const dir = (direction || 'down').toLowerCase();
      const el = locator ? (findByLocator(locator) || [])[0] : null;
      const target = el || window;
      const dx = 0;
      const dy = dir === 'down' ? amt : dir === 'up' ? -amt : amt;
      if (target === window) { window.scrollBy({ left: dx, top: dy, behavior: 'smooth' }); }
      else { target.scrollBy({ left: dx, top: dy, behavior: 'smooth' }); }
      return { ok: true };
    } catch (e) { return { ok: false }; }
  };
  window.__agent.waitFor = async function(predicate, timeoutMs) {
    const start = Date.now();
    const timeout = typeof timeoutMs === 'number' ? timeoutMs : 5000;
    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    try {
      if (predicate && predicate.readyState === 'complete') {
        while (document.readyState !== 'complete') { if (Date.now() - start > timeout) return { ok: false }; await sleep(100); }
        return { ok: true };
      }
      if (predicate && predicate.selector) {
        while (true) {
          const node = document.querySelector(predicate.selector);
          if (node && isVisible(node)) return { ok: true };
          if (Date.now() - start > timeout) return { ok: false };
          await sleep(100);
        }
      }
      if (predicate && typeof predicate.delayMs === 'number') { await sleep(Math.min(predicate.delayMs, timeout)); return { ok: true }; }
    } catch (e) {}
    return { ok: false };
  };

  try { window.webkit.messageHandlers[CHANNEL].postMessage({ type: 'runtime_ready', version: 'm2' }); } catch {}
})();


