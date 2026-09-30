// ── MCP · view — rendering + DOM wiring for the MCP servers panel ──────────
//
// Owns all row/status/tools rendering and event wiring. Reads through
// McpStore.state and reacts to store events. Probe / toggle / remove go through
// store actions; confirm dialogs and error alerts (UI concerns) live here.
//
// Augments the `Mcp` facade with onPanelShow.
//
// Depends on: McpStore, I18n, global $ helper.
// ───────────────────────────────────────────────────────────────────────────

const McpView = (() => {

  function _renderLoading() {
    const list = $("mcp-list");
    if (list) list.innerHTML = `<div class="channel-loading">${I18n.t("mcp.loading")}</div>`;
  }

  function _renderError(payload) {
    const list = $("mcp-list");
    if (list) list.innerHTML = `<div class="channel-error">${I18n.t("mcp.loadError", { msg: _esc(payload.message) })}</div>`;
  }

  const MORE_SVG = '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>';
  const CHEVRON_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg"><polyline points="9 6 15 12 9 18"/></svg>';
  const SERVER_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="6" rx="1"/><rect x="3" y="14" width="18" height="6" rx="1"/><path d="M8 7h.01M8 17h.01"/></svg>';
  // Same icon style as the sidebar session menu: 14px, 1.8 stroke.
  const MENU_ICONS = {
    fix:    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>',
    remove: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>',
  };

  let _menuEl = null;
  let _menuBtn = null;

  function _render() {
    const list = $("mcp-list");
    const data = McpStore.state.data;
    if (!list || !data) return;
    _closeMenu();

    list.innerHTML = "";

    if (!data.configured || !data.servers || data.servers.length === 0) {
      list.innerHTML = `
        <div class="mcp-empty">
          <h3>${I18n.t("mcp.empty.title")}</h3>
          <p>${I18n.t("mcp.cta.body")}</p>
        </div>
      `;
      return;
    }

    data.servers.forEach(server => {
      list.appendChild(_renderServer(server));
      // _renderTools looks the region up by id, so the row must be in the DOM first.
      if (McpStore.state.isExpanded(server.name) && !server.disabled) {
        _renderTools(server.name);
      }
    });
  }

  function _renderServer(server) {
    const isHttp = server.type === "http" || server.type === "streamable-http";
    const target = isHttp
      ? (server.url || "")
      : [server.command, ...(server.args || [])].filter(Boolean).join(" ");
    const isExpanded = McpStore.state.isExpanded(server.name) && !server.disabled;
    const toggleAria = I18n.t(server.disabled ? "mcp.toggle.off" : "mcp.toggle.on");

    const card = document.createElement("div");
    card.className = "mcp-card";
    if (server.disabled) card.classList.add("mcp-card-disabled");
    if (isExpanded) card.classList.add("mcp-card-expanded");
    card.id = `mcp-card-${_esc(server.name)}`;

    card.innerHTML = `
      <div class="mcp-card-head">
        <span class="channel-logo mcp-logo" aria-hidden="true">${SERVER_SVG}</span>
        <div class="channel-row-text">
          <div class="channel-row-name">
            <span class="channel-row-title">${_esc(server.name)}</span>
            <span class="mcp-chip">${isHttp ? "HTTP" : "stdio"}</span>
          </div>
          ${server.description ? `<div class="channel-row-desc" title="${_esc(server.description)}">${_esc(server.description)}</div>` : ""}
        </div>
        <div class="channel-row-action">
          <label class="toggle-switch" title="${_esc(toggleAria)}">
            <input type="checkbox" id="toggle-mcp-${_esc(server.name)}" ${server.disabled ? "" : "checked"} aria-label="${_esc(toggleAria)}">
            <span class="toggle-slider"></span>
          </label>
          <button type="button" class="channel-row-btn" data-mcp-more
            title="${_esc(I18n.t("channels.btn.more"))}" aria-haspopup="menu" aria-expanded="false">${MORE_SVG}</button>
        </div>
      </div>
      ${target ? `<code class="mcp-target" title="${_esc(target)}">${_esc(target)}</code>` : ""}
      <div class="mcp-card-foot">
        <button type="button" class="mcp-tools-btn" data-mcp-tools ${server.disabled ? "disabled" : ""} aria-expanded="${isExpanded}">
          ${I18n.t(isExpanded ? "mcp.btn.hide" : "mcp.btn.probe")}
          <span class="mcp-tools-chevron" aria-hidden="true">${CHEVRON_SVG}</span>
        </button>
      </div>
      <div class="mcp-tools-region" id="mcp-tools-${_esc(server.name)}" ${isExpanded ? "" : "hidden"}></div>
    `;

    card.querySelector("[data-mcp-tools]")
      .addEventListener("click", () => Mcp.toggleExpand(server.name));
    card.querySelector(`#toggle-mcp-${CSS.escape(server.name)}`)
      .addEventListener("change", (ev) => _toggle(server.name, ev.target.checked));
    const more = card.querySelector("[data-mcp-more]");
    more.addEventListener("click", (ev) => { ev.stopPropagation(); _toggleMenu(more, server.name); });

    return card;
  }

  // One shared floating menu: rows are rebuilt on every store change, so a
  // menu nested inside a row would vanish mid-interaction.
  function _toggleMenu(btn, name) {
    if (_menuBtn === btn && _menuEl && !_menuEl.hidden) { _closeMenu(); return; }
    _closeMenu();

    if (!_menuEl) {
      _menuEl = document.createElement("div");
      _menuEl.className = "ext-row-menu";
      _menuEl.setAttribute("role", "menu");
      _menuEl.addEventListener("click", _onMenuClick);
      document.body.appendChild(_menuEl);
    }
    const item = (kind, label, extra) =>
      `<button type="button" role="menuitem" class="ext-row-menu-item${extra || ""}" data-mcp-menu="${kind}" data-mcp-name="${_esc(name)}">${MENU_ICONS[kind]}<span>${_esc(label)}</span></button>`;
    _menuEl.innerHTML = item("fix", I18n.t("mcp.btn.askClacky")) + item("remove", I18n.t("mcp.btn.remove"), " ext-row-menu-danger");
    _menuEl.hidden = false;
    _menuBtn = btn;
    btn.setAttribute("aria-expanded", "true");

    const rect = btn.getBoundingClientRect();
    const w = _menuEl.offsetWidth;
    const h = _menuEl.offsetHeight;
    let top = rect.bottom + 4;
    if (top + h > window.innerHeight - 8) top = rect.top - h - 4;
    _menuEl.style.left = Math.max(8, Math.min(rect.right - w, window.innerWidth - w - 8)) + "px";
    _menuEl.style.top  = Math.max(8, top) + "px";
  }

  function _closeMenu() {
    if (!_menuEl || _menuEl.hidden) return;
    _menuEl.hidden = true;
    if (_menuBtn) _menuBtn.setAttribute("aria-expanded", "false");
    _menuBtn = null;
  }

  function _onMenuClick(e) {
    const item = e.target.closest("[data-mcp-menu]");
    if (!item) return;
    const name = item.getAttribute("data-mcp-name");
    const kind = item.getAttribute("data-mcp-menu");
    _closeMenu();
    if (kind === "fix") Mcp.askFix(name);
    else _remove(name);
  }

  async function _renderTools(name) {
    const region = document.getElementById(`mcp-tools-${name}`);
    if (!region) return;

    if (McpStore.state.hasCachedTools(name)) {
      region.innerHTML = _toolsHtml(McpStore.state.cachedTools(name));
      return;
    }

    region.innerHTML = `<div class="mcp-tools-loading">${I18n.t("mcp.toolsLoading")}</div>`;

    const result = await Mcp.probe(name);
    if (!result.ok) {
      region.innerHTML = `<div class="mcp-tools-error">${I18n.t("mcp.toolsLoadError", { msg: _esc(result.error) })}</div>`;
      return;
    }
    region.innerHTML = _toolsHtml(result.tools);
  }

  function _toolsHtml(tools) {
    if (!tools || tools.length === 0) {
      return `<div class="mcp-tools-empty">${I18n.t("mcp.toolsNone")}</div>`;
    }
    const items = tools.map(t => `
      <li class="mcp-tool-item">
        <code class="mcp-tool-name">${_esc(t.name)}</code>
        ${t.description ? `<span class="mcp-tool-desc">${_esc(t.description)}</span>` : ""}
      </li>
    `).join("");
    return `
      <div class="mcp-tools-header">${I18n.t("mcp.toolsHeader")} (${tools.length})</div>
      <ul class="mcp-tool-list">${items}</ul>
    `;
  }

  async function _toggle(name, enabled) {
    await Mcp.toggle(name, enabled);
  }

  async function _remove(name) {
    const confirmed = await Modal.confirm(I18n.t("mcp.remove.confirm", { name }));
    if (!confirmed) return;
    Mcp.remove(name);
  }

  function _esc(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function _onActionError(payload) {
    const key = payload.kind === "remove" ? "mcp.remove.error" : "mcp.toggle.error";
    Modal.toast(I18n.t(key, { msg: payload.message }), "error");
  }

  function _subscribe() {
    Mcp.on("mcp:loading", _renderLoading);
    Mcp.on("mcp:changed", _render);
    Mcp.on("mcp:error", _renderError);
    Mcp.on("mcp:actionError", _onActionError);
    // Runs at script load, before app.js defines the global `$` helper.
    document.getElementById("btn-mcp-cta")?.addEventListener("click", () => Mcp.askAdd());
    document.getElementById("btn-mcp-refresh")?.addEventListener("click", () => {
      Mcp.resetCaches();
      Mcp.load();
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest("[data-mcp-more]") && !e.target.closest(".ext-row-menu")) _closeMenu();
    });
    document.addEventListener("keydown", (e) => { if (e.key === "Escape") _closeMenu(); });
    window.addEventListener("resize", _closeMenu);
    window.addEventListener("scroll", _closeMenu, true);
  }

  const viewApi = {
    onPanelShow() { return Mcp.load(); },
  };

  return { init: _subscribe, api: viewApi };
})();

Object.assign(Mcp, McpView.api);
McpView.init();
