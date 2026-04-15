# codedb-cli

Fast CLI client for [codedb](https://github.com/justrach/codedb) — code intelligence at microsecond latency.

Replaces the original bash wrapper with a compiled Go binary. Zero subprocess overhead: queries complete in ~6ms end-to-end (vs ~330ms with bash+curl+jq).

## Install

```bash
cd cli
go build -o codedb-cli .
cp codedb-cli ~/.local/bin/
```

Requires `codedb` binary on PATH.

## Usage

### Single repo

```bash
# Auto-starts daemon if needed
codedb-cli /path/to/repo tree
codedb-cli /path/to/repo search "handleAuth" 10
codedb-cli /path/to/repo find Store
codedb-cli /path/to/repo word "allocator"
codedb-cli /path/to/repo outline src/main.zig
codedb-cli /path/to/repo deps src/server.zig
codedb-cli /path/to/repo hot 5
codedb-cli /path/to/repo read src/lib.zig 10 30
codedb-cli /path/to/repo status
```

### Machine-wide search

Run one codedb daemon per configured root, then search all of them in parallel:

```bash
# Start daemons for all roots (one per port, incrementing from port_start)
codedb-cli machine start

# Parallel fan-out to all running daemons (rg fallback for roots without a daemon)
codedb-cli machine search "handleAuth" 10
codedb-cli machine word "Explorer"
codedb-cli machine find "Store"

# Management
codedb-cli machine status
codedb-cli machine roots
codedb-cli machine stop
```

## Configuration

Config lives at `~/.config/codedb-cli/config.toml` (created on first run):

```toml
# Path to codedb binary
binary = "codedb"

# Default port for single-root daemon
daemon_port = 7719

# Starting port for machine-wide daemons (one per root, incrementing)
port_start = 7720

# Machine-wide roots
roots = [
  "~/src",
  "~/projects",
]
```

State (PIDs, port assignments) is stored at `~/.local/state/codedb-cli/`.

## Architecture

```
user query
    │
    ├─ single root ──► daemon on :7719 ──► HTTP GET ──► JSON ──► formatted output
    │
    └─ machine ──┬──► daemon :7720 (root 1) ─┐
                 ├──► daemon :7721 (root 2) ──┤ goroutine fan-out
                 ├──► daemon :7722 (root 3) ──┤ (parallel)
                 ├──► ...                     │
                 └──► rg fallback (large) ────┘──► merged results
```

- Each daemon is a `codedb <root> --port N serve` process
- Queries hit the daemon's HTTP API (~200-500µs server-side)
- Roots without a running daemon fall back to `rg`
- The Go binary adds <1ms overhead over raw HTTP

## Integration

### codedb-turn-context

The [turn-context helper](../scripts/codedb-turn-context) calls `codedb-cli machine search/word` to prefetch code context before each agent turn. Output format is compatible: `==> /path <==` headers on stdout, timing on stderr, `path:line` for word mode.

### Daemon lifecycle

Daemons are long-lived background processes. `machine start` is idempotent — it skips roots that already have a healthy daemon. PIDs are tracked in the state directory for `machine stop`.
