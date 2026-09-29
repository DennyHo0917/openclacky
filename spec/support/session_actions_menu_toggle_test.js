"use strict";

// Regression harness for the sidebar session "···" actions menu toggle.
//
// Clicking the "···" button of the session whose menu is already open must
// close it (it used to close + reopen, i.e. flicker). Clicking another row's
// button switches menus, and clicking elsewhere still dismisses.
//
// The real sessions.js runs against a minimal DOM stub.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sourcePath = name => path.resolve(__dirname, "../../lib/clacky/web", name);

const autoStub = (extra = {}) => new Proxy(extra, {
  get: (target, key) => (key in target ? target[key] : () => {}),
});

class Element {
  constructor(tag = "div") {
    this.tagName = tag;
    this.style = { setProperty() {} };
    this.dataset = {};
    this.attrs = {};
    this.children = [];
    this.parentNode = null;
    this.classes = new Set();
    this._className = "";
    this._innerHTML = "";
    this._queried = {};
    this.textContent = "";
    this.classList = {
      add: n => this.classes.add(n),
      remove: n => this.classes.delete(n),
      toggle: (n, on) => (on ? this.classes.add(n) : this.classes.delete(n)),
      contains: n => this.classes.has(n),
    };
  }
  set className(v) { this._className = v; this.classes = new Set(v.split(/\s+/).filter(Boolean)); }
  get className() { return this._className; }
  set innerHTML(v) { this._innerHTML = v; if (v === "") this.children = []; }
  get innerHTML() { return this._innerHTML; }
  setAttribute(k, v) { this.attrs[k] = v; }
  removeAttribute(k) { delete this.attrs[k]; }
  addEventListener() {}
  removeEventListener() {}
  appendChild(child) { this.children.push(child); child.parentNode = this; return child; }
  append(...kids) { kids.forEach(k => this.appendChild(k)); }
  prepend(child) { this.children.unshift(child); child.parentNode = this; return child; }
  remove() {
    if (!this.parentNode) return;
    this.parentNode.children = this.parentNode.children.filter(c => c !== this);
    this.parentNode = null;
  }
  replaceChildren(...kids) { this.children = []; this.append(...kids); }
  insertBefore(child) { return this.prepend(child); }
  // Markup built via innerHTML is not parsed; hand out one stable stub per
  // selector so handlers attached to it (e.g. the "···" button) can be fired.
  querySelector(sel) { return this._queried[sel] || (this._queried[sel] = new Element()); }
  querySelectorAll() { return []; }
  getBoundingClientRect() { return { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 }; }
  contains() { return false; }
  closest() { return null; }
  focus() {}
}

function boot() {
  const nodes = {};
  const docListeners = [];
  const unrefTimeout = (fn, ms, ...args) => {
    const timer = setTimeout(fn, ms, ...args);
    if (timer.unref) timer.unref();
    return timer;
  };
  const body = new Element("body");
  const document = {
    createElement: tag => new Element(tag),
    createDocumentFragment: () => new Element("fragment"),
    getElementById: id => nodes[id] || (nodes[id] = new Element()),
    addEventListener: (type, fn, opts) => docListeners.push({ type, fn, once: !!(opts && opts.once) }),
    removeEventListener: (type, fn) => {
      const i = docListeners.findIndex(l => l.type === type && l.fn === fn);
      if (i >= 0) docListeners.splice(i, 1);
    },
    querySelector: sel => body.children.find(c => sel.startsWith(".") && c.classes.has(sel.slice(1))) || null,
    querySelectorAll: () => [],
    body,
  };

  const context = {
    console, Date, Map, Set, Math, JSON, Promise, URLSearchParams,
    setTimeout: unrefTimeout,
    clearTimeout,
    requestAnimationFrame: () => {},
    innerHeight: 800,
    innerWidth: 1200,
    document,
    fetch: async () => ({ ok: false, json: async () => ({}) }),
    I18n: { t: key => key, lang: () => "en" },
    WS: { onEvent() {}, setSubscribedSession() {}, send() {} },
    Clacky: {},
    $: id => document.getElementById(id),
    escapeHtml: s => String(s === undefined || s === null ? "" : s),
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    Router: autoStub(),
    Projects: autoStub({ all: () => [], getIconSvg: () => "" }),
    Tasks: autoStub(),
    Skills: autoStub(),
    Composer: autoStub({ text: () => "", chips: () => [] }),
    IME: autoStub({ track: () => ({ isComposing: () => false, dispose() {} }) }),
    alert() {},
  };
  context.window = context;
  context.globalThis = context;
  vm.createContext(context);

  vm.runInContext(fs.readFileSync(sourcePath("utils.js"), "utf8"), context);
  vm.runInContext(fs.readFileSync(sourcePath("sessions.js"), "utf8"), context);

  const Sessions = vm.runInContext("Clacky.Sessions", context);
  Sessions.setAll([row("a"), row("b")]);
  Sessions.renderList();
  const list = document.getElementById("session-list");

  const clickDots = id => {
    const item = list.children.find(c => c.dataset.sessionId === id);
    const btn = item.querySelector(".session-actions-btn");
    btn.onclick({ target: btn, stopPropagation() {} });
  };
  // Deliver a click that reaches document (i.e. anywhere outside the button).
  const clickElsewhere = () => {
    docListeners.filter(l => l.type === "click").forEach(l => {
      if (l.once) document.removeEventListener(l.type, l.fn);
      l.fn({ target: body });
    });
  };
  const openMenus = () => body.children.filter(c => c.classes.has("session-actions-menu"));
  const flush = () => new Promise(r => setTimeout(r, 5));
  return { clickDots, clickElsewhere, openMenus, flush };
}

const row = (id, extra = {}) => Object.assign({
  id, name: id, status: "idle", source: "manual",
  created_at: "2026-08-01T00:00:00+08:00",
  updated_at: "2026-08-01T00:00:00+08:00",
}, extra);

const menuOwners = menus => menus.map(m => m.dataset.sessionId);

async function tests() {
  // 1. The reported bug: a second click on the same "···" closes the menu.
  {
    const { clickDots, openMenus, flush } = boot();
    clickDots("a");
    await flush();
    assert.deepEqual(menuOwners(openMenus()), ["a"], "first click opens the menu");

    clickDots("a");
    assert.deepEqual(openMenus(), [], "second click on the same button closes the menu");

    await flush();
    clickDots("a");
    assert.deepEqual(menuOwners(openMenus()), ["a"], "third click reopens it");
  }

  // 2. Clicking another row's "···" switches to that row's menu.
  {
    const { clickDots, openMenus, flush } = boot();
    clickDots("a");
    await flush();
    clickDots("b");
    assert.deepEqual(menuOwners(openMenus()), ["b"], "menu switches to the other session");
  }

  // 3. Clicking elsewhere still dismisses the open menu.
  {
    const { clickDots, clickElsewhere, openMenus, flush } = boot();
    clickDots("a");
    await flush();
    clickElsewhere();
    assert.deepEqual(openMenus(), [], "outside click dismisses the menu");
  }
}

tests().then(
  () => console.log("session_actions_menu_toggle_test: ok"),
  err => { console.error(err); process.exit(1); }
);
