// ── MCP · store — server catalog data + Agent-driven actions ───────────────
//
// MCP is a read-only, Agent-First panel. Configuration lives in mcp.json; this
// store fetches the catalog, probes servers for their tool list, toggles the
// enabled flag, and removes entries. It never renders.
//
// Holds catalog data, expand state, and a tools cache. Emits store events the
// view reacts to; mirrors them to the extension bus via Clacky.ext.emit.
//
// `Mcp` stays the single public facade.
//
// Depends on: Sessions, Clacky.ext.
// ───────────────────────────────────────────────────────────────────────────

const McpStore = (() => {
  let _data = null;
  const _expanded = new Set();
  const _toolsCache = new Map();

  const _listeners = {};

  function _on(event, handler) {
    (_listeners[event] ||= []).push(handler);
    return () => {
      const list = _listeners[event];
      const i = list ? list.indexOf(handler) : -1;
      if (i >= 0) list.splice(i, 1);
    };
  }

  function _emit(event, payload) {
    (_listeners[event] || []).forEach((h) => h(payload));
    if (window.Clacky && Clacky.ext) Clacky.ext.emit(event, payload);
  }

  const state = {
    get data() { return _data; },
    get expanded() { return _expanded; },
    isExpanded(name) { return _expanded.has(name); },
    cachedTools(name) { return _toolsCache.get(name); },
    hasCachedTools(name) { return _toolsCache.has(name); },
  };

  async function _sendToAgent(command, sessionName) {
    try {
      await Sessions.startWith(command, { name: sessionName });
    } catch (e) {
      Modal.toast("Error: " + e.message, "error");
    }
  }

  const Mcp = {
    on: _on,
    state,

    async load() {
      _emit("mcp:loading");
      try {
        const res = await fetch("/api/mcp");
        _data = await res.json();
        _emit("mcp:changed", { data: _data });
      } catch (e) {
        _emit("mcp:error", { message: e.message });
      }
    },

    /** Fetch a server's tool catalog (cached). Returns { ok, tools, error }. */
    async probe(name) {
      if (_toolsCache.has(name)) return { ok: true, tools: _toolsCache.get(name) };
      try {
        const res  = await fetch(`/api/mcp/${encodeURIComponent(name)}/probe`, { method: "POST" });
        const data = await res.json();
        if (!res.ok || !data.ok) return { ok: false, error: data.error || "unknown" };
        const tools = data.tools || [];
        _toolsCache.set(name, tools);
        return { ok: true, tools };
      } catch (e) {
        return { ok: false, error: e.message };
      }
    },

    toggleExpand(name) {
      if (_expanded.has(name)) _expanded.delete(name);
      else _expanded.add(name);
      _emit("mcp:changed", { data: _data });
    },

    async toggle(name, enabled) {
      try {
        const res = await fetch(`/api/mcp/${encodeURIComponent(name)}/enabled`, {
          method:  "PATCH",
          headers: { "Content-Type": "application/json" },
          body:    JSON.stringify({ enabled }),
        });
        const data = await res.json();
        if (!res.ok || !data.ok) {
          _emit("mcp:actionError", { kind: "toggle", message: data.error || `HTTP ${res.status}` });
          return;
        }
        if (!enabled) {
          _toolsCache.delete(name);
          _expanded.delete(name);
        }
        await Mcp.load();
      } catch (e) {
        _emit("mcp:actionError", { kind: "toggle", message: e.message });
      }
    },

    async remove(name) {
      try {
        const res = await fetch(`/api/mcp/${encodeURIComponent(name)}`, { method: "DELETE" });
        const data = await res.json();
        if (!res.ok || !data.ok) {
          _emit("mcp:actionError", { kind: "remove", message: data.error || `HTTP ${res.status}` });
          return;
        }
        _toolsCache.delete(name);
        _expanded.delete(name);
        await Mcp.load();
      } catch (e) {
        _emit("mcp:actionError", { kind: "remove", message: e.message });
      }
    },

    resetCaches() {
      _toolsCache.clear();
      _expanded.clear();
    },

    askAdd()      { return _sendToAgent("/mcp-manager add", "MCP Setup"); },
    askFix(name)  { return _sendToAgent(`/mcp-manager reconfigure ${name}`, `MCP Fix — ${name}`); },
    sendToAgent:  _sendToAgent,
  };

  return Mcp;
})();

const Mcp = McpStore;
