#!/bin/sh
# Hourly kkguai feedback check (run by launchd, see scripts/com.dd.kkguai-feedback.plist).
#
# The check itself is plain shell + python: no Claude session is started while there is
# nothing new, which is what keeps a quiet hour free. Only new feedback starts one headless
# Claude run, with the instructions in scripts/feedback-agent.md.
set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/Users/dd/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

REPO="/Users/dd/hello/pstsc-src"
STATE="$HOME/.local/state/kkguai"
LOCK="$STATE/.hourly.lock"
LOG="$STATE/feedback-agent.log"
CLAUDE_BIN="${KKGUAI_CLAUDE_BIN:-$HOME/.local/bin/claude}"
PENDING="$STATE/pending.txt"
INBOX_ERR="$STATE/inbox.err"

mkdir -p "$STATE"
# One run at a time: a fixing session can take much longer than the hour between checks.
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "$(date '+%F %T') skip: previous run still running" >> "$LOG"
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

# Keep the log small; it is plain text appended once per hour.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 2000000 ]; then
    mv -f "$LOG" "$LOG.old"
fi
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

cd "$REPO" || { log "skip: repo missing"; exit 0; }

touch "$PENDING"
out=$(python3 -I scripts/feedback-inbox.py 2> "$INBOX_ERR")
status=$?
summary=$(tail -1 "$INBOX_ERR" 2>/dev/null)
log "inbox exit=$status ${summary:-no summary}"
# SSH or Gmail trouble: nothing to do this hour, the state file is untouched so mail is not lost.
[ "$status" -eq 0 ] || exit 0

# New items print one JSON object per line; remember their files for this and later runs.
echo "$out" | python3 -I -c '
import json, os, sys
pending = sys.argv[1]
known = set()
if os.path.exists(pending):
    known = {line.strip() for line in open(pending) if line.strip()}
added = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        item = json.loads(line)
    except ValueError:
        continue
    path = item.get("file")
    if path and path not in known and path not in added:
        added.append(path)
if added:
    with open(pending, "a") as fh:
        fh.writelines(p + "\n" for p in added)
print(len(added))
' "$PENDING" > /dev/null 2>> "$LOG"

count=$(awk 'NF' "$PENDING" | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
    exit 0
fi
log "starting feedback session with $count pending item(s)"

prompt="$(cat scripts/feedback-agent.md)"
prompt="$prompt

---
待处理反馈文件（每行一个路径）：$PENDING
现在是 $(date '+%F %H:%M %Z')。"
echo "===== $(date '+%F %T') session start ($count items) =====" >> "$LOG"
/usr/bin/perl -e 'alarm shift; exec @ARGV' 7200 \
    "$CLAUDE_BIN" -p "$prompt" --permission-mode bypassPermissions >> "$LOG" 2>&1
code=$?
log "session exit=$code"

# A finished run leaves the list empty; anything left is retried next hour.
remaining=$(awk 'NF' "$PENDING" | wc -l | tr -d ' ')
log "remaining=$remaining"
exit 0
