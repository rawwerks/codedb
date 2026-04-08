# codedb-turn-context

A small Python helper that prefetches a compact block of code-local context on
every agent turn, so the model sees relevant file paths and snippets *before*
it decides whether to open a tool call.

It lives in `scripts/codedb-turn-context` as a standalone CLI with no
dependencies beyond the Python standard library and `codedb-cli`. The intent is
to be invoked by thin per-agent adapters — Claude Code hooks, pi extensions,
Codex launchers, whatever — on each user prompt, with the adapter piping the
helper's stdout into the model's context for that turn.

## What it does

Given a raw user message, it:

1. Extracts high-specificity literals from the message (backticks, quoted
   strings, absolute/relative paths, CLI flags, compound identifiers like
   `codedb-cli` or `handleAuth`, and a conservative two-word phrase fallback
   for things like `retry logic` or `connection refused`).
2. Runs up to two `codedb-cli machine` queries against the curated machine
   roots (configured via `CODEDB_MACHINE_ROOTS`).
3. Re-ranks the raw hits to prefer code files over docs/tests, definitions
   over references, basename matches, and files inside the current working
   directory.
4. Emits a compact `[fast-local-context]` block to stdout, or JSON with
   `--json`.

Typical end-to-end latency is 150–400 ms for a high-signal prompt; low-signal
prompts (`thanks`, `ok cool`) skip the query entirely and return nothing.

## Install

The helper ships in the codedb repo under `scripts/`. Copy it (or symlink it)
to somewhere on your `$PATH`:

```bash
cp scripts/codedb-turn-context ~/.local/bin/codedb-turn-context
chmod +x ~/.local/bin/codedb-turn-context
```

Verify it runs:

```bash
codedb-turn-context 'where is `codedb-cli` defined?'
```

You should see a `[fast-local-context]` block with a handful of hits.

## Per-user config

The helper intentionally ships with **no personal paths hard-coded**. If you
want hits to render with short display aliases (e.g. `GH/myrepo/src/main.rs`
instead of `/home/you/src/github/myrepo/src/main.rs`), drop a TOML config at
one of:

1. The path in `$CODEDB_TURN_CONTEXT_CONFIG` (exclusive: that path or nothing)
2. `$XDG_CONFIG_HOME/codedb-turn-context.toml` (if `XDG_CONFIG_HOME` is set)
3. `~/.config/codedb-turn-context.toml`

Or pass `--config <path>` directly.

A minimal config looks like this (full example in
`scripts/codedb-turn-context.config.example.toml`):

```toml
[path_aliases]
"GH"   = "~/src/github"
"WORK" = "~/src/work"
```

Keys are the short alias you want to see in output; values are absolute paths
(tildes are expanded). With no config present, the helper falls back to a
basename-derived short form — still readable, just less dense.

**The config is gitignored.** `scripts/codedb-turn-context.local.toml` and
`scripts/codedb-turn-context.toml` are both in `.gitignore` so users who
prefer an in-repo config can't accidentally leak personal layout to the
public repo.

## Output format

```
[fast-local-context]
queries: search:codedb-cli
- (h1) GH/codedb/docs/cli.md:21 — codedb-cli <command> # bash + curl + jq
- (h2) GH/codedb/docs/cli.md:43 — cp scripts/codedb-cli ~/.local/bin/codedb-cli
- (h3) GH/codedb/docs/cli.md:44 — chmod +x ~/.local/bin/codedb-cli
- (h4) GH/codedb/docs/cli.md:61 — codedb-cli [root] <command> [args...]
expand: codedb-turn-context expand <id>
[/fast-local-context]
```

Each hit carries an `(hN)` marker. Agents can ask the helper to expand any hit
into a file slice with surrounding context:

```bash
codedb-turn-context expand h1 --context 10
```

The cached form (`expand h1`) requires the same `cwd` as the original search.
For a stateless escape hatch, pass a path directly:

```bash
codedb-turn-context expand /abs/path/to/file.py:42 --context 5
```

The expand cache lives at `~/.cache/codedb-turn-context/last-{sha1}.json`,
keyed by `sha1(realpath(cwd))[:12]` so parallel agents in different repos
never collide.

## CWD boost

Pass `--cwd <path>` to boost hits whose realpath falls under that directory.
The boost (`+9`) is the largest single weight in the ranker, so hits in the
working repo win all-else-equal — but a real code definition outside the cwd
still beats a doc-mention-of-the-same-symbol inside the cwd. Adapters should
thread the agent's session cwd through on every invocation.

## Agent adapters

Adapters are kept out of the codedb repo so they can version with their host
agents. Two examples in the wild:

### Claude Code hook

`~/.claude/hooks/codedb-prompt-context.sh` is a 50-line Python shim that
reads the `UserPromptSubmit` event JSON on stdin, extracts the `prompt` and
`cwd`, and calls `codedb-turn-context --cwd <cwd> <prompt>`. Anything printed
to stdout gets injected into the model's context for that turn via the
standard hook `additionalContext` mechanism.

Wire it into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/codedb-prompt-context.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

### pi extension

`~/.pi/agent/extensions/codedb-turn-context.ts` is a TypeScript extension
that hooks pi's `onUserPrompt` event, shells out to
`codedb-turn-context --cwd <session_cwd>`, and injects the stdout into the
turn as a context event. Set `PI_CODEDB_TURN_CONTEXT_COMMAND` to point at
your binary if you installed it somewhere nonstandard.

## Subcommands and flags

```
codedb-turn-context [options] <message>          # search
codedb-turn-context [options] expand <id|path:line>  # read file slice

Options:
  --json                Emit JSON instead of the text block
  --max-queries N       Max machine queries to run (default 2)
  --max-hits N          Max hits to return (default 4)
  --cwd PATH            Working directory for ranking + expand cache
  --context N           Lines of surrounding context for expand (default 10)
  --config PATH         Explicit per-user TOML config override
```

## Tests

```bash
bash scripts/test-codedb-turn-context.sh
```

The suite is self-contained — it builds tmpdir fixtures and forces an empty
config via `CODEDB_TURN_CONTEXT_CONFIG=` so it never picks up your real
`~/.config/codedb-turn-context.toml`.
