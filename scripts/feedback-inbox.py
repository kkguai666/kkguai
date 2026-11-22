#!/usr/bin/env python3
"""Reads kkguai feedback from the maintainer's Gmail through the win01 helper.

Feedback reaches Gmail as FormSubmit submissions with the subject prefix
"[kkguai]". The OAuth token and the proxy live on win01, so this script calls
the gmail.mjs helper there over SSH instead of keeping a second copy of the
credentials on the Mac.

New messages are written as JSON files and printed one per line for a scheduled
session to pick up. Processed message ids are remembered in a local state file,
so a message is handled once.

Each new message is also forwarded verbatim to the maintainer's QQ mailbox
(from the same Gmail account), unless --no-forward is given.

Usage:
    scripts/feedback-inbox.py [--state PATH] [--out DIR] [--limit N]
                              [--forward-to ADDR] [--no-forward] [--replay]

Exit codes: 0 (new mail or none), 4 SSH/Gmail failure.
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HOST = "win01"
REMOTE_CMD = r"C:\Users\Administrator\.claude\skills\gmail-api\scripts\kkguai.cmd"
QUERY = 'subject:[kkguai] newer_than:120d'
STATE_VERSION = 1
DEFAULT_FORWARD = "1076822082@qq.com"


def ssh(remote_command, timeout=120):
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", HOST, remote_command],
        capture_output=True, text=True, timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).strip()[:500])
    return result.stdout


def gmail(*args):
    quoted = " ".join('"%s"' % arg if " " in arg else arg for arg in args)
    out = ssh('"%s" %s' % (REMOTE_CMD, quoted))
    start = out.find("[") if out.lstrip().startswith("[") else out.find("{")
    if start < 0:
        raise RuntimeError("unexpected gmail.mjs output: %r" % out[:200])
    return json.loads(out[start:])


def plain_text(text):
    """FormSubmit mails the submission as HTML; keep the words, drop the markup."""
    if "<" not in text:
        return text.strip()
    import html as html_module
    import re
    text = re.sub(r"(?is)<(script|style)\b.*?</\1>", "", text)
    text = re.sub(r"(?i)<br\s*/?>|</p>|</div>|</pre>|</tr>", "\n", text)
    text = re.sub(r"(?i)</t[dh]>", "  ", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html_module.unescape(text)
    lines = [line.rstrip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line.strip()).strip()


def load_state(path):
    try:
        data = json.loads(Path(path).read_text())
        if data.get("version") == STATE_VERSION:
            return data
    except (OSError, ValueError):
        pass
    return {"version": STATE_VERSION, "ids": []}


def save_state(path, state):
    state["ids"] = state["ids"][-5000:]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1))
    tmp.replace(path)


def forward(to, subject, text):
    """Send a copy through the same Gmail account; the body travels as a file so
    newlines and non-ASCII text survive ssh + cmd quoting."""
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False) as fh:
        fh.write(text)
        local = fh.name
    remote = r"C:\Users\Administrator\AppData\Local\Temp\kkguai-forward.txt"
    try:
        subprocess.run(["scp", "-q", local, "%s:%s" % (HOST, remote.replace("\\", "/"))],
                       check=True, capture_output=True, timeout=60)
        subject_b64 = base64.b64encode(subject.encode()).decode()
        ssh('"%s" sendfile %s %s "%s"' % (REMOTE_CMD, to, subject_b64, remote))
    finally:
        os.unlink(local)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--state", default=str(Path.home() / ".local/state/kkguai/feedback-state.json"))
    parser.add_argument("--out", default=str(Path.home() / ".local/state/kkguai/feedback"))
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--forward-to", default=DEFAULT_FORWARD)
    parser.add_argument("--no-forward", action="store_true")
    parser.add_argument("--replay", action="store_true", help="print messages that were seen before")
    args = parser.parse_args()

    state = load_state(args.state)
    seen = set(state["ids"])

    try:
        listing = gmail("list", QUERY, str(args.limit))
    except Exception as error:  # noqa: BLE001 — the caller only needs the reason
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 4

    listing = listing if isinstance(listing, list) else []
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    new_count = 0
    for entry in reversed(listing):  # oldest first, so forwarding keeps the original order
        message_id = entry.get("id")
        if not message_id or (message_id in seen and not args.replay):
            continue
        try:
            full = gmail("read", message_id)
        except Exception as error:  # noqa: BLE001
            print(json.dumps({"error": str(error), "id": message_id}, ensure_ascii=False))
            continue
        item = {
            "id": message_id,
            "from": full.get("from", entry.get("from")),
            "subject": full.get("subject", entry.get("subject")),
            "date": full.get("date", entry.get("date")),
            "text": plain_text(full.get("body", "")),
        }
        path = out_dir / ("%s.json" % message_id)
        path.write_text(json.dumps(item, ensure_ascii=False, indent=1))

        if not args.no_forward:
            try:
                forward(args.forward_to, item["subject"] or "[kkguai]", item["text"])
                item["forwarded_to"] = args.forward_to
            except Exception as error:  # noqa: BLE001 — reading matters more than the copy
                item["forward_error"] = str(error)[:300]

        item["file"] = str(path)
        print(json.dumps(item, ensure_ascii=False))
        new_count += 1

    if new_count:
        state["ids"] = sorted(seen | {entry.get("id") for entry in listing if entry.get("id")})
        save_state(args.state, state)
    print(json.dumps({"new": new_count, "checked": len(listing)}, ensure_ascii=False), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
