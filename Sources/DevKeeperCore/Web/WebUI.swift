import Foundation

/// The single page of the local web interface. Data is inserted with `textContent` only, never as HTML.
enum WebUI {
    static let html = #"""
    <!doctype html>
    <html lang="zh-Hant">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DevKeeper</title>
    <style nonce="{{NONCE}}">
    :root { color-scheme: dark; --bg:#1c1c1e; --panel:#2c2c2e; --line:#3a3a3c; --text:#f2f2f7; --dim:#98989d;
            --accent:#0a84ff; --ok:#30d158; --warn:#ff9f0a; --bad:#ff453a; }
    * { box-sizing: border-box; }
    body { margin:0; background:var(--bg); color:var(--text); font:14px/1.5 -apple-system, "Noto Sans TC", "Segoe UI", sans-serif; }
    header { display:flex; align-items:center; gap:24px; padding:12px 24px; border-bottom:1px solid var(--line); position:sticky; top:0; background:var(--bg); }
    h1 { font-size:16px; margin:0; }
    nav { display:flex; gap:4px; }
    nav button { background:none; border:0; color:var(--dim); padding:6px 12px; border-radius:6px; font:inherit; cursor:pointer; }
    nav button[aria-selected="true"] { background:var(--panel); color:var(--text); }
    nav button:focus-visible, .btn:focus-visible { outline:2px solid var(--accent); }
    main { max-width:960px; margin:0 auto; padding:24px; }
    .row { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:16px; }
    .btn { background:var(--panel); border:1px solid var(--line); color:var(--text); padding:6px 14px; border-radius:6px; font:inherit; cursor:pointer; }
    .cards { display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:12px; margin-bottom:24px; }
    .card, .item { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:14px 16px; }
    .card .n { font-size:26px; font-weight:600; }
    .dim { color:var(--dim); }
    .item { margin-bottom:10px; }
    .item .t { font-weight:600; }
    .tag { display:inline-block; padding:0 8px; border-radius:10px; font-size:12px; margin-right:8px; border:1px solid currentColor; }
    .ok { color:var(--ok); } .warn { color:var(--warn); } .bad { color:var(--bad); }
    code { display:block; margin-top:4px; font:12px ui-monospace, Menlo, monospace; color:var(--dim); word-break:break-all; }
    h2 { font-size:15px; margin:24px 0 10px; }
    </style>
    </head>
    <body>
    <header>
      <h1>DevKeeper</h1>
      <nav role="tablist" id="tabs"></nav>
    </header>
    <main id="view" aria-live="polite"></main>
    <script nonce="{{NONCE}}">
    (function () {
      var params = new URLSearchParams(location.search);
      var token = params.get("token");
      try {
        if (token) { sessionStorage.setItem("dk", token); } else { token = sessionStorage.getItem("dk"); }
      } catch (e) {}
      if (params.has("token")) { history.replaceState(null, "", location.pathname); }

      var TABS = [["overview", "概覽"], ["python", "Python 環境"], ["audit", "安全稽核"]];
      var current = "overview";
      var view = document.getElementById("view");

      function el(tag, cls, text) {
        var node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text !== undefined) node.textContent = text;
        return node;
      }
      var seq = 0;   // bumped on every tab switch so a late response never overwrites another tab
      function api(path) {
        var mine = seq;
        return fetch(path, { headers: { Authorization: "Bearer " + token }, cache: "no-store" }).then(function (r) {
          if (!r.ok) throw new Error(r.status === 403 ? "驗證失敗，請用終端機印出的網址重新開啟" : "讀取失敗（" + r.status + "）");
          return r.json();
        }).then(function (d) {
          if (mine !== seq) throw new Error("");
          return d;
        });
      }
      function card(label, value, note) {
        var c = el("div", "card");
        c.appendChild(el("div", "dim", label));
        c.appendChild(el("div", "n", String(value)));
        if (note) c.appendChild(el("div", "dim", note));
        return c;
      }
      function section(title, list, fmt) {
        view.appendChild(el("h2", null, title));
        if (!list.length) { view.appendChild(el("div", "dim", "沒有待升級項目")); return; }
        list.forEach(function (x) { view.appendChild(el("div", "item", fmt(x))); });
      }
      function header(title, reload) {
        var row = el("div", "row");
        row.appendChild(el("div", "dim", title));
        var b = el("button", "btn", "重新整理");
        b.addEventListener("click", reload);
        row.appendChild(b);
        view.appendChild(row);
      }
      function status(text) { view.replaceChildren(el("div", "dim", text)); }
      function fail(e) { if (e.message) view.replaceChildren(el("div", "bad", e.message)); }

      function overview() {
        status("掃描中…");
        api("/api/scan").then(function (d) {
          view.replaceChildren();
          header(d.os, overview);
          var cards = el("div", "cards");
          cards.appendChild(card("Python 版本", d.interpreters.length));
          cards.appendChild(card("npm 全域套件", d.npmGlobalCount, Object.keys(d.npmOutdated).length + " 個可升級"));
          cards.appendChild(card("pip 套件", d.pipCount, Object.keys(d.pipOutdated).length + " 個可升級" + (d.pipPythonVersion ? "（Python " + d.pipPythonVersion + "）" : "")));
          if (d.systemPackageManager) cards.appendChild(card("系統套件（" + d.systemPackageManager + "）", d.systemPackageCount || d.systemUpgradable.length, d.systemUpgradable.length + " 個可升級"));
          view.appendChild(cards);
          var pairs = function (o) { return Object.keys(o).sort().map(function (k) { return k + " → " + o[k]; }); };
          section("npm 可升級", pairs(d.npmOutdated), function (x) { return x; });
          section("pip 可升級", pairs(d.pipOutdated), function (x) { return x; });
          if (d.systemPackageManager) section("系統套件可升級", d.systemUpgradable, function (x) { return x; });
        }).catch(fail);
      }

      function python() {
        status("偵測中…");
        api("/api/python").then(function (list) {
          view.replaceChildren();
          header(list.length + " 個 Python", python);
          if (!list.length) view.appendChild(el("div", "dim", "沒有偵測到可用的 Python。"));
          list.forEach(function (i) {
            var item = el("div", "item");
            var t = el("div", "t", "Python " + i.version);
            var cls = i.supportStatus === "endOfLife" ? "bad" : i.supportStatus === "endingSoon" ? "warn" : "ok";
            var label = i.supportStatus === "endOfLife" ? "已終止支援 " : "支援至 ";
            var tag = el("span", "tag " + cls, label + i.supportUntil);
            var line = el("div", "dim", i.source + (i.externallyManaged ? "　受保護 (PEP 668)" : "") + (i.hasPip ? "" : "　無 pip"));
            item.appendChild(t); item.appendChild(tag); item.appendChild(line); item.appendChild(el("code", null, i.path));
            view.appendChild(item);
          });
        }).catch(fail);
      }

      var showAll = false;
      function audit() {
        status("稽核中，可能需要一點時間…");
        api("/api/audit" + (showAll ? "?all=1" : "")).then(function (d) {
          view.replaceChildren();
          header(d.items.length ? d.items.length + " 個套件存在弱點" : "沒有發現需要處理的已知安全弱點", audit);
          if (d.hiddenCount > 0 || showAll) {
            var toggle = el("button", "btn", showAll ? "隱藏內建例外" : "顯示 " + d.hiddenCount + " 項內建例外");
            toggle.addEventListener("click", function () { showAll = !showAll; audit(); });
            view.appendChild(toggle);
          }
          var names = { critical: "嚴重", high: "高", medium: "中", low: "低", unknown: "未知" };
          d.items.forEach(function (g) {
            var item = el("div", "item");
                        var t = el("div", "t");
            var sev = String(g.severity).toLowerCase();
            var cls = (sev === "critical" || sev === "high") ? "bad" : sev === "medium" ? "warn" : "dim";
            t.appendChild(el("span", "tag " + cls, names[sev] || g.severity));
            t.appendChild(document.createTextNode(g.package));
            item.appendChild(t);
            item.appendChild(el("div", "dim", g.currentVersion + (g.safeVersion ? " → 安全版本 " + g.safeVersion : "") + "　" + g.environments.join("、")));
            item.appendChild(el("div", "dim", g.cves.slice(0, 3).join("、") + (g.cves.length > 3 ? " 等 " + g.cves.length + " 個" : "")));
            g.fixCommands.forEach(function (c) { if (c) item.appendChild(el("code", null, c)); });
            view.appendChild(item);
          });
        }).catch(fail);
      }

      var pages = { overview: overview, python: python, audit: audit };
      var tabs = document.getElementById("tabs");
      function select(id) {
        current = id;
        seq++;
        Array.prototype.forEach.call(tabs.children, function (b) { b.setAttribute("aria-selected", String(b.dataset.id === id)); });
        pages[id]();
      }
      TABS.forEach(function (t) {
        var b = el("button", null, t[1]);
        b.setAttribute("role", "tab");
        b.dataset.id = t[0];
        b.addEventListener("click", function () { select(t[0]); });
        tabs.appendChild(b);
      });
      if (!token) { fail(new Error("缺少存取金鑰，請用終端機印出的網址開啟")); } else { select(current); }
    })();
    </script>
    </body>
    </html>
    """#
}
