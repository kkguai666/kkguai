#!/usr/bin/env python3
"""Reads kkguai feedback from the maintainer's QQ mailbox over IMAP.

Feedback arrives as Web3Forms submissions with the subject prefix "[kkguai]".
New messages are written as JSON files and printed one per line, so a scheduled
session can pick them up. Already-seen UIDs are remembered in a small state file,
and nothing is marked read in the mailbox.

Credentials come from the environment (KKGUAI_IMAP_USER / KKGUAI_IMAP_PASS) or
from the login Keychain item "kkguai-feedback" (account = the email address):

    security add-generic-password -s kkguai-feedback -a you@qq.com -w <auth-code>

Usage:
    scripts/feedback-inbox.py [--state PATH] [--out DIR] [--limit N] [--show-seen]

Exit codes: 0 new mail (or none), 3 not configured, 4 login/IMAP failure.
"""
import argparse
import email
import email.policy
import html
import imaplib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOST = "imap.qq.com"
KEYCHAIN_SERVICE = "kkguai-feedback"
SUBJECT_PREFIX = "[kkguai]"
STATE_VERSION = 1

# QQ mail rejects clients that never send the IMAP ID command ("Unsafe Login").
imaplib.Commands["ID"] = ("NONAUTH", "AUTH", "SELECTED")
ID_ARGS = ('("name" "kkguai-feedback" "version" "1.0" '
           '"vendor" "kkguai" "contact" "noreply@example.com")')


def keychain_lookup(service):
    try:
        user = subprocess.run(["security", "find-generic-password", "-s", service],
                              capture_output=True, text=True, check=True).stdout
        account = re.search(r'"acct"<blob>="([^"]*)"', user)
        secret = subprocess.run(["security", "find-generic-password", "-s", service, "-w"],
                                capture_output=True, text=True, check=True).stdout.strip()
        return (account.group(1) if account else None), secret
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None, None


def credentials():
    user = os.environ.get("KKGUAI_IMAP_USER")
    password = os.environ.get("KKGUAI_IMAP_PASS")
    if user and password:
        return user, password
    account, secret = keychain_lookup(KEYCHAIN_SERVICE)
    if account and secret:
        return account, secret
    return None, None


def load_state(path):
    try:
        data = json.loads(Path(path).read_text())
        if data.get("version") == STATE_VERSION:
            return data
    except (OSError, ValueError):
        pass
    return {"version": STATE_VERSION, "uids": []}


def save_state(path, state):
    state["uids"] = state["uids"][-5000:]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1))
    tmp.replace(path)


def decode_header(value):
    if value is None:
        return ""
    return str(value).strip()


def message_text(msg):
    plain, rich = None, None
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        ctype = part.get_content_type()
        if ctype not in ("text/plain", "text/html"):
            continue
        try:
            body = part.get_content()
        except (LookupError, ValueError):
            payload = part.get_payload(decode=True) or b""
            body = payload.decode(part.get_content_charset() or "utf-8", "replace")
        if ctype == "text/plain" and plain is None:
            plain = body
        elif ctype == "text/html" and rich is None:
            rich = body
    if plain is None and rich is not None:
        text = re.sub(r"(?is)<(script|style).*?</\1>", "", rich)
        text = re.sub(r"(?i)<br\s*/?>|</p>|</div>", "\n", text)
        text = re.sub(r"<[^>]+>", "", text)
        plain = html.unescape(text)
    return (plain or "").strip()


def connect(user, password):
    conn = imaplib.IMAP4_SSL(HOST, 993, timeout=30)
    conn.login(user, password)
    try:
        conn._simple_command("ID", ID_ARGS)
    except imaplib.IMAP4.error:
        pass  # servers without ID support simply ignore the extra command
    typ, data = conn.select("INBOX", readonly=True)
    if typ != "OK":
        raise imaplib.IMAP4.error("cannot open INBOX: %s" % (data,))
    return conn


def search_feedback(conn):
    typ, data = conn.uid("SEARCH", None, "SUBJECT", '"%s"' % SUBJECT_PREFIX)
    if typ != "OK":
        raise imaplib.IMAP4.error("search failed: %s" % (data,))
    uids = []
    for chunk in data:
        if chunk:
            uids.extend(int(part) for part in chunk.split())
    return sorted(uids)


def read_message(conn, uid):
    typ, data = conn.uid("FETCH", str(uid), "(BODY.PEEK[])")
    if typ != "OK":
        return None
    raw = None
    for part in data:
        if isinstance(part, tuple) and len(part) == 2:
            raw = part[1]
            break
    if raw is None:
        return None
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    return {
        "uid": uid,
        "date": decode_header(msg.get("Date")),
        "from": decode_header(msg.get("From")),
        "reply_to": decode_header(msg.get("Reply-To")),
        "subject": decode_header(msg.get("Subject")),
        "text": message_text(msg),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--state", default=str(Path.home() / ".local/state/kkguai/feedback-state.json"))
    parser.add_argument("--out", default=str(Path.home() / ".local/state/kkguai/feedback"))
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--show-seen", action="store_true", help="print seen messages again")
    args = parser.parse_args()

    user, password = credentials()
    if not user or not password:
        print(json.dumps({"error": "not configured",
                          "hint": "set KKGUAI_IMAP_USER/KKGUAI_IMAP_PASS or create Keychain item '%s'" % KEYCHAIN_SERVICE},
                         ensure_ascii=False))
        return 3

    state = load_state(args.state)
    seen = set(state["uids"])

    conn = None
    try:
        conn = connect(user, password)
        uids = search_feedback(conn)[-args.limit:]

        out_dir = Path(args.out)
        out_dir.mkdir(parents=True, exist_ok=True)
        new_count = 0
        for uid in uids:
            if uid in seen and not args.show_seen:
                continue
            item = read_message(conn, uid)
            if item is None:
                continue
            path = out_dir / ("%d.json" % uid)
            path.write_text(json.dumps(item, ensure_ascii=False, indent=1))
            print(json.dumps({"uid": uid, "file": str(path), "subject": item["subject"],
                              "from": item["from"], "reply_to": item["reply_to"],
                              "date": item["date"], "text": item["text"]}, ensure_ascii=False))
            new_count += 1
        if new_count:
            state["uids"] = sorted(seen | set(uids))
            save_state(args.state, state)
        print(json.dumps({"new": new_count, "checked": len(uids)}, ensure_ascii=False), file=sys.stderr)
        return 0
    except Exception as error:  # noqa: BLE001 — the caller only needs the reason
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        return 4
    finally:
        if conn is not None:
            try:
                conn.logout()
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
