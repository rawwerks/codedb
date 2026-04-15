const mer = @import("mer");

pub const meta: mer.Meta = .{
    .title = "Improvements",
    .description = "How codedb indexing went from 75s to 2.9s — a 26x speedup on real-world codebases.",
};

pub const prerender = true;

pub fn render(req: mer.Request) mer.Response {
    _ = req;
    return .{
        .status = .ok,
        .content_type = .html,
        .body = html,
    };
}

const html =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\  <meta charset="UTF-8">
    \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\  <title>Improvements — codedb</title>
    \\  <link rel="preconnect" href="https://fonts.googleapis.com">
    \\  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    \\  <link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700;800&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
    \\  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    \\  <style>
    \\    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    \\    :root {
    \\      --bg: #ffffff; --bg2: #f7faf8; --bg3: #eef5f0;
    \\      --dark: #0a0a0a; --dark2: #111111; --dark3: #1a1a1a;
    \\      --text: #111; --muted: #6b7280; --border: #e0e7e2;
    \\      --accent: #059669; --accent-light: #10b981; --accent-dim: rgba(5,150,105,0.10);
    \\      --green: #059669;
    \\      --mono: 'Geist Mono', ui-monospace, monospace;
    \\      --sans: 'Geist', system-ui, sans-serif;
    \\    }
    \\    html { scroll-behavior: smooth; }
    \\    body { background: var(--dark); color: var(--text); font-family: var(--sans); min-height: 100vh; overflow-x: hidden; }
    \\    a { color: inherit; text-decoration: none; }
    \\
    \\    /* Nav */
    \\    nav { position: sticky; top: 0; z-index: 100; background: rgba(10,10,10,0.92); backdrop-filter: blur(16px); border-bottom: 1px solid rgba(255,255,255,0.08); }
    \\    .nav-inner { max-width: 1100px; margin: 0 auto; padding: 0 40px; display: flex; align-items: center; justify-content: space-between; height: 60px; }
    \\    .wordmark { font-family: var(--sans); font-size: 17px; font-weight: 800; letter-spacing: -0.02em; color: #fff; }
    \\    .wordmark em { font-style: normal; color: var(--accent-light); }
    \\    .nav-links { display: flex; gap: 32px; align-items: center; }
    \\    .nav-links a { font-size: 13px; font-weight: 500; color: rgba(255,255,255,0.5); letter-spacing: 0.01em; transition: color 0.15s; }
    \\    .nav-links a:hover { color: #fff; }
    \\    .nav-cta { font-family: var(--sans); font-size: 13px !important; font-weight: 700 !important; color: #fff !important; background: var(--accent); padding: 8px 18px; border-radius: 6px; transition: background 0.15s; }
    \\    .nav-cta:hover { background: #15803d; }
    \\    .nav-burger { display: none; flex-direction: column; gap: 5px; background: none; border: none; cursor: pointer; padding: 4px; }
    \\    .nav-burger span { display: block; width: 22px; height: 2px; background: #fff; border-radius: 2px; transition: transform 0.2s, opacity 0.2s; }
    \\    .nav-burger.open span:nth-child(1) { transform: translateY(7px) rotate(45deg); }
    \\    .nav-burger.open span:nth-child(2) { opacity: 0; }
    \\    .nav-burger.open span:nth-child(3) { transform: translateY(-7px) rotate(-45deg); }
    \\    @media (max-width: 640px) {
    \\      .nav-burger { display: flex; }
    \\      .nav-links { display: none; flex-direction: column; gap: 0; position: absolute; top: 60px; left: 0; right: 0; background: rgba(10,10,10,0.97); backdrop-filter: blur(12px); border-bottom: 1px solid rgba(255,255,255,0.08); padding: 8px 0; }
    \\      .nav-links.open { display: flex; }
    \\      .nav-links a { padding: 14px 24px; font-size: 15px; }
    \\      .nav-cta { margin: 8px 24px 12px; padding: 12px 20px; border-radius: 6px; text-align: center; }
    \\    }
    \\
    \\    /* Hero */
    \\    .hero { background: var(--dark); padding: 80px 40px 0; max-width: 1100px; margin: 0 auto; }
    \\    .hero-label { font-family: var(--mono); font-size: 11px; font-weight: 600; letter-spacing: 0.16em; text-transform: uppercase; color: var(--accent-light); margin-bottom: 20px; display: flex; align-items: center; gap: 10px; }
    \\    .hero-label::before { content: ''; display: inline-block; width: 20px; height: 1px; background: var(--accent-light); }
    \\    .hero-headline { font-family: var(--sans); font-size: clamp(44px, 7vw, 88px); font-weight: 800; letter-spacing: -0.04em; line-height: 0.95; color: #fff; margin-bottom: 16px; }
    \\    .hero-headline .hl { color: var(--accent-light); }
    \\    .hero-sub { font-family: var(--mono); font-size: 12px; color: rgba(255,255,255,0.35); letter-spacing: 0.04em; margin-bottom: 64px; }
    \\
    \\    /* Stat row */
    \\    .stat-row { display: grid; grid-template-columns: repeat(4,1fr); gap: 16px; padding-bottom: 48px; }
    \\    @media (max-width: 700px) { .stat-row { grid-template-columns: repeat(2,1fr); } }
    \\    .stat-cell { background: rgba(22,163,74,0.06); border: 1px solid rgba(22,163,74,0.15); border-radius: 12px; padding: 28px 24px; text-align: center; }
    \\    .stat-val { font-family: var(--sans); font-size: clamp(32px, 4vw, 48px); font-weight: 800; letter-spacing: -0.04em; color: var(--accent-light); line-height: 1; margin-bottom: 4px; }
    \\    .stat-val .unit { font-size: 0.45em; font-weight: 600; color: rgba(255,255,255,0.4); letter-spacing: 0; vertical-align: super; margin-left: 2px; }
    \\    .stat-label { font-family: var(--mono); font-size: 11px; color: rgba(255,255,255,0.4); letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 8px; }
    \\    .stat-delta { font-family: var(--mono); font-size: 11px; color: var(--accent-light); letter-spacing: 0.02em; }
    \\
    \\    /* Before/after section */
    \\    .compare-section { background: var(--bg); padding: 80px 40px; }
    \\    .compare-inner { max-width: 1100px; margin: 0 auto; }
    \\    .section-eyebrow { font-family: var(--mono); font-size: 11px; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; color: var(--accent); margin-bottom: 10px; }
    \\    .section-heading { font-family: var(--sans); font-size: clamp(22px, 3vw, 32px); font-weight: 800; letter-spacing: -0.025em; color: var(--dark); margin-bottom: 32px; }
    \\    .section-sub { font-size: 14px; color: var(--muted); margin-bottom: 32px; max-width: 700px; line-height: 1.7; }
    \\    .bench-table { width: 100%; border-collapse: collapse; margin: 0 0 48px; font-size: 13px; }
    \\    .bench-table th { text-align: left; padding: 10px 12px; color: var(--muted); font-family: var(--mono); font-size: 11px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.08em; border-bottom: 2px solid var(--border); }
    \\    .bench-table td { padding: 10px 12px; border-bottom: 1px solid var(--border); font-family: var(--mono); font-size: 12px; }
    \\    .bench-table .fast { color: var(--accent); font-weight: 600; }
    \\    .bench-table .old { color: #ef4444; font-weight: 600; }
    \\    .bench-table .na { color: #d1d5db; }
    \\    .chart-row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 48px 0; }
    \\    @media (max-width: 700px) { .chart-row { grid-template-columns: 1fr; } }
    \\    .chart-card { background: var(--bg2); border: 1px solid var(--border); border-radius: 12px; padding: 24px; }
    \\    .chart-card h3 { font-family: var(--sans); font-size: 15px; font-weight: 700; color: var(--dark); margin-bottom: 16px; }
    \\    .chart-card canvas { width: 100% !important; height: 280px !important; }
    \\
    \\    /* Timeline section */
    \\    .timeline-section { background: var(--dark2); padding: 80px 40px; }
    \\    .timeline-inner { max-width: 1100px; margin: 0 auto; }
    \\    .timeline-section .section-heading { color: #fff; }
    \\    .timeline-section .section-eyebrow { color: var(--accent-light); }
    \\    .timeline-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 2px; margin-top: 2px; }
    \\    @media (max-width: 700px) { .timeline-grid { grid-template-columns: 1fr; } }
    \\    .timeline-card { background: var(--dark3); padding: 32px; border-radius: 8px; }
    \\    .timeline-card h3 { font-family: var(--sans); font-size: 15px; font-weight: 700; color: #fff; margin-bottom: 8px; }
    \\    .timeline-card p { font-size: 13px; color: rgba(255,255,255,0.4); line-height: 1.7; font-family: var(--mono); }
    \\    .timeline-card .num { font-family: var(--sans); font-size: 36px; font-weight: 800; color: var(--accent-light); letter-spacing: -0.04em; margin-bottom: 12px; }
    \\
    \\    /* CTA */
    \\    .cta-section { background: var(--dark); padding: 0 40px 100px; }
    \\    .cta-inner { max-width: 1100px; margin: 0 auto; border-top: 1px solid rgba(255,255,255,0.08); padding-top: 48px; text-align: center; }
    \\    .btn { display: inline-flex; align-items: center; justify-content: center; font-family: var(--sans); font-size: 14px; font-weight: 700; padding: 13px 28px; border-radius: 8px; background: var(--accent); color: #fff; transition: all 0.2s; white-space: nowrap; }
    \\    .btn:hover { background: #15803d; transform: translateY(-1px); box-shadow: 0 4px 12px rgba(22,163,74,0.25); }
    \\    .btn-ghost { background: transparent; border: 1px solid rgba(255,255,255,0.15); color: rgba(255,255,255,0.6); font-weight: 500; margin-left: 12px; }
    \\    .btn-ghost:hover { border-color: rgba(255,255,255,0.4); color: #fff; transform: none; box-shadow: none; }
    \\    .layout-footer { padding: 20px 40px; border-top: 1px solid rgba(255,255,255,0.06); font-size: 11px; color: rgba(255,255,255,0.2); text-align: center; font-family: var(--mono); letter-spacing: 0.04em; background: var(--dark); max-width: none; }
    \\    .layout-footer a { color: rgba(255,255,255,0.2); }
    \\    .layout-footer a:hover { color: rgba(255,255,255,0.5); }
    \\  </style>
    \\</head>
    \\<body>
    \\
    \\<!-- Nav -->
    \\<nav>
    \\  <div class="nav-inner">
    \\    <a href="/" class="wordmark">code<em>db</em></a>
    \\    <button class="nav-burger" id="burger" aria-label="Menu">
    \\      <span></span><span></span><span></span>
    \\    </button>
    \\    <div class="nav-links" id="nav-links">
    \\      <a href="/benchmarks">Benchmarks</a>
    \\      <a href="/improvements">Improvements</a>
    \\      <a href="/quickstart">Install</a>
    \\      <a href="/v0.2.57" style="color:var(--accent-light);">v0.2.57</a>
    \\      <a href="/privacy">Privacy</a>
    \\      <a href="https://github.com/justrach/codedb">GitHub</a>
    \\      <a href="/quickstart" class="nav-cta">Get started</a>
    \\    </div>
    \\  </div>
    \\</nav>
    \\
    \\<!-- Hero -->
    \\<div style="background:var(--dark);">
    \\  <div class="hero">
    \\    <div class="hero-label">Performance improvements</div>
    \\    <div class="hero-headline">
    \\      <span class="hl">75s</span> to <span class="hl">2.9s</span>
    \\    </div>
    \\    <div class="hero-sub">Cold-start indexing on openclaw (11,281 files, 2.29M lines) &mdash; a 26x speedup</div>
    \\
    \\    <div class="stat-row">
    \\      <div class="stat-cell">
    \\        <div class="stat-label">openclaw</div>
    \\        <div class="stat-val">26<span class="unit">x</span></div>
    \\        <div class="stat-delta">75s &rarr; 2.9s</div>
    \\      </div>
    \\      <div class="stat-cell">
    \\        <div class="stat-label">Query speed</div>
    \\        <div class="stat-val">469<span class="unit">x</span></div>
    \\        <div class="stat-delta">vs grep/find</div>
    \\      </div>
    \\      <div class="stat-cell">
    \\        <div class="stat-label">Token savings</div>
    \\        <div class="stat-val">92<span class="unit">x</span></div>
    \\        <div class="stat-delta">fewer bytes to LLM</div>
    \\      </div>
    \\      <div class="stat-cell">
    \\        <div class="stat-label">Re-index</div>
    \\        <div class="stat-val">&lt;2<span class="unit">ms</span></div>
    \\        <div class="stat-delta">per file change</div>
    \\      </div>
    \\    </div>
    \\  </div>
    \\</div>
    \\
    \\<!-- Before / After -->
    \\<div class="compare-section">
    \\  <div class="compare-inner">
    \\    <div class="section-eyebrow">Before vs After</div>
    \\    <div class="section-heading">Indexing speed — cold start</div>
    \\    <p class="section-sub">codedb builds all indexes on startup: structural outlines, trigram search, inverted word index, and dependency graph. These numbers show cold-start time on real open-source repos.</p>
    \\
    \\    <table class="bench-table">
    \\      <thead>
    \\        <tr><th>Repo</th><th>Files</th><th>Lines</th><th>Before</th><th>After</th><th>Speedup</th></tr>
    \\      </thead>
    \\      <tbody>
    \\        <tr><td>openclaw/openclaw</td><td>11,281</td><td>2.29M</td><td class="old">75 s</td><td class="fast">2.9 s</td><td class="fast">26x</td></tr>
    \\        <tr><td>vitessio/vitess</td><td>5,028</td><td>2.18M</td><td class="old">50 s</td><td class="fast">2.1 s</td><td class="fast">24x</td></tr>
    \\        <tr><td>codedb</td><td>20</td><td>12.6k</td><td class="na">17 ms</td><td class="fast">17 ms</td><td class="na">—</td></tr>
    \\        <tr><td>merjs</td><td>100</td><td>17.3k</td><td class="na">16 ms</td><td class="fast">16 ms</td><td class="na">—</td></tr>
    \\      </tbody>
    \\    </table>
    \\
    \\    <div class="chart-row">
    \\      <div class="chart-card">
    \\        <h3>Cold-start indexing (large repos)</h3>
    \\        <canvas id="indexChart"></canvas>
    \\      </div>
    \\      <div class="chart-card">
    \\        <h3>Query latency — MCP vs grep</h3>
    \\        <canvas id="queryChart"></canvas>
    \\      </div>
    \\    </div>
    \\
    \\    <div class="section-eyebrow" style="margin-top: 48px;">Query performance</div>
    \\    <div class="section-heading">Sub-millisecond everything</div>
    \\    <p class="section-sub">Once indexed, every query hits in-memory data structures. No filesystem scan. No re-parsing. These are warm MCP query times on openclaw.</p>
    \\
    \\    <table class="bench-table">
    \\      <thead>
    \\        <tr><th>Query</th><th>codedb MCP</th><th>ripgrep</th><th>grep</th><th>Speedup</th></tr>
    \\      </thead>
    \\      <tbody>
    \\        <tr><td>Reverse deps</td><td class="fast">1.3 ms</td><td class="na">n/a</td><td class="na">n/a</td><td class="fast">469x vs CLI</td></tr>
    \\        <tr><td>Word lookup</td><td class="fast">0.2 ms</td><td>65 ms</td><td>65 ms</td><td class="fast">325x</td></tr>
    \\        <tr><td>Symbol search</td><td class="fast">3.9 ms</td><td>763 ms</td><td>763 ms</td><td class="fast">200x</td></tr>
    \\        <tr><td>Full-text search</td><td class="fast">0.05 ms</td><td>5.3 ms</td><td>6.6 ms</td><td class="fast">1,340x</td></tr>
    \\        <tr><td>File tree</td><td class="fast">0.04 ms</td><td class="na">—</td><td class="na">—</td><td class="fast">1,253x vs CLI</td></tr>
    \\      </tbody>
    \\    </table>
    \\
    \\    <div class="section-eyebrow" style="margin-top: 48px;">Token efficiency</div>
    \\    <div class="section-heading">92x fewer tokens sent to your LLM</div>
    \\    <p class="section-sub">codedb returns structured, relevant results — not raw line dumps. For AI agents, this means dramatically fewer tokens per query and lower cost per interaction.</p>
    \\
    \\    <table class="bench-table">
    \\      <thead>
    \\        <tr><th>Repo</th><th>codedb MCP</th><th>ripgrep / grep</th><th>Reduction</th></tr>
    \\      </thead>
    \\      <tbody>
    \\        <tr><td>codedb (search "allocator")</td><td class="fast">~20 tokens</td><td>~32,564 tokens</td><td class="fast">1,628x fewer</td></tr>
    \\        <tr><td>merjs (search "allocator")</td><td class="fast">~20 tokens</td><td>~4,007 tokens</td><td class="fast">200x fewer</td></tr>
    \\      </tbody>
    \\    </table>
    \\  </div>
    \\</div>
    \\
    \\<!-- What changed -->
    \\<div class="timeline-section">
    \\  <div class="timeline-inner">
    \\    <div class="section-eyebrow">What changed</div>
    \\    <div class="section-heading">How we got 26x faster</div>
    \\    <div class="timeline-grid">
    \\      <div class="timeline-card">
    \\        <div class="num">1</div>
    \\        <h3>Parallel file walking</h3>
    \\        <p>FilteredWalker now uses thread-pool parallelism for directory traversal, saturating I/O on large repos instead of single-threaded stat() calls.</p>
    \\      </div>
    \\      <div class="timeline-card">
    \\        <div class="num">2</div>
    \\        <h3>Batch index construction</h3>
    \\        <p>Trigram, word, and outline indexes build concurrently per-file instead of sequentially. Arena allocators eliminate per-symbol malloc overhead.</p>
    \\      </div>
    \\      <div class="timeline-card">
    \\        <div class="num">3</div>
    \\        <h3>Smarter filtering</h3>
    \\        <p>Aggressive early pruning of node_modules, .git, zig-cache, __pycache__, and binary files. Fewer files touched = faster cold start.</p>
    \\      </div>
    \\    </div>
    \\  </div>
    \\</div>
    \\
    \\<!-- CTA -->
    \\<div class="cta-section">
    \\  <div class="cta-inner">
    \\    <a href="/quickstart" class="btn">Get started</a>
    \\    <a href="/benchmarks" class="btn btn-ghost">Full benchmarks</a>
    \\  </div>
    \\</div>
    \\
    \\<!-- Footer -->
    \\<footer class="layout-footer">
    \\  codedb &copy; 2025 Rach Pradhan &middot; <a href="https://github.com/justrach/codedb">GitHub</a> &middot; <a href="/privacy">Privacy</a>
    \\</footer>
    \\
    \\<!-- Charts -->
    \\<script>
    \\  const green = '#10b981', red = '#ef4444', gray = '#e5e7eb';
    \\  new Chart(document.getElementById('indexChart'), {
    \\    type: 'bar',
    \\    data: {
    \\      labels: ['openclaw (11k files)', 'vitess (5k files)'],
    \\      datasets: [
    \\        { label: 'Before', data: [75, 50], backgroundColor: red, borderRadius: 4 },
    \\        { label: 'After', data: [2.9, 2.1], backgroundColor: green, borderRadius: 4 }
    \\      ]
    \\    },
    \\    options: {
    \\      responsive: true, maintainAspectRatio: false,
    \\      plugins: { legend: { position: 'bottom', labels: { font: { family: "'Geist Mono'" }, color: '#6b7280' } } },
    \\      scales: {
    \\        y: { title: { display: true, text: 'Seconds', font: { family: "'Geist Mono'", size: 11 }, color: '#6b7280' }, grid: { color: '#f3f4f6' } },
    \\        x: { grid: { display: false }, ticks: { font: { family: "'Geist Mono'", size: 11 } } }
    \\      }
    \\    }
    \\  });
    \\  new Chart(document.getElementById('queryChart'), {
    \\    type: 'bar',
    \\    data: {
    \\      labels: ['Reverse deps', 'Word lookup', 'Symbol search', 'Full-text'],
    \\      datasets: [
    \\        { label: 'codedb MCP', data: [1.3, 0.2, 3.9, 0.05], backgroundColor: green, borderRadius: 4 },
    \\        { label: 'grep/ripgrep', data: [750, 65, 763, 6.6], backgroundColor: gray, borderRadius: 4 }
    \\      ]
    \\    },
    \\    options: {
    \\      responsive: true, maintainAspectRatio: false,
    \\      plugins: { legend: { position: 'bottom', labels: { font: { family: "'Geist Mono'" }, color: '#6b7280' } } },
    \\      scales: {
    \\        y: { type: 'logarithmic', title: { display: true, text: 'ms (log scale)', font: { family: "'Geist Mono'", size: 11 }, color: '#6b7280' }, grid: { color: '#f3f4f6' } },
    \\        x: { grid: { display: false }, ticks: { font: { family: "'Geist Mono'", size: 11 } } }
    \\      }
    \\    }
    \\  });
    \\  document.getElementById('burger')?.addEventListener('click', function() {
    \\    this.classList.toggle('open');
    \\    document.getElementById('nav-links').classList.toggle('open');
    \\  });
    \\</script>
    \\</body>
    \\</html>
;
