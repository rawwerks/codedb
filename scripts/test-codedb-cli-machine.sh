#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/scripts/codedb-cli"
TMPDIR="$(mktemp -d)"
trap 'pkill -f "$TMPDIR/fake-codedb .* serve" 2>/dev/null || true; rm -rf "$TMPDIR"' EXIT

ROOT1="$TMPDIR/root1"
ROOT2="$TMPDIR/root2"
mkdir -p "$ROOT1/sub" "$ROOT2"
printf 'alpha\ncodedb-cli smoke\n' > "$ROOT1/sub/a.py"
printf 'import asyncio\nasyncio.run(main())\n' > "$ROOT2/b.py"

export CODEDB_MACHINE_ROOTS="$ROOT1:$ROOT2"

search_out="$(CODEDB_BINARY="$TMPDIR/does-not-exist" "$CLI" machine search 'codedb-cli' 3)"
[[ "$search_out" == *"$ROOT1/sub/a.py"* ]]

word_out="$(CODEDB_BINARY="$TMPDIR/does-not-exist" "$CLI" machine word 'asyncio' 5)"
[[ "$word_out" == *"$ROOT2/b.py:1"* ]]

status_out="$(CODEDB_BINARY="$TMPDIR/does-not-exist" "$CLI" machine status)"
[[ "$status_out" == *"$ROOT1"* ]]
[[ "$status_out" == *"mode: rg + optional cached codedb snapshot"* ]]

FAKE_CODEDB="$TMPDIR/fake-codedb"
FAKE_CODEDB_PID_FILE="$TMPDIR/fake-codedb.pid"
cat > "$FAKE_CODEDB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cmd="${2:-}"
case "$cmd" in
  serve)
    : "${FAKE_CODEDB_PID_FILE:?}"
    echo $$ > "$FAKE_CODEDB_PID_FILE"
    exec sleep 300
    ;;
  snapshot)
    : > codedb.snapshot
    ;;
  --version|-v)
    echo 'fake-codedb 0.0'
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$FAKE_CODEDB"

ROOT3="$TMPDIR/root3"
mkdir -p "$ROOT3"
printf 'x = 1\n' > "$ROOT3/c.py"
printf 'y = 2\n' > "$ROOT3/d.py"

CACHE_BASE="$TMPDIR/cache"
rebuild_out="$(
  CODEDB_MACHINE_ROOTS="$ROOT1:$ROOT3" \
  CODEDB_CACHE_BASE="$CACHE_BASE" \
  CODEDB_MACHINE_SNAPSHOT_MAX_FILES=1 \
  CODEDB_BINARY="$FAKE_CODEDB" \
  "$CLI" machine rebuild
)"
[[ "$rebuild_out" == *"$ROOT1"* ]]
[[ "$rebuild_out" == *"skip snapshot: 2 files exceeds CODEDB_MACHINE_SNAPSHOT_MAX_FILES=1"* ]]

status_out="$(
  CODEDB_MACHINE_ROOTS="$ROOT1:$ROOT3" \
  CODEDB_CACHE_BASE="$CACHE_BASE" \
  CODEDB_MACHINE_SNAPSHOT_MAX_FILES=1 \
  CODEDB_BINARY="$FAKE_CODEDB" \
  "$CLI" machine status
)"
[[ "$status_out" == *"$ROOT1"* ]]
[[ "$status_out" == *"snapshot: present"* ]]
[[ "$status_out" == *"$ROOT3"* ]]
[[ "$status_out" == *"mode: rg-only (root too large for a practical single codedb snapshot)"* ]]

set +e
FAKE_CODEDB_PID_FILE="$FAKE_CODEDB_PID_FILE" \
CODEDB_BINARY="$FAKE_CODEDB" \
CODEDB_PORT=7789 \
CODEDB_STARTUP_WAIT_STEPS=2 \
CODEDB_STARTUP_WAIT_INTERVAL=0.1 \
"$CLI" "$ROOT1" start >/dev/null 2>&1
start_status=$?
set -e

if [[ "$start_status" -eq 0 ]]; then
  echo "expected start to time out with fake codedb" >&2
  exit 1
fi

if [[ ! -f "$FAKE_CODEDB_PID_FILE" ]]; then
  echo "fake codedb never recorded its pid" >&2
  exit 1
fi

serve_pid="$(cat "$FAKE_CODEDB_PID_FILE")"
sleep 0.2
if kill -0 "$serve_pid" 2>/dev/null; then
  echo "fake codedb serve process leaked after startup timeout" >&2
  exit 1
fi

echo "ok"
