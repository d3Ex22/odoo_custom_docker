(function () {
  const VIEWS = ["odoo", "logs", "utils", "mail"];
  const LABEL = {odoo: "Odoo", logs: "Logs", utils: "Utils", mail: "Mail"};
  // colours of hub.css, read once (the favicon is drawn on a canvas and needs literal values)
  const cssVar = n => getComputedStyle(document.documentElement).getPropertyValue("--" + n).trim();
  const PALETTE = ["yellow", "cyan", "red", "purple", "green", "orange", "fg"].map(cssVar);
  const tabs = document.getElementById("tabs"), frames = document.getElementById("frames"), empty = document.getElementById("empty"), icon = document.getElementById("icon"), config = document.getElementById("config"), wait = document.getElementById("wait");
  let projects = [], current = null;   // current = {project, view}
  const port = location.port ? ":" + location.port : "";   // proxy on a non-default port (tests)
  const store = {
    get: k => { try { return localStorage.getItem("hub:" + k); } catch (e) { return null; } },
    set: (k, v) => { try { localStorage.setItem("hub:" + k, v); } catch (e) {} },
  };
  const byName = n => projects.find(p => p.name === n);
  const online = () => projects.filter(p => p.running);
  const viewsOf = p => VIEWS.filter(v => p[v]);
  const viewOf = p => { const v = store.get("view:" + p.name); return viewsOf(p).includes(v) ? v : "odoo"; };
  const pad2 = n => String(n).padStart(2, "0");
  const esc = s => String(s == null ? "" : s).replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));

  // ---- modal: one dialog at a time, resolved with the value of the clicked action (null = dismissed) ----
  const modal = (() => {
    const el = document.getElementById("modal"); let cur = null;
    function close(v) { el.classList.remove("on"); el.innerHTML = ""; const r = cur; cur = null; if (r) r(v); }
    function open({title, body, actions, color}) {
      return new Promise(res => {
        if (cur) cur(null);
        cur = res;
        el.innerHTML = '<div class="box"><div class="ttl">// ' + title + '</div><div class="bd">' + body + '</div><div class="acts">' +
          actions.map((a, i) => '<button class="' + (a.cls || "") + '" data-i="' + i + '">' + esc(a.label) + "</button>").join("") + "</div></div>";
        el.querySelector(".box").style.setProperty("--c", color || "var(--yellow)");
        el.querySelectorAll("button").forEach(b => b.addEventListener("click", () => { const a = actions[+b.dataset.i]; close(typeof a.value === "function" ? a.value(el) : a.value); }));
        el.classList.add("on");
      });
    }
    el.addEventListener("click", e => { e.stopPropagation(); if (e.target === el) close(null); });   // never counts as a click outside the config panel
    return {open, close, busy: () => !!cur,
            confirm: (title, body, ok, color) => open({title, body, color, actions: [{label: "cancel", value: false}, {label: ok || "ok", cls: "pri", value: true}]})};
  })();

  // one colour per project, the same as the primary colour of its terminals: chosen by its utils
  // entrypoint (p.color; PROJECT_COLOR or the next free one on a collision), else the hash of the
  // name — the same one as lib/theme.sh theme_project_color() (keep both in sync)
  function colors() {
    const out = {};
    for (const p of projects) {
      let h = 0; for (const ch of p.name) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
      out[p.name] = p.color || PALETTE[h % PALETTE.length];
    }
    return out;
  }

  // tab order: the user's (drag and drop, kept in localStorage), new projects at the end
  function sortProjects(list) {
    const order = (store.get("order") || "").split(",").filter(Boolean);
    const rank = n => { const i = order.indexOf(n); return i < 0 ? order.length : i; };
    return list.slice().sort((a, b) => rank(a.name) - rank(b.name) || a.name.localeCompare(b.name));
  }
  function moveTab(name, before) {   // drop `name` before `before` (null = at the end)
    const names = projects.map(p => p.name).filter(n => n !== name);
    names.splice(before ? names.indexOf(before) : names.length, 0, name);
    store.set("order", names.join(","));
    projects = sortProjects(projects);
    lastSig = ""; render();
  }

  function fromHash() {
    const m = location.hash.replace(/^#\/?/, "").split("/");
    let project = m[0] || "", view = VIEWS.includes(m[1]) ? m[1] : "";
    if (!online().length) return null;
    let p = byName(project);
    const held = p && p.start && ["starting", "restarting"].includes(p.start.state);   // (re)starting: stay on it
    if (!project || project === "_" || !p || !(p.running || held)) {
      const last = (store.get("last") || "").split("/")[0];
      p = byName(last); if (!p || !p.running) p = online()[0];
    }
    if (view && !p[view] && p.running) view = "";
    return {project: p.name, view: view || viewOf(p)};
  }

  function select(sel) {
    current = sel;
    if (!sel) { render(); return; }
    const want = "#" + sel.project + "/" + sel.view;
    if (location.hash !== want) history.replaceState(null, "", want);
    store.set("last", sel.project + "/" + sel.view);
    store.set("view:" + sel.project, sel.view);
    const id = "f-" + sel.project + "-" + sel.view;
    let f = document.getElementById(id);
    const host = byName(sel.project)[sel.view];
    if (!f && host) {
      f = document.createElement("iframe");
      f.id = id; f.dataset.project = sel.project;
      f.allow = "clipboard-read; clipboard-write; fullscreen";
      f.src = "http://" + host + port + "/";
      frames.appendChild(f);
    }
    [...frames.children].forEach(x => x.classList.toggle("active", x === f));
    render();
    waiting();   // the "odoo starting" panel only belongs to the odoo view: drop it at once when leaving it
  }

  function favicon(color, letter) {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><polygon points="6,0 32,0 32,26 26,32 0,32 0,6" fill="' + color + '"/>' +
      '<text x="16" y="23" font-family="monospace" font-weight="800" font-size="20" text-anchor="middle" fill="#000">' + letter + '</text></svg>';
    icon.href = "data:image/svg+xml," + encodeURIComponent(svg);
  }

  function dotClass(s, key) {
    if (!s) return "";
    if (key === "odoo") return !s.odoo || BLOCKED.includes(s.start) ? "off" : s.start === "errors" ? "warn" : "on";
    if (key === "db") return s.db ? "on" : "off";
    if (key === "ent") return s.enterprise === "ok" ? "on" : s.enterprise === "mismatch" ? "warn" : "off";
    return "";
  }
  // outcome of the last start: an error blocked Odoo (registry not loaded, process gone), a warning means it serves
  // but tracebacks were logged (a module failed to update...)
  const BLOCKED = ["failed", "dead"];
  const nErr = s => s.start_errors + " error" + (s.start_errors > 1 ? "s" : "");
  function startMark(s) {   // {mark, cls, text} or null when the last start went fine
    if (!s || !s.start) return null;
    if (BLOCKED.includes(s.start)) return {mark: "✖", cls: "err", text: s.start === "dead" ? "odoo exited at start" : "start failed: database not loaded" + (s.start_errors ? " (" + nErr(s) + ")" : "")};
    if (s.start === "errors") return {mark: "⚠", cls: "warn", text: "started with " + nErr(s) + " in the log"};
    if (s.start === "timeout") return {mark: "⚠", cls: "warn", text: "not ready when the start watch gave up"};
    return null;
  }
  function tooltip(s) {
    if (!s) return "no status yet";
    if (s.setup) return "first start: confirm the configuration (setup)";
    const sm = startMark(s);
    return ["odoo " + (s.odoo ? "running" : "stopped") + (sm ? " · " + sm.mark + " " + sm.text : s.start ? " · last start " + s.start : ""),
            "postgres " + (s.db ? "up" : "down"), "mcp " + (s.mcp ? "up" : "down"),
            "enterprise " + (s.enterprise === "ok" ? s.enterprise_version : s.enterprise === "mismatch" ? s.enterprise_version + " ≠ " + s.odoo_version : "missing"),
            "database " + (s.database || "multi-db"), "odoo " + s.odoo_version + (s.build ? "." + s.build : ""),
            s.env_version ? "environment v" + s.env_version + (envUpdate({status: s}) ? " → v" + s.env_update.available + " available" : "") : "",
            s.rebuild ? "REBUILD NEEDED" : ""].filter(Boolean).join("\n");
  }

  // ---- .env changed since the containers were created (status.env_changed) → propose the restart ----
  const proposed = {};   // project → signature of the change set already shown
  const snoozed = {};    // project → {KEY: value} saved from the Config panel and answered "later" there: not proposed again
  // severity of a .env change, from the "Applied by" help line of the key: 1 restart (blue), 2 rebuild (orange), 3 rebuild wiping the databases (red)
  const LEVEL = {1: {label: "restart", color: "var(--blue)"}, 2: {label: "rebuild", color: "var(--orange)"}, 3: {label: "wipe db", color: "var(--red)"}};
  const levelOf = (apply, wipe) => wipe ? 3 : apply === "rebuild" ? 2 : /compose/.test(apply) ? 1 : 0;
  const envPending = p => Object.entries((p.status && p.status.env_changed) || {});
  const envLevel = p => Math.max(0, ...envPending(p).map(([, v]) => levelOf(v.apply, v.wipe)));
  // what a saved / pending change needs; returns true when the stack was restarted (rebuild is typed in the utils terminal: the user answers its confirmation there)
  async function applyChanges(p, level, rows) {
    if (!level) return false;
    let body = "<table>" + rows.map(r => '<tr><td class="k">' + esc(r.key) + "</td><td>" + esc(r.from || "∅") + "<i>→</i>" + esc(r.to || "∅") + '</td><td class="ap">' + esc(LEVEL[r.level] ? LEVEL[r.level].label : r.apply) + "</td></tr>").join("") + "</table>";
    if (level === 3) body += '<p class="warn">PostgreSQL major changed: <code>rebuild</code> wipes every database of this project. Back them up first (<code>db backup</code>) and restore afterwards (<code>db restore --last</code>). The command is typed in the utils terminal and asks for confirmation.</p>';
    else if (level === 2) body += "<p>version stack changed: <code>rebuild</code> builds the missing images and recreates the containers (minutes). Databases and files kept. The command is typed in the utils terminal.</p>";
    else body += "<p>restart = <code>docker compose down</code> + <code>up -d</code>: containers recreated, terminals reset, databases and files kept.</p>";
    const actions = [{label: "later", value: false}];
    if (level === 1) actions.push({label: "restart env", cls: "pri l1", value: true});
    else if (p.running) actions.push({label: "rebuild in utils", cls: "pri l" + level, value: true});
    else body += '<p class="warn">project stopped: start it, then run <code>rebuild</code> in its utils terminal.</p>';
    const ok = await modal.open({title: "<b>" + esc(p.name) + "</b> · .env changed", body, actions, color: LEVEL[level].color});
    if (!ok) return false;
    if (level === 1) { await api("/api/restart?project=" + encodeURIComponent(p.name), {method: "POST"}); refresh(); return true; }
    await api("/api/rebuild?project=" + encodeURIComponent(p.name), {method: "POST"});
    if (p.utils) select({project: p.name, view: "utils"});
    return false;
  }
  function askRestart(p) {
    const pend = envPending(p); if (!pend.length) return;
    return applyChanges(p, envLevel(p), pend.map(([key, v]) => ({key, from: v.from, to: v.to, apply: v.apply, level: levelOf(v.apply, v.wipe)})));
  }
  // ---- newer release of the environment template (status.env_update) → propose env-update ----
  const envUpdate = p => (p.status && p.status.env_update && p.status.env_update.available) ? p.status.env_update : null;
  async function askUpdate(p) {
    const u = envUpdate(p); if (!u) return;
    const body = "<table><tr><td class=\"k\">environment</td><td>v" + esc(u.current) + "<i>→</i>v" + esc(u.available) + '</td><td class="ap">' + esc(u.rev) + (u.ref ? " @ " + esc(u.ref) : "") + "</td></tr></table>" +
      "<p><code>env-update</code> refreshes <code>.data/</code>, <code>docker-compose.yml</code> and the docs of this project from the template; <code>.env</code> values, <code>.config/</code>, <code>addons/</code> and <code>db_files/</code> are kept. Review with <code>git diff</code> afterwards.</p>";
    const ok = await modal.open({title: "<b>" + esc(p.name) + "</b> · environment update", body, color: colors()[p.name],
                                 actions: [{label: "later", value: false}, {label: "update env", cls: "pri", value: true}]});
    if (!ok) return;
    modal.open({title: "<b>" + esc(p.name) + "</b> · updating…", body: "<p>fetching the template and applying the changes</p>", actions: [], color: colors()[p.name]});
    const r = await api("/api/env_update?project=" + encodeURIComponent(p.name), {method: "POST"});
    const log = (r && r.log) || "hub unreachable", good = !!(r && r.ok);
    const compose = /docker compose up -d/.test(log), rebuild = /\brebuild\b.*Dockerfile/.test(log);
    const actions = [{label: good ? "done" : "close", value: false}];
    if (good && compose && !rebuild) actions.push({label: "restart env", cls: "pri", value: true});
    const restart = await modal.open({title: "<b>" + esc(p.name) + "</b> · " + (good ? "environment updated" : "update failed"),
                                      body: (good ? "" : '<p class="warn">env-update exited with an error:</p>') + "<pre>" + esc(log) + "</pre>" +
                                        (good && rebuild ? '<p class="warn">Dockerfiles changed: run <code>rebuild</code> in the utils terminal.</p>' : ""),
                                      actions, color: good ? colors()[p.name] : "var(--red)"});
    if (restart) await api("/api/restart?project=" + encodeURIComponent(p.name), {method: "POST"});
    refresh();
  }
  // ---- first start: the odoo guard waits for /var/shared/.setup_done → confirm the critical keys here ----
  const needsSetup = p => !!(p.status && p.status.setup && p.dir);
  async function askSetup(p) {
    if (!needsSetup(p)) return;
    const info = await api("/api/setup?project=" + encodeURIComponent(p.name));
    if (!info || info.error) { await modal.open({title: "<b>" + esc(p.name) + "</b> · first start", body: '<p class="warn">' + esc((info && info.error) || "hub unreachable") + "</p>", actions: [{label: "close", value: null}], color: "var(--red)"}); return; }
    const e = info.env || {}, sg = info.suggest || {};
    const field = (k, label, note, value, hint) => '<div class="k">' + label + (note ? "<small>" + note + "</small>" : "") + '</div><input data-key="' + k + '" value="' + esc(value) + '" spellcheck="false">' + (hint ? '<div class="hint">' + hint + "</div>" : "");
    const sug = k => sg[k] ? "<b>" + esc(sg[k].from) + "</b> uses " + esc(sg[k].value) + (sg[k].verified ? " (valid for Odoo " + esc(e.ODOO_VERSION) + ")" : " (not verified, project stopped)") + " — pre-filled; empty = Community" : "no sibling project of the same version found — empty = Community";
    const body = "<p>Odoo has not been started yet: these settings decide how the first database is built. Nothing starts before you confirm.</p>" +
      '<div class="form">' +
      '<div class="k">ODOO_VERSION<small>stack already built</small></div><div class="ro">Odoo ' + esc(e.ODOO_VERSION || "?") + " — change it later in this panel + <code>rebuild</code></div>" +
      field("ENTERPRISE_PATH", "ENTERPRISE_PATH", "relative to docker-compose.yml", e.ENTERPRISE_PATH || (sg.ENTERPRISE_PATH || {}).value || "", sug("ENTERPRISE_PATH")) +
      field("ODOO_PATH", "ODOO_PATH", "odoo source, optional", e.ODOO_PATH || (sg.ODOO_PATH || {}).value || "", sg.ODOO_PATH ? "<b>" + esc(sg.ODOO_PATH.from) + "</b> uses " + esc(sg.ODOO_PATH.value) + " — pre-filled" : "") +
      field("ADDONS_PATH", "ADDONS_PATH", "root of your addons", e.ADDONS_PATH || "./addons", "") +
      field("SELECTED_DB", "SELECTED_DB", "database created at start", e.SELECTED_DB || "", "empty = multi-database mode") +
      '<div class="k">SSH_PATH<small>keys for pull over ssh</small></div><div class="ro">' + (e.SSH_PATH ? esc(e.SSH_PATH) + " — mounted read-only in utils" : "no key found in the home of the folder's owner — set it later in <b>config</b>") + "</div>" +
      "</div><p>Everything else keeps the template defaults and can be changed in <b>config</b> at any time.</p>";
    const values = await modal.open({title: "<b>" + esc(p.name) + "</b> · first start", body, color: colors()[p.name],
                                     actions: [{label: "later", value: null}, {label: "confirm & start", cls: "pri", value: box => Object.fromEntries([...box.querySelectorAll("[data-key]")].map(i => [i.dataset.key, i.value.trim()]))}]});
    if (!values) return;
    const r = await api("/api/setup?project=" + encodeURIComponent(p.name), {method: "POST", body: JSON.stringify(values)});
    if (!r || r.error) await modal.open({title: "<b>" + esc(p.name) + "</b> · setup failed", body: '<p class="warn">' + esc((r && r.error) || "hub unreachable") + "</p>", actions: [{label: "close", value: null}], color: "var(--red)"});
    refresh();
  }
  function proposeRestart() {
    if (modal.busy()) return;
    for (const p of projects) {
      if (p.start && p.start.state !== "error") continue;
      if (needsSetup(p)) { if (proposed["setup:" + p.name]) continue; proposed["setup:" + p.name] = true; askSetup(p); return; }
      const pend = envPending(p), sig = JSON.stringify(pend), u = envUpdate(p), usig = u ? "update:" + u.available : "";
      if (pend.length && proposed[p.name] !== sig) {
        proposed[p.name] = sig;
        if (!pend.every(([k, v]) => snoozed[p.name] && snoozed[p.name][k] === v.to)) { askRestart(p); return; }
      }
      if (usig && proposed["upd:" + p.name] !== usig) { proposed["upd:" + p.name] = usig; askUpdate(p); return; }
    }
  }

  let lastSig = "";
  function render() {
    // only touch the DOM when something changed (keeps open menus alive across polls)
    const sig = JSON.stringify([projects.map(p => Object.assign({}, p, {status: p.status && Object.assign({}, p.status, {time: 0}), start: p.start && Object.assign({}, p.start, {elapsed: 0}), progress: p.progress && Object.assign({}, p.progress, {elapsed: 0})})), current]);
    if (sig === lastSig) return;
    lastSig = sig;
    const opened = (document.querySelector(".tab.open .name") || {}).textContent;
    empty.style.display = online().length ? "none" : "flex";
    tabs.innerHTML = "";
    const color = colors();
    projects.forEach((p, n) => {
      const active = current && current.project === p.name;
      const view = active ? current.view : p.running ? viewOf(p) : "offline";
      const s = p.status, busy = p.start && ["starting", "restarting", "stopping"].includes(p.start.state);
      const tab = document.createElement("div");
      tab.className = "tab" + (active ? " active" : "") + (p.running ? "" : " off") + (busy || p.progress ? " busy" : "");
      tab.dataset.name = p.name;   // the face is the drag handle (set below): a slight move while clicking a menu entry must not start a drag
      // elapsed time of a compose action, ticking on the page (data-t0 elements are updated every second)
      const t0 = busy ? Date.now() - (p.start.elapsed || 0) * 1000 : 0;
      const timer = (label, cls) => busy ? '<span class="' + cls + '" data-t0="' + t0 + '" data-label="' + label + '">' + label + " " + clock(t0) + "</span>" : "";
      tab.style.setProperty("--c", color[p.name]);
      let menu = '<div class="head">// <b>' + esc(p.name) + "</b> · " + pad2(n + 1) + (p.dir ? ' · <span class="dir">' + esc(p.dir) + "</span>" : "") + "</div>";
      const cfgLink = p.dir ? '<button class="cfg" data-p="' + esc(p.name) + '">config</button>' : "";
      if (p.running) {
        menu += viewsOf(p).map(v => '<a href="#' + p.name + '/' + v + '" class="' + (active && current.view === v ? "current" : "") + '">' + LABEL[v] + "</a>").join("") + cfgLink;
        if (p.mcp) menu += '<a class="mcp" href="http://' + p.mcp + port + '/health" target="_blank">http://' + p.mcp + port + "/health</a>";
        if (s) menu += '<div class="st">' + esc(tooltip(s)) + "</div>";
        menu += '<button class="odoo-restart" data-p="' + esc(p.name) + '">restart odoo</button>';
        menu += '<button class="hist" data-p="' + esc(p.name) + '">history' + (p.last ? '<span class="lst' + (p.last.ok ? "" : " err") + '">' + esc(p.last.action) + "</span>" : "") + "</button>";
        if (!busy) menu += '<button class="stop" data-p="' + esc(p.name) + '">compose down</button>';
      } else if (busy) {
        menu += '<div class="st"><b>' + timer(p.start.state + "…", "") + "</b>  docker compose " + (p.start.state === "stopping" ? "down" : "up -d") +
          (p.start.state === "stopping" ? "" : "\nbuilding a missing image takes several minutes") + "</div>" + cfgLink;
      } else {
        menu += '<button class="start" data-p="' + esc(p.name) + '">start</button>';
        if (p.start && p.start.state === "error") menu += '<div class="st err">' + esc(p.start.log) + "</div>";
        menu += '<button class="forget" data-p="' + esc(p.name) + '">forget</button>' + cfgLink;
        menu += '<button class="hist" data-p="' + esc(p.name) + '">history' + (p.last ? '<span class="lst' + (p.last.ok ? "" : " err") + '">' + esc(p.last.action) + "</span>" : "") + "</button>";
      }
      const dots = p.running ? '<span class="dots" title="' + esc(tooltip(s)) + '">' + ["odoo", "db", "ent"].map(k => '<i class="dot ' + dotClass(s, k) + '"></i>').join("") + "</span>" : "";
      const flag = s && s.rebuild ? '<span class="flag">rebuild</span>' : "";
      const sm = p.running && !busy && startMark(s);
      const startFlag = sm ? '<span class="flag start ' + sm.cls + '" title="' + esc(sm.text) + '">' + sm.mark + (s.start_errors ? " " + s.start_errors : "") + "</span>" : "";
      const env = busy ? "" : envPending(p).length ? '<span class="flag env l' + envLevel(p) + '" title="apply the .env changes">' + (LEVEL[envLevel(p)] || LEVEL[1]).label + "</span>" : "";
      const upd = !busy && envUpdate(p) ? '<span class="flag upd" title="environment v' + esc(envUpdate(p).available) + ' available">v' + esc(envUpdate(p).available) + "</span>" : "";
      const setup = !busy && needsSetup(p) ? '<span class="flag setup" title="first start: confirm the configuration">setup</span>' : "";
      const href = p.running ? '#' + p.name + '/' + view : "#";
      const step = busy ? p.start.detail : p.progress && p.progress.label;   // where a long run is (image build…)
      const stepT0 = p.progress ? Date.now() - (p.progress.elapsed || 0) * 1000 : t0;
      const viewTag = busy || p.progress ? '<span class="view run" data-t0="' + stepT0 + '" data-label="' + esc(step || p.start.state) + '">' + esc(step || p.start.state) + " " + clock(stepT0) + "</span>"
                                         : '<span class="view">' + (LABEL[view] || view) + "</span>";
      tab.innerHTML = '<div class="face"><a href="' + href + '"><span class="idx">' + pad2(n + 1) + '</span><span class="name">' + esc(p.name) + "</span>" + viewTag + dots + startFlag + flag + env + upd + setup + "</a>" +
        '<span class="caret">▼</span></div><div class="menu">' + menu + "</div>";
      tab.querySelector(".face").draggable = true;
      tab.querySelector(".caret").addEventListener("click", e => { e.stopPropagation(); const o = tab.classList.contains("open"); closeMenus(); tab.classList.toggle("open", !o); });
      if (!p.running) tab.querySelector(".face>a").addEventListener("click", e => { e.preventDefault(); const o = tab.classList.contains("open"); closeMenus(); tab.classList.toggle("open", !o); e.stopPropagation(); });
      const envFlag = tab.querySelector(".flag.env");
      if (envFlag) envFlag.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); closeMenus(); askRestart(p); });
      const setupFlag = tab.querySelector(".flag.setup");
      if (setupFlag) setupFlag.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); closeMenus(); askSetup(p); });
      const updFlag = tab.querySelector(".flag.upd");
      if (updFlag) updFlag.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); closeMenus(); askUpdate(p); });
      if (p.name === opened) tab.classList.add("open");
      tabs.appendChild(tab);
    });
    tabs.querySelectorAll("a").forEach(a => { a.draggable = false; });   // the tab moves, not the link
    if (config.classList.contains("active")) placeConfig();
    tick();
    // title + favicon of the current project
    if (current) {
      const p = byName(current.project), sm = p && p.running && startMark(p.status);
      document.title = (sm ? sm.mark + " " : "") + current.project.toUpperCase() + " · " + LABEL[current.view];
      favicon(color[current.project], current.project[0].toUpperCase());
    } else { document.title = "Odoo"; favicon(cssVar("red"), "O"); }
  }

  // ---- config: the .env of a project rendered as a form, in a dropdown under its tab ----
  let cfg = {project: null, orig: {}, level: {}};
  function placeConfig() {   // under the project's tab, kept inside the window
    const tab = [...tabs.children].find(t => t.querySelector(".name").textContent === cfg.project);
    const x = tab ? tab.getBoundingClientRect().left : 8;
    config.style.setProperty("--x", Math.max(8, Math.min(x, window.innerWidth - config.offsetWidth - 8)) + "px");
  }
  function openConfig(name) {
    const p = byName(name); if (!p) return;
    config.classList.add("active"); config.style.setProperty("--c", colors()[name]);
    if (cfg.project !== name) loadConfig(name);
    placeConfig();
  }
  function closeConfig(force) {
    if (!config.classList.contains("active")) return;
    if (!force && Object.keys(syncDirty()).length) return;   // unsaved changes: close only with ✕
    config.classList.remove("active"); cfg = {project: null, orig: {}, level: {}}; config.innerHTML = "";
  }
  window.addEventListener("resize", () => { if (config.classList.contains("active")) placeConfig(); });
  function parseEnv(text) {
    const L = text.split("\n"), items = [];
    const isSec = l => /^# ?={5,}\s*$/.test(l), isSub = l => /^# ?-{5,}\s*$/.test(l), isC = l => /^#/.test(l), isK = l => /^[A-Z_][A-Z0-9_]*=/.test(l);
    const strip = l => l.replace(/^# ?/, "");
    const keyOf = l => { const eq = l.indexOf("="); let v = l.slice(eq + 1); const q = v.length >= 2 && v[0] === v[v.length - 1] && "'\"".includes(v[0]); return {key: l.slice(0, eq), value: q ? v.slice(1, -1).replace(/'\\''/g, "'") : v}; };
    let i = 0;
    while (i < L.length) {
      const l = L[i];
      if (!l.trim()) { i++; continue; }
      if (isSec(l) || isSub(l)) {
        const close = isSec(l) ? isSec : isSub, body = []; let j = i + 1;
        while (j < L.length && isC(L[j]) && !close(L[j])) body.push(strip(L[j++]));
        if (j < L.length && close(L[j])) { items.push({t: isSec(l) ? "sec" : "sub", title: body[0] || "", desc: body.slice(1).join("\n").trim()}); i = j + 1; }
        else i++;
        continue;
      }
      const help = [], m = {};   // m = markers of the '#@' line: optional, auto, type=bool, apply=r|compose|rebuild, wipe=db
      while (i < L.length && isC(L[i]) && !isSec(L[i]) && !isSub(L[i])) {
        if (/^#@/.test(L[i])) L[i].slice(2).trim().split(/\s+/).forEach(t => { const [k, v] = t.split("="); if (k) m[k] = v || true; });
        else help.push(strip(L[i]));
        i++;
      }
      const keys = [];
      while (i < L.length && isK(L[i])) keys.push(keyOf(L[i++]));
      if (keys.length) items.push({t: "grp", help: help.join("\n"), keys, m});
      else if (help.length) items.push({t: "note", text: help.join("\n")});
      else i++;
    }
    return items;
  }
  const cfgHead = (name, dir) => '<div class="cfg-head">// <b>' + esc(name) + '</b> · .env <span class="dir">' + esc(dir || "") + '</span><span class="msg"></span><button class="save" disabled>save</button><button class="x" title="close">✕</button></div>';
  function renderConfig(name, text, dir) {
    cfg = {project: name, orig: {}, level: {}};
    let html = "";
    for (const it of parseEnv(text)) {
      if (it.t === "sec") html += "<h1>" + esc(it.title) + "</h1>" + (it.desc ? '<pre class="note">' + esc(it.desc) + "</pre>" : "");
      else if (it.t === "sub") html += "<h2>" + esc(it.title) + (it.desc ? "<pre>" + esc(it.desc) + "</pre>" : "") + "</h2>";
      else if (it.t === "note") html += '<pre class="note">' + esc(it.text) + "</pre>";
      else {
        const ro = !!it.m.auto, opt = !!it.m.optional, help = it.help;
        const level = levelOf(it.m.apply, it.m.wipe === "db");
        const applyBadge = level ? '<i class="l' + level + '">' + LEVEL[level].label + "</i>" : it.m.apply === "r" ? "<i>odoo restart</i>" : "";
        html += '<div class="grp">' + (help ? '<pre class="help">' + esc(help) + "</pre>" : "");
        for (const k of it.keys) {
          cfg.orig[k.key] = k.value; cfg.level[k.key] = level;
          const isBool = it.m.type === "bool" || /^(true|false)$/.test(k.value);
          html += '<div class="row"><span class="k">' + esc(k.key) + (ro ? '<i class="ro">auto</i>' : opt ? "<i>optional</i>" : "") + applyBadge + "</span>";
          if (isBool) html += '<div class="sw"><label><input type="checkbox" data-key="' + esc(k.key) + '"' + (k.value === "true" ? " checked" : "") + (ro ? " disabled" : "") + "><i></i></label><span>" + esc(k.value) + "</span></div>";
          else html += '<input type="text" data-key="' + esc(k.key) + '" value="' + esc(k.value) + '"' + (ro ? " readonly" : "") + ' spellcheck="false">';
          html += "</div>";
        }
        html += "</div>";
      }
    }
    config.innerHTML = cfgHead(name, dir) + '<div class="cfg-body">' + html + "</div>";
  }
  function cfgValue(el) { return el.type === "checkbox" ? (el.checked ? "true" : "false") : el.value; }
  function syncDirty() {   // marks the changed rows, refreshes the toggle labels; returns {KEY: new value}
    const out = {};
    for (const el of config.querySelectorAll("[data-key]")) {
      const v = cfgValue(el), dirty = v !== cfg.orig[el.dataset.key];
      el.closest(".row").classList.toggle("dirty", dirty);
      if (el.type === "checkbox") el.closest(".sw").querySelector("span").textContent = v;
      if (dirty) out[el.dataset.key] = v;
    }
    return out;
  }
  async function loadConfig(name) {
    cfg = {project: name, orig: {}, level: {}};
    config.innerHTML = cfgHead(name, (byName(name) || {}).dir) + '<div class="cfg-body"><div class="st">loading…</div></div>';
    const r = await api("/api/env?project=" + encodeURIComponent(name));
    if (cfg.project !== name) return;
    if (!r || r.error) { config.querySelector(".st").textContent = (r && r.error) || "hub unreachable"; config.querySelector(".st").classList.add("err"); return; }
    renderConfig(name, r.text, r.dir);
  }
  // level of one edited key; a value put back to what the containers run with (status.env_changed[key].from) needs nothing
  const keyLevel = (k, v) => { const ch = ((byName(cfg.project) || {}).status || {}).env_changed || {}; return ch[k] && ch[k].from === v ? 0 : cfg.level[k] || 0; };
  const cfgLevel = values => Math.max(0, ...Object.entries(values).map(([k, v]) => keyLevel(k, v)));
  config.addEventListener("input", () => {   // the save button takes the colour of what the change will need
    const values = syncDirty(), n = Object.keys(values).length, level = cfgLevel(values), b = config.querySelector("button.save");
    if (!b) return;
    b.disabled = !n; b.className = "save l" + level;
    b.textContent = !n ? "save" : "save " + n + (level ? " · " + LEVEL[level].label : "");
  });
  config.addEventListener("click", e => e.stopPropagation());   // clicks inside never close the panel (document click does)
  config.addEventListener("click", async e => {
    const b = e.target.closest("button"); if (!b || b.disabled) return;
    if (b.classList.contains("x")) { closeConfig(true); return; }
    const values = syncDirty(), level = cfgLevel(values), msg = config.querySelector(".msg"), p = byName(cfg.project);
    const rows = Object.entries(values).map(([key, to]) => ({key, from: cfg.orig[key], to, level: keyLevel(key, to)}));
    b.disabled = true; msg.className = "msg"; msg.textContent = "saving…";
    const r = await api("/api/env?project=" + encodeURIComponent(cfg.project), {method: "POST", body: JSON.stringify(values)});
    if (!r || r.error) { msg.className = "msg err"; msg.textContent = (r && r.error) || "hub unreachable"; b.disabled = false; return; }
    const body = config.querySelector(".cfg-body"), scroll = body.scrollTop;
    renderConfig(cfg.project, r.text, config.querySelector(".dir").textContent);
    config.querySelector(".cfg-body").scrollTop = scroll;
    config.querySelector(".msg").textContent = "saved " + Object.keys(values).join(", ") + (level ? "" : rows.some(x => cfg.level[x.key]) ? " — back to the running values" : " — applied by the next Odoo start (r)");
    if (level && p && p.running) {
      snoozed[p.name] = Object.assign(snoozed[p.name] || {}, values);
      if (await applyChanges(p, level, rows.filter(x => x.level))) closeConfig(true);
    }
    else if (level) config.querySelector(".msg").textContent += " — " + LEVEL[level].label + " at the next start";
  });

  const TOKEN = (document.querySelector('meta[name="hub-token"]') || {}).content || "";
  async function api(path, opts) {
    const o = Object.assign({cache: "no-store"}, opts || {});
    if (o.method === "POST") o.headers = Object.assign({"X-Hub-Token": TOKEN, "Content-Type": "application/json"}, o.headers || {});
    try {
      const r = await fetch(path, o);
      if (r.status === 403 && o.method === "POST") { location.reload(); return null; }   // hub restarted: new token, the page must be reloaded
      return await r.json();
    } catch (e) { return null; }
  }
  // state pushed by the server (/api/events); refresh() = pull once (after an action, or when the stream is down)
  function applyState(list) {
    projects = sortProjects(list || []);
    if (current && !document.getElementById("f-" + current.project + "-" + current.view)) { const p = byName(current.project); if (p && p.running) select(current); }
    // drop the frames of stopped projects
    [...frames.children].forEach(f => { const p = byName(f.dataset.project); if (!p || !p.running) f.remove(); });
    const sel = fromHash();
    if (!sel || !current || sel.project !== current.project || sel.view !== current.view) select(sel); else render();
    waiting();
    proposeRestart();
  }
  async function refresh() { applyState(await api("/api/projects")); }
  const clock = t0 => { const n = Math.max(0, Math.round((Date.now() - t0) / 1000)); return Math.floor(n / 60) + ":" + String(n % 60).padStart(2, "0"); };
  let ticker = null;   // updates the elapsed timers of the busy tabs; runs only while there is one
  function tick() {
    const els = document.querySelectorAll("[data-t0]");
    els.forEach(el => { el.textContent = el.dataset.label + " " + clock(+el.dataset.t0); });
    if (els.length && !ticker) ticker = setInterval(tick, 1000);
    else if (!els.length && ticker) { clearInterval(ticker); ticker = null; }
  }
  (function listen() {
    let es = null, fallback = null;
    function connect() {
      es = new EventSource("/api/events");
      es.addEventListener("hello", e => { if (e.data !== TOKEN) location.reload(); });   // hub restarted: new token, new files
      es.onmessage = e => { try { applyState(JSON.parse(e.data)); } catch (err) { /* partial frame */ } if (fallback) { clearInterval(fallback); fallback = null; } };
      es.onerror = () => { if (!fallback) fallback = setInterval(refresh, 5000); };   // EventSource reconnects by itself; poll meanwhile
    }
    connect();
    document.addEventListener("visibilitychange", () => { if (!document.hidden && es.readyState === EventSource.CLOSED) { es.close(); connect(); } });
  })();

  // ---- Odoo not answering yet (starting / stopped): a panel instead of a 502 in the frame; the frame reloads when it is up ----
  // A restart shorter than a status tick is never seen as "down": the start timestamp tells it, and the frame
  // (left on the proxy error page) is reloaded as well.
  const wasDown = {}, seenStart = {};
  function waiting() {
    const p = current && byName(current.project), s = p && p.status;
    if (p && s && s.start_at && s.odoo && s.start !== "starting") {
      if (seenStart[p.name] && seenStart[p.name] !== s.start_at) wasDown[p.name] = true;
      seenStart[p.name] = s.start_at;
    }
    const down = !!(p && p.running && current.view === "odoo" && s && (!s.odoo || s.start === "starting" || s.start === "failed"));
    wait.classList.toggle("on", down);
    if (down) {
      wait.style.setProperty("--c", colors()[p.name]);
      const what = !s.odoo ? (s.setup ? "waiting for the first-start confirmation" : s.start === "dead" ? "odoo exited at start" : "odoo process stopped")
                           : s.start === "failed" ? "odoo blocked: start failed"
                           : "odoo starting" + (s.database ? " · " + esc(s.database) : "");
      wait.innerHTML = '<div class="big">// ' + what + "</div>" +
        (startMark(s) ? '<div class="' + startMark(s).cls + '">' + startMark(s).mark + " " + esc(startMark(s).text) + "</div>" : "") +
        (p.last ? '<div class="last">' + esc(p.last.action) + (p.last.detail ? " · " + esc(p.last.detail) : "") + "</div>" : "") +
        '<div class="acts">' + (p.logs ? '<a href="#' + p.name + '/logs">logs</a>' : "") + (p.utils ? '<a href="#' + p.name + '/utils">utils</a>' : "") +
        ((!s.odoo || s.start === "failed") && !s.setup ? '<button class="odoo-restart" data-p="' + esc(p.name) + '">restart odoo</button>' : "") + "</div>";
      wasDown[p.name] = true;
    } else if (p && wasDown[p.name] && s && s.odoo && s.start !== "starting") {   // back: the frame showed the proxy error page
      wasDown[p.name] = false;
      const f = document.getElementById("f-" + p.name + "-odoo"); if (f) f.src = f.src;
    }
  }
  wait.addEventListener("click", async e => {
    const b = e.target.closest("button"); if (!b) return;
    b.disabled = true; await api("/api/odoo_restart?project=" + encodeURIComponent(b.dataset.p), {method: "POST"});
  });

  // ---- journal: the last actions run from the hub on a project ----
  const when = t => { const d = new Date(t * 1000), today = new Date().toDateString() === d.toDateString(); return (today ? "" : pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1) + " ") + pad2(d.getHours()) + ":" + pad2(d.getMinutes()); };
  async function showJournal(name) {
    const p = byName(name), list = (await api("/api/journal?project=" + encodeURIComponent(name))) || [];
    const body = list.length ? "<table>" + list.slice().reverse().map(e => '<tr><td class="ap">' + when(e.t) + '</td><td class="k' + (e.ok ? "" : " bad") + '">' + (e.ok ? "" : "✗ ") + esc(e.action) + "</td><td>" + esc(e.detail) + "</td></tr>").join("") + "</table>"
                             : "<p>nothing yet: starts, stops, .env saves and updates run from the hub are listed here.</p>";
    modal.open({title: "<b>" + esc(name) + "</b> · history", body, actions: [{label: "close", value: null}], color: p ? colors()[name] : "var(--yellow)"});
  }
  // ---- scan: register the template copies found under a host folder (projects never started on this machine) ----
  async function askScan() {
    const dirs = projects.map(p => p.dir).filter(Boolean), guess = dirs.length ? dirs[0].replace(/\/[^/]+$/, "") : "";
    const body = "<p>Every folder (3 levels deep) holding a <code>docker-compose.yml</code>, a <code>.env</code> and <code>.data/</code> of this environment is added to the hub, stopped, with its <b>Start</b> action.</p>" +
      '<div class="form"><div class="k">host folder</div><input data-key="path" value="' + esc(guess) + '" spellcheck="false" placeholder="/Users/me/odoo"></div>';
    const path = await modal.open({title: "scan a folder", body, actions: [{label: "cancel", value: null}, {label: "scan", cls: "pri", value: box => box.querySelector("[data-key=path]").value.trim()}]});
    if (!path) return;
    modal.open({title: "scanning…", body: "<p>" + esc(path) + "</p>", actions: []});
    const r = await api("/api/scan", {method: "POST", body: JSON.stringify({path})});
    const found = (r && r.found) || {}, added = (r && r.added) || [];
    const rows = Object.entries(found).map(([n, d]) => '<tr><td class="k">' + esc(n) + "</td><td>" + esc(d) + '</td><td class="ap">' + (added.includes(n) ? "added" : "known") + "</td></tr>").join("");
    await modal.open({title: "scan · " + (r && !r.error ? Object.keys(found).length + " project" + (Object.keys(found).length > 1 ? "s" : "") : "failed"),
                      body: r && !r.error ? (rows ? "<table>" + rows + "</table>" : "<p>no environment found under <code>" + esc(path) + "</code></p>") : '<p class="warn">' + esc((r && r.error) || "hub unreachable") + "</p>",
                      actions: [{label: "close", value: null}], color: r && !r.error ? "var(--yellow)" : "var(--red)"});
    refresh();
  }
  document.querySelectorAll(".scan").forEach(b => b.addEventListener("click", e => { e.stopPropagation(); askScan(); }));

  function closeMenus() { document.querySelectorAll(".tab.open").forEach(t => t.classList.remove("open")); }

  // ---- drag and drop: reorder the tabs (alt+1..9 follow the new order) ----
  let dragging = null;
  tabs.addEventListener("dragstart", e => { if (e.target.closest(".menu")) { e.preventDefault(); return; } const t = e.target.closest(".tab"); if (!t) return; dragging = t.dataset.name; closeMenus(); t.classList.add("drag"); e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", dragging); });
  tabs.addEventListener("dragend", () => { dragging = null; tabs.querySelectorAll(".drag, .over").forEach(t => t.classList.remove("drag", "over")); });
  tabs.addEventListener("dragover", e => {
    if (!dragging) return;
    e.preventDefault(); e.dataTransfer.dropEffect = "move";
    tabs.querySelectorAll(".over").forEach(t => t.classList.remove("over"));
    const t = e.target.closest(".tab"); if (t && t.dataset.name !== dragging) t.classList.add("over");
  });
  tabs.addEventListener("drop", e => {
    if (!dragging) return;
    e.preventDefault();
    const t = e.target.closest(".tab"), name = dragging; dragging = null;
    if (!t) { moveTab(name, null); return; }
    if (t.dataset.name === name) return;
    const r = t.getBoundingClientRect(), after = e.clientX > r.left + r.width / 2;
    const names = projects.map(p => p.name), i = names.indexOf(t.dataset.name);
    moveTab(name, after ? names[i + 1] || null : t.dataset.name);
  });
  document.addEventListener("click", () => { closeMenus(); closeConfig(); });
  // A click inside an iframe never reaches this document: the only signal is the window losing focus.
  // Odoo (home menu) grabs the focus back a few ms after its frame lost it: such a blur is not a click.
  let focusedAt = 0, fromFrame = false;
  window.addEventListener("focus", () => { focusedAt = performance.now(); });
  window.addEventListener("blur", () => { if (performance.now() - focusedAt > 300) { closeMenus(); closeConfig(); } });
  // Same grab breaks typing in the hub's inputs: hide the frame while Odoo tries (not rendered = not focusable).
  document.addEventListener("mousedown", () => { fromFrame = document.activeElement?.tagName === "IFRAME"; }, true);
  document.addEventListener("focusin", e => {
    if (!fromFrame || !e.target.matches("input, textarea, select")) return;
    fromFrame = false;
    const shielded = [...document.querySelectorAll("iframe.active")];
    shielded.forEach(f => { f.style.visibility = "hidden"; });
    setTimeout(() => shielded.forEach(f => { f.style.visibility = ""; }), 120);
  });
  tabs.addEventListener("click", async e => {
    const b = e.target.closest("button");
    if (b) {
      e.stopPropagation();
      if (b.classList.contains("cfg")) { closeMenus(); openConfig(b.dataset.p); return; }
      if (b.classList.contains("hist")) { closeMenus(); showJournal(b.dataset.p); return; }
      if (b.classList.contains("odoo-restart")) { closeMenus(); await api("/api/odoo_restart?project=" + encodeURIComponent(b.dataset.p), {method: "POST"}); refresh(); return; }
      if (b.classList.contains("start")) { closeMenus(); await api("/api/start?project=" + encodeURIComponent(b.dataset.p), {method: "POST"}); refresh(); return; }
      if (b.classList.contains("stop")) {
        closeMenus();
        if (await modal.confirm("stop <b>" + esc(b.dataset.p) + "</b>", "<code>docker compose down</code>: containers and terminals removed, databases and files kept. The project stays in the hub with a <b>Start</b> action.", "compose down", "var(--red)"))
          await api("/api/stop?project=" + encodeURIComponent(b.dataset.p), {method: "POST"});
      } else if (b.classList.contains("forget")) {
        closeMenus();
        if (await modal.confirm("forget <b>" + esc(b.dataset.p) + "</b>", "The project disappears from the hub until its next <code>docker compose up</code>. Its folder is not touched.", "forget", "var(--red)"))
          await api("/api/forget?project=" + encodeURIComponent(b.dataset.p), {method: "POST"});
      }
      closeMenus(); refresh(); return;
    }
    const a = e.target.closest(".menu a");
    if (a && a.getAttribute("href").startsWith("#")) {   // a view of the project
      e.preventDefault(); e.stopPropagation(); closeMenus();
      const [project, view] = a.getAttribute("href").slice(1).split("/");
      select({project, view});
    } else if (a) closeMenus();
  });
  window.addEventListener("hashchange", () => { const s = fromHash(); if (s) select(s); });
  // keyboard: only when the focus is on this page (not inside a terminal / Odoo frame)
  document.addEventListener("keydown", e => {
    if (e.key === "Escape") { if (modal.busy()) modal.close(null); else closeConfig(); return; }
    if (!e.altKey || e.ctrlKey || e.metaKey) return;
    const on = online(); if (!on.length) return;
    const i = current ? on.findIndex(p => p.name === current.project) : 0;
    let p = null, v = null;
    if (/^[1-9]$/.test(e.key)) p = on[+e.key - 1];
    else if (e.key === "ArrowLeft") p = on[(i - 1 + on.length) % on.length];
    else if (e.key === "ArrowRight") p = on[(i + 1) % on.length];
    else if (e.key.toLowerCase() === "v" && i >= 0) { const vs = viewsOf(on[i]); v = vs[(vs.indexOf(current.view) + 1) % vs.length]; p = on[i]; }
    else return;
    if (!p) return;
    e.preventDefault();
    select({project: p.name, view: v || (current && current.project === p.name ? current.view : viewOf(p))});
  });
  refresh();

  // ---- brand glitch: random bursts of stuttering offsets + colour split; now and then the other logo ----
  (function glitch() {
    const brand = document.getElementById("brand");
    const rnd = (a, b) => a + Math.random() * (b - a), pick = a => a[Math.random() * a.length | 0];
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const slice = () => { const t = rnd(0, 70) | 0; return "inset(" + t + "% 0 " + (rnd(0, 90 - t) | 0) + "% 0)"; };
    function frame(strength) {   // one stuttering step of the whole logo
      brand.style.transform = "translate(" + (rnd(-3, 3) * strength | 0) + "px," + (rnd(-2, 2) * strength | 0) + "px) skewX(" + (rnd(-10, 10) * strength).toFixed(1) + "deg)";
      brand.classList.toggle("split", Math.random() < .7);
      brand.style.setProperty("--d1", (rnd(-5, 5) | 0) + "px"); brand.style.setProperty("--d2", (rnd(-5, 5) | 0) + "px");
      brand.style.setProperty("--c1", slice()); brand.style.setProperty("--c2", slice());
    }
    function reset() { brand.style.transform = ""; brand.classList.remove("split", "ara"); brand.style.removeProperty("--slice"); }
    async function shake() {
      const n = 2 + (rnd(0, 6) | 0);
      for (let i = 0; i < n; i++) { frame(pick([.4, 1, 1, 1.6])); await sleep(rnd(25, 110)); if (Math.random() < .25) { reset(); await sleep(rnd(40, 160)); } }
      reset();
    }
    async function arasaka() {
      const n = 3 + (rnd(0, 5) | 0);
      for (let i = 0; i < n; i++) {
        brand.classList.toggle("ara", Math.random() < .8);
        brand.style.setProperty("--slice", Math.random() < .5 ? "none" : slice());
        frame(pick([.5, 1, 1.5]));
        await sleep(rnd(35, 120));
      }
      reset();
    }
    (async () => {
      while (true) {
        await sleep(rnd(2500, 14000));
        if (document.hidden) continue;
        if (Math.random() < .12) await arasaka(); else await shake();
        if (Math.random() < .3) { await sleep(rnd(120, 600)); await shake(); }   // aftershock
      }
    })();
  })();
})();
