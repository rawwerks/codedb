# codedb v0.2.57 launch tweets

Best times to post (PST): Tue-Thu, 8-10 AM
Best times to post (SGT): Tue-Thu, 11 PM - 1 AM

---

Tweet 1 (The big numbers)

codedb v0.2.57 is out.

10× faster cold indexing: 3.6s → 346ms
83% less cold RSS: 3.5GB → 580MB
92% less warm RSS: 1.9GB → 150MB

Worker-local parallel scan. Bounded id_to_path. WordHit 24B → 8B.

---

Tweet 2 (Internal lookup times - microseconds!)

Real benchmarks on openclaw (6,315 files) — linear scale:

codedb:  ~500µs  (0.0005s) — warm trigram index
fff-mcp: ~510µs  (0.00051s) — bigram + frecency (Rust+rayon)
ripgrep: ~500ms  (0.5s)    — cold disk scan
grep:    ~1,500ms (1.5s)   — cold disk scan

2.3x faster than fff-mcp. 6x better recall.
1,000x faster than ripgrep.
3,000x faster than grep.

---

Tweet 3 (What 500 microseconds means)

500 microseconds = 0.0005 seconds

Your AI agent can:
- Run 2,000 codedb searches in 1 second
- Or wait 1 second for a single grep

Warm index. No filesystem scan. No raw text dumps.

---

Tweet 4 (Git subprocess fix)

The watcher was forking git rev-parse 15 times per minute on idle repos.

Now: stat .git/HEAD mtime first.
Result: 87% fewer subprocesses. ~0 on idle.

Shoutout to @JF10R for reporting the unbounded growth issue.

---

Tweet 5 (Correctness fixes)

11 bug fixes in v0.2.57:

- TrigramIndex.removeFile: fixed ghost entries
- PostingList.removeDocId: O(log n) instead of O(n)
- TrigramIndex id_to_path: bounded with free-list
- Python/TS parsers: docstrings, block comments fixed

Index integrity now guaranteed.

---

Tweet 6 (MCP reliability)

MCP servers shouldn't be zombies.

- 10-minute idle timeout
- POLLHUP detection on stdin
- Clean shutdown on disconnect

Fixes issues reported by @destroyer22719 with Opencode.

---

Tweet 7 (Contributors)

18 issues closed. 10 contributors.

@JF10R: trigram growth, drainNotifyFile
@ocordeiro: symbol.line_end
@destroyer22719: MCP disconnections
@wilsonsilva: remote requests
@killop: Windows support
@sims1253: R language, PHP/Ruby fixes
@JustFly1984: DNS, version issues
@mochadwi: comparisons
@Mavis2103: memory ideas

Thank you all.

---

Tweet 8 (CTA)

Update now:

codedb update

Or fresh install:
curl -fsSL https://codedb.codegraff.com/install.sh | bash

macOS: signed + notarized
Linux: x86_64

---

Single tweet version

codedb v0.2.57: 10× faster indexing, 83% less cold RSS, 92% less warm RSS.

Internal search: ~500µs (0.5ms)
vs ripgrep: ~500ms (1,000× slower)
vs grep: ~1,500ms (3,000× slower)

codedb update

---

Thread starter

🚀 codedb v0.2.57

10× faster cold indexing
83% less cold RSS
92% less warm RSS
500µs internal search
1000× ripgrep

Full thread ↓
🧵

---

Emoji options

🚀 10× faster indexing
📉 83% less memory
⚡ 1000× ripgrep (500µs vs 500ms)
🛠️ 18 issues fixed
🙏 10 contributors

---

Hashtags

#codedb #zig #ai #mcp #codeintelligence #devtools #performance

---

Link to use

https://github.com/justrach/codedb/releases/tag/v0.2.57
