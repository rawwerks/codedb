#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/scripts/codedb-cli"
TOOL="$REPO_ROOT/scripts/codedb-turn-context"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

chmod +x "$TOOL"

ROOT1="$TMPDIR/root1"
ROOT2="$TMPDIR/root2"
mkdir -p "$ROOT1/docs" "$ROOT2/src"

cat > "$ROOT1/docs/cli.md" <<'EOF'
codedb-cli <command>             # bash + curl + jq
cp scripts/codedb-cli ~/.local/bin/codedb-cli
EOF

cat > "$ROOT2/src/server.py" <<'EOF'
def handleAuth(conn):
    raise RuntimeError("connection refused")
EOF

export CODEDB_CONTEXT_CLI="$CLI"
export CODEDB_MACHINE_ROOTS="$ROOT1:$ROOT2"
export CODEDB_BINARY="$TMPDIR/does-not-exist"
# Force empty config so the test suite is hermetic and does not pick up
# whatever /home/$USER/.config/codedb-turn-context.toml happens to contain.
# Individual config-loader tests override this env var explicitly.
export CODEDB_TURN_CONTEXT_CONFIG=""

json_out="$($TOOL --json 'where is `codedb-cli` defined?')"
python3 - <<'PY' "$json_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
assert any(q["query"] == "codedb-cli" and q["mode"] == "search" for q in obj["queries"]), obj
assert any(hit["display_path"].endswith("docs/cli.md") for hit in obj["hits"]), obj
assert "[fast-local-context]" in obj["text_block"], obj
PY

json_out="$($TOOL --json 'why is handleAuth failing?')"
python3 - <<'PY' "$json_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
assert any(q["query"] == "handleAuth" and q["mode"] == "word" for q in obj["queries"]), obj
assert any("handleAuth" in hit["text"] for hit in obj["hits"]), obj
PY

json_out="$($TOOL --json 'I got "connection refused" from the daemon')"
python3 - <<'PY' "$json_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
assert any(q["query"] == "connection refused" and q["mode"] == "search" for q in obj["queries"]), obj
assert any("connection refused" in hit["text"] for hit in obj["hits"]), obj
PY

json_out="$($TOOL --json 'I got connection refused from the daemon')"
python3 - <<'PY' "$json_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
assert any(q["query"] == "connection refused" and q["mode"] == "search" for q in obj["queries"]), obj
assert any("connection refused" in hit["text"] for hit in obj["hits"]), obj
PY

json_out="$($TOOL --json 'thanks')"
python3 - <<'PY' "$json_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "skip", obj
assert obj["reason"] == "no_candidates", obj
assert obj["text_block"] == "", obj
PY

text_out="$($TOOL 'where is `codedb-cli` defined?')"
[[ "$text_out" == *"[fast-local-context]"* ]]
[[ "$text_out" == *"codedb-cli"* ]]

stdin_out="$(printf 'where is `codedb-cli` defined?' | $TOOL --json)"
python3 - <<'PY' "$stdin_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
PY

# ---- CWD boost: hits inside --cwd outrank equal-quality hits outside ----
# Two roots with the same kind of file (Python def) for the same symbol.
# Without --cwd, ranking is a tie broken by display_path order.
# With --cwd pointing at root1, the root1 hit must be first.
mkdir -p "$ROOT1/src"
cat > "$ROOT1/src/auth.py" <<'EOF'
def doSomething():
    return "in root1"
EOF
mkdir -p "$ROOT2/lib"
cat > "$ROOT2/lib/auth.py" <<'EOF'
def doSomething():
    return "in root2"
EOF

cwd_out="$(HOME=$TMPDIR $TOOL --json --cwd "$ROOT1" 'find doSomething')"
python3 - <<'PY' "$cwd_out" "$ROOT1"
import json, sys
obj, root1 = json.loads(sys.argv[1]), sys.argv[2]
assert obj["status"] == "ok", obj
first = obj["hits"][0]
assert first["path"].startswith(root1), f"cwd boost should put a hit under {root1} first, got {first['path']}"
# IDs should be sequential h1..hN
ids = [h.get("id") for h in obj["hits"]]
assert ids == [f"h{i+1}" for i in range(len(ids))], ids
PY

# Sanity: without --cwd, the ranking is tie-broken by display path length —
# this just confirms the cwd flag is what flipped the order, not the tool itself.
nocwd_out="$($TOOL --json 'find doSomething')"
python3 - <<'PY' "$nocwd_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
# Both roots present
paths = {h["path"] for h in obj["hits"]}
assert any("/root1/" in p for p in paths) and any("/root2/" in p for p in paths), paths
PY

# ---- expand: cache lookup by id (h1) ----
HOME="$TMPDIR" $TOOL --cwd "$ROOT1" 'find doSomething' >/dev/null
expand_h1="$(HOME=$TMPDIR $TOOL --cwd "$ROOT1" expand h1 --context 1)"
[[ "$expand_h1" == *"doSomething"* ]] || { echo "expand h1 missing doSomething: $expand_h1"; exit 1; }
[[ "$expand_h1" == *">"* ]] || { echo "expand h1 missing line marker: $expand_h1"; exit 1; }

