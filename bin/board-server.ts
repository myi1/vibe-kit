#!/usr/bin/env bun
// board-server.ts — vibe-kit read-only kanban dashboard (v0.10.0).
//
// Thin HTTP wrapper. The aggregation logic lives in ONE place: the bash
// `vibe-retrofit board --json` command. This server just:
//   - serves the kanban HTML at /
//   - proxies /api/board.json to `vibe-retrofit board --json` (live, per request)
//
// Read-only by design. No write-back. The CLI/agent stays the source of truth.
// Started by `vibe-retrofit board` (which sets VIBE_KIT_BOARD_REPO + VIBE_KIT_ROOT).
//
// Zero deps beyond bun. Client polls /api/board.json every 5s for live refresh.

const port = parseInt(process.argv[2] || "4317", 10);
const repo = process.env.VIBE_KIT_BOARD_REPO || process.cwd();
const vibeKitRoot = process.env.VIBE_KIT_ROOT || "";
const cli = vibeKitRoot ? `${vibeKitRoot}/bin/vibe-retrofit` : "vibe-retrofit";

async function aggregateBoard(): Promise<string> {
  // Call the bash aggregator as a subprocess — single source of truth.
  const proc = Bun.spawn([cli, "board", "--json", "--repo", repo], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  await proc.exited;
  // Validate it's JSON; if not, wrap the error so the client renders something.
  try {
    JSON.parse(out);
    return out;
  } catch {
    return JSON.stringify({
      repo: repo.split("/").pop(),
      generated_at: new Date().toISOString(),
      error: "aggregator did not return valid JSON",
      columns: [],
    });
  }
}

const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>vibe-kit board</title>
<style>
  :root {
    --bg: #0a0a0f; --panel: #14141c; --border: #26263a; --text: #e6e6f0;
    --dim: #8a8aa0; --accent: #6ea8fe; --stale: #d97757; --green: #4ec9a8;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 14px/1.5 -apple-system, "Inter", system-ui, sans-serif; }
  header { padding: 16px 24px; border-bottom: 1px solid var(--border);
    display: flex; align-items: baseline; gap: 16px; }
  header h1 { font-size: 18px; margin: 0; font-weight: 600; }
  header .meta { color: var(--dim); font-size: 12px;
    font-family: "JetBrains Mono", ui-monospace, monospace; }
  .board { display: flex; gap: 16px; padding: 24px; overflow-x: auto;
    align-items: flex-start; }
  .col { background: var(--panel); border: 1px solid var(--border);
    border-radius: 10px; min-width: 260px; max-width: 300px; flex: 1 0 260px; }
  .col h2 { font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--dim); margin: 0; padding: 12px 14px; border-bottom: 1px solid var(--border);
    display: flex; justify-content: space-between; }
  .col h2 .count { color: var(--accent); }
  .items { padding: 10px; display: flex; flex-direction: column; gap: 8px;
    min-height: 40px; }
  .card { background: #1c1c28; border: 1px solid var(--border); border-radius: 8px;
    padding: 10px 12px; }
  .card .title { font-size: 13px; }
  .card .title a { color: var(--text); text-decoration: none; }
  .card .title a:hover { color: var(--accent); }
  .card .src { font-size: 11px; color: var(--dim); margin-top: 4px;
    font-family: "JetBrains Mono", ui-monospace, monospace; }
  .card.stale { border-color: var(--stale); }
  .card.stale .src::after { content: " · stale"; color: var(--stale); }
  .empty { color: var(--dim); font-size: 12px; padding: 8px 12px; font-style: italic; }
  .src-constitution { color: var(--green); }
  .src-spec { color: var(--green); }
  footer { color: var(--dim); font-size: 11px; padding: 8px 24px;
    font-family: "JetBrains Mono", ui-monospace, monospace; }
</style>
</head>
<body>
<header>
  <h1>vibe-kit board</h1>
  <span class="meta" id="meta">loading…</span>
</header>
<div class="board" id="board"></div>
<footer id="footer">read-only · auto-refresh 5s · source of truth is your CLI/agent</footer>
<script>
async function load() {
  try {
    const res = await fetch('/api/board.json');
    const data = await res.json();
    render(data);
  } catch (e) {
    document.getElementById('meta').textContent = 'fetch error: ' + e;
  }
}
function esc(s) { const d = document.createElement('div'); d.textContent = s ?? ''; return d.innerHTML; }
function render(data) {
  document.getElementById('meta').textContent =
    (data.repo || '?') + ' · generated ' + (data.generated_at || '');
  const board = document.getElementById('board');
  board.innerHTML = '';
  (data.columns || []).forEach(col => {
    const items = col.items || [];
    const colEl = document.createElement('div');
    colEl.className = 'col';
    const srcClass = (s) => 'src src-' + String(s||'').replace(/[^a-z]/gi,'-').toLowerCase();
    colEl.innerHTML =
      '<h2>' + esc(col.name) + ' <span class="count">' + items.length + '</span></h2>' +
      '<div class="items">' +
      (items.length === 0
        ? '<div class="empty">empty</div>'
        : items.map(it => {
            const stale = it.stale ? ' stale' : '';
            const title = it.url
              ? '<a href="' + esc(it.url) + '" target="_blank" rel="noopener">' + esc(it.title) + '</a>'
              : esc(it.title);
            return '<div class="card' + stale + '">' +
              '<div class="title">' + title + '</div>' +
              '<div class="' + srcClass(it.source) + '">' + esc(it.source || '') +
              (it.id ? ' · ' + esc(it.id) : '') + '</div>' +
              '</div>';
          }).join('')) +
      '</div>';
    board.appendChild(colEl);
  });
  if (data.error) {
    document.getElementById('footer').textContent = 'error: ' + data.error;
  }
}
load();
setInterval(load, 5000);
</script>
</body>
</html>`;

Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/api/board.json") {
      const json = await aggregateBoard();
      return new Response(json, {
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    }
    return new Response(HTML, { headers: { "content-type": "text/html; charset=utf-8" } });
  },
});

console.error(`[vibe-kit board] serving ${repo} on http://localhost:${port}`);
