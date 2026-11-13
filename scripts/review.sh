#!/usr/bin/env bash
# Hands a running web app to the other coding agent for a black-box review.
# The reviewer works in an empty temporary folder: it gets the URL, the brief and the
# review instructions, never the code. Results land in .second-opinion/ in the current
# directory, and the last line printed is the verdict (KEEP GOING or DONE).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review.sh --url URL --brief "what it is, who it's for, what to focus on"
                 [--reviewer codex|claude] [--bar 7] [--out .second-opinion]

  --reviewer  defaults to the other agent (codex inside Claude Code, claude inside Codex);
              if that one isn't installed, a fresh session of the same agent reviews
  --bar       minimum score for Works, Usefulness and Polish (default 7)

Environment:
  SECOND_OPINION_MODEL        model for the reviewer (default: the CLI's own default)
  SECOND_OPINION_FULL_ACCESS  set to 1 to run Codex without its sandbox, if its sandbox
                              stops it from launching a browser
EOF
}

url="" brief="" reviewer="" bar="${SECOND_OPINION_BAR:-7}" out=".second-opinion"
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url=${2:-}; shift 2 ;;
    --brief) brief=${2:-}; shift 2 ;;
    --reviewer) reviewer=${2:-}; shift 2 ;;
    --bar) bar=${2:-}; shift 2 ;;
    --out) out=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$url" ] && [ -n "$brief" ] || { usage >&2; exit 2; }
[[ "$bar" =~ ^([1-9]|10)$ ]] || { echo "--bar must be a number from 1 to 10" >&2; exit 2; }
builder=""
if [ -n "${CLAUDECODE:-}" ]; then builder=claude; elif [ -n "${CODEX_THREAD_ID:-}" ]; then builder=codex; fi
if [ -z "$reviewer" ]; then
  # The other agent if it's installed; otherwise a fresh session of the same one.
  case "$builder" in claude) reviewer=codex ;; codex) reviewer=claude ;; *) reviewer=claude ;; esac
  if ! command -v "$reviewer" >/dev/null && [ -n "$builder" ] && command -v "$builder" >/dev/null; then
    echo "The $reviewer CLI isn't installed, so a fresh $builder session will review instead." >&2
    reviewer=$builder
  fi
fi
case "$reviewer" in codex|claude) ;; *) echo "--reviewer must be codex or claude" >&2; exit 2 ;; esac
command -v "$reviewer" >/dev/null || { echo "The $reviewer CLI isn't installed or isn't on PATH." >&2; exit 3; }
mode=cross-model
[ "$reviewer" = "$builder" ] && mode=same-agent
command -v python3 >/dev/null || { echo "python3 is needed to read the scores." >&2; exit 3; }

here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
n=1; while [ -e "$out/review-$(printf %02d "$n").md" ]; do n=$((n + 1)); done
round=$(printf %02d "$n")
prev="$out/review-$(printf %02d $((n - 1))).md"