# ---- expand: stateless path:line form (no cache needed) ----
expand_path="$($TOOL expand "$ROOT2/src/server.py:2" --context 2)"
[[ "$expand_path" == *"handleAuth"* ]] || { echo "expand path:line missing handleAuth: $expand_path"; exit 1; }

# ---- expand: missing id in cache returns nonzero ----
if HOME="$TMPDIR" $TOOL --cwd "$ROOT1" expand h99 2>/dev/null; then
  echo "expand h99 should have failed"
  exit 1
fi

# ---- expand: garbage token returns nonzero ----
if $TOOL expand 'not-an-id-or-path' 2>/dev/null; then
  echo "expand should reject garbage tokens"
  exit 1
fi

# ---- Text block now includes (h1) markers and the expand hint ----
text_out="$($TOOL --cwd "$ROOT1" 'find doSomething')"
[[ "$text_out" == *"(h1)"* ]] || { echo "text block missing (h1): $text_out"; exit 1; }
[[ "$text_out" == *"expand: codedb-turn-context expand"* ]] || { echo "text block missing expand hint"; exit 1; }

# ---- Per-user config: path_aliases from TOML appear in display_path ----
# Hermetic: point CODEDB_TURN_CONTEXT_CONFIG at a tmpdir TOML that aliases
# $ROOT1 as "TESTROOT". Hits under $ROOT1 must render with that prefix.
cat > "$TMPDIR/test-aliases.toml" <<TOML
[path_aliases]
"TESTROOT" = "$ROOT1"
TOML
cfg_out="$(CODEDB_TURN_CONTEXT_CONFIG="$TMPDIR/test-aliases.toml" $TOOL --json 'find doSomething')"
python3 - <<'PY' "$cfg_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
paths = [h["display_path"] for h in obj["hits"]]
assert any(p.startswith("TESTROOT/") for p in paths), f"expected TESTROOT/ alias in display paths, got {paths}"
PY

# ---- Per-user config: default-empty case renders with basename fallback ----
# Forcing env var empty means no config is loaded at all. Display paths should
# use the codedb-machine root's basename (root1 / root2) rather than an alias.
empty_out="$(CODEDB_TURN_CONTEXT_CONFIG="" $TOOL --json 'find doSomething')"
python3 - <<'PY' "$empty_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
paths = [h["display_path"] for h in obj["hits"]]
# No TESTROOT, no other custom alias — just basename-derived segments.
assert not any(p.startswith("TESTROOT/") for p in paths), f"unexpected TESTROOT alias leaked: {paths}"
assert any(p.startswith("root1/") or p.startswith("root2/") for p in paths), f"expected basename fallback, got {paths}"
PY

# ---- Per-user config: malformed TOML is ignored gracefully ----
# The tool must print a one-line warning to stderr and keep running with
# empty aliases. Users should never see a broken hook just because they
# fat-fingered their config.
cat > "$TMPDIR/bad-config.toml" <<'TOML'
[path_aliases
"GH" = "/tmp"
TOML
bad_out="$(CODEDB_TURN_CONTEXT_CONFIG="$TMPDIR/bad-config.toml" $TOOL --json 'find doSomething' 2>"$TMPDIR/bad-config.stderr")"
python3 - <<'PY' "$bad_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
PY
grep -q 'ignoring malformed config' "$TMPDIR/bad-config.stderr" || { echo "expected 'ignoring malformed config' warning on stderr, got: $(cat "$TMPDIR/bad-config.stderr")"; exit 1; }

# ---- Per-user config: wrong-type [path_aliases] section is ignored ----
cat > "$TMPDIR/wrong-type.toml" <<'TOML'
path_aliases = "this should be a table not a string"
TOML
wrong_out="$(CODEDB_TURN_CONTEXT_CONFIG="$TMPDIR/wrong-type.toml" $TOOL --json 'find doSomething' 2>"$TMPDIR/wrong-type.stderr")"
python3 - <<'PY' "$wrong_out"
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "ok", obj
PY
grep -q 'is not a table' "$TMPDIR/wrong-type.stderr" || { echo "expected 'is not a table' warning, got: $(cat "$TMPDIR/wrong-type.stderr")"; exit 1; }

# ---- --config CLI flag: explicit path overrides env var ----
explicit_out="$(CODEDB_TURN_CONTEXT_CONFIG="$TMPDIR/bad-config.toml" $TOOL --json --config "$TMPDIR/test-aliases.toml" 'find doSomething')"
python3 - <<'PY' "$explicit_out"
import json, sys
obj = json.loads(sys.argv[1])
paths = [h["display_path"] for h in obj["hits"]]
assert any(p.startswith("TESTROOT/") for p in paths), f"--config should override env var, got {paths}"
PY

echo "ok"