chrome=""
for c in "${CHROME_PATH:-}" \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "$(command -v google-chrome 2>/dev/null || true)" \
  "$(command -v chromium 2>/dev/null || true)" \
  "$(command -v chromium-browser 2>/dev/null || true)"; do
  [ -n "$c" ] && [ -x "$c" ] && { chrome=$c; break; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/second-opinion.XXXXXX")
profile=$(mktemp -d "${TMPDIR:-/tmp}/second-opinion-chrome.XXXXXX")
chrome_pid=""
cleanup() {
  [ -n "$chrome_pid" ] && kill "$chrome_pid" 2>/dev/null && wait "$chrome_pid" 2>/dev/null
  rm -rf "$work" "$profile"
}
trap cleanup EXIT
mkdir -p "$work/shots"

# Start the browser here, outside the reviewer's sandbox (Codex's macOS sandbox can't launch
# Chrome itself), and give the reviewer puppeteer-core to drive it over the DevTools port.
ws=""
if [ -n "$chrome" ] && command -v npm >/dev/null; then
  "$chrome" --headless=new --remote-debugging-port=0 --user-data-dir="$profile" \
    --no-first-run --no-default-browser-check --hide-scrollbars about:blank >/dev/null 2>&1 &
  chrome_pid=$!
  for _ in $(seq 1 50); do
    [ -s "$profile/DevToolsActivePort" ] && break
    sleep 0.2
  done
  if [ -s "$profile/DevToolsActivePort" ]; then
    port=$(sed -n 1p "$profile/DevToolsActivePort")
    ws="ws://127.0.0.1:$port$(sed -n 2p "$profile/DevToolsActivePort")"
    (cd "$work" && npm init -y >/dev/null && npm i --silent --no-audit --no-fund puppeteer-core >/dev/null 2>&1) \
      || ws=""
  fi
fi

cp "$here/REVIEWER.md" "$work/REVIEWER.md"
{
  printf '\n## This review\n\n'
  printf -- '- **Round:** %s\n' "$round"
  printf -- '- **URL:** %s\n' "$url"
  if [ -n "$ws" ]; then
    printf -- '- **Browser:** headless Chrome is running. puppeteer-core is installed here. Connect with\n'
    printf "  \`require('puppeteer-core').connect({ browserWSEndpoint: '%s' })\`\n" "$ws"
  else
    printf -- '- **Browser:** none started (Chrome or npm not found). Use any browser tooling you have.\n'
  fi
  if [ -f "$prev" ]; then
    cp "$prev" "$work/previous-review.md"
    printf -- '- **Previous review:** previous-review.md\n'
  fi
  printf -- '- **Brief from the builder:**\n\n'
  printf '%s\n' "$brief" | sed 's/^/  > /'
} >> "$work/REVIEWER.md"

prompt="You are the reviewer. Read REVIEWER.md in this folder and follow it. Write review.md and scores.json here."
echo "Round $round: $reviewer is reviewing $url (this takes a few minutes)..." >&2
status=0
if [ "$reviewer" = codex ]; then
  args=(exec --skip-git-repo-check -C "$work")
  if [ "${SECOND_OPINION_FULL_ACCESS:-}" = 1 ]; then
    args+=(--dangerously-bypass-approvals-and-sandbox)
  else
    args+=(-s workspace-write -c sandbox_workspace_write.network_access=true)
  fi
  [ -n "${SECOND_OPINION_MODEL:-}" ] && args+=(-m "$SECOND_OPINION_MODEL")
  codex "${args[@]}" "$prompt" < /dev/null > "$work/reviewer.log" 2>&1 || status=$?
else
  args=(-p "$prompt" --max-turns 60 --permission-mode acceptEdits
        --allowedTools "Bash" "Read" "Write" "Edit" "Glob" "Grep" "WebFetch")
  [ -n "${SECOND_OPINION_MODEL:-}" ] && args+=(--model "$SECOND_OPINION_MODEL")
  (cd "$work" && claude "${args[@]}") < /dev/null > "$work/reviewer.log" 2>&1 || status=$?
fi

if [ ! -s "$work/review.md" ] || [ ! -s "$work/scores.json" ]; then
  echo "The reviewer didn't finish (exit code $status). Last lines of its output:" >&2
  tail -n 20 "$work/reviewer.log" >&2
  exit 4
fi

{
  if [ "$mode" = same-agent ]; then
    printf '> Same-agent review: a fresh %s session with no access to the build, not a different model.\n\n' "$reviewer"
  else
    printf '> Cross-model review by %s.\n\n' "$reviewer"
  fi
  cat "$work/review.md"
} > "$out/review-$round.md"
cp "$work/scores.json" "$out/scores-$round.json"
if [ -n "$(ls -A "$work/shots")" ]; then cp -R "$work/shots" "$out/shots-$round"; fi

cat "$out/review-$round.md"
echo
python3 -I - "$out" "$n" "$bar" "$reviewer" "$mode" <<'PY'
import json, sys
out, n, bar, reviewer, mode = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
path = f"{out}/scores-{n:02d}.json"
try:
    with open(path) as f:
        s = json.load(f)
    s.update(reviewer=reviewer, mode=mode)
    with open(path, "w") as f:
        json.dump(s, f, indent=1)
except (OSError, ValueError, AttributeError):
    pass

def load(i):
    try:
        with open(f"{out}/scores-{i:02d}.json") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None

def passes(s):
    try:
        return (all(int(s[k]) >= bar for k in ("works", "usefulness", "polish"))
                and int(s.get("blocking_bugs", 0)) == 0 and s.get("real_browser", True) is not False)
    except (KeyError, TypeError, ValueError):
        return False

rows = [(i, load(i)) for i in range(1, n + 1)]
keys = ("first_impression", "works", "usefulness", "polish", "wow", "blocking_bugs")
print("Round  " + "  ".join(k.replace("_", " ") for k in keys) + "  pass  reviewer")
for i, s in rows:
    cells = "  ".join(str((s or {}).get(k, "?")).rjust(len(k)) for k in keys)
    who = (s or {}).get("reviewer", "?") + (" (same agent)" if (s or {}).get("mode") == "same-agent" else "")
    print(f"{i:>5}  {cells}  {'yes' if s and passes(s) else 'no ':<4}  {who}")
cur, prev = rows[-1][1], rows[-2][1] if n > 1 else None
if cur is None:
    print("VERDICT: KEEP GOING (scores.json couldn't be read)")
elif cur.get("real_browser") is False:
    print("VERDICT: KEEP GOING (the reviewer couldn't use a real browser)")
elif passes(cur) and prev is not None and passes(prev):
    print(f"VERDICT: DONE (two rounds in a row at {bar}+ with no blocking bugs)")
elif passes(cur):
    print(f"VERDICT: KEEP GOING (this round passed; one more passing round to finish)")
else:
    print(f"VERDICT: KEEP GOING (needs Works, Usefulness and Polish at {bar}+ and no blocking bugs)")
PY
