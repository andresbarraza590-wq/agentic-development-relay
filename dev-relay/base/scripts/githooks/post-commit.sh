#!/bin/sh
# post-commit — lightweight best-effort local audit trail. Attempts one JSON line per commit
# to an untracked log inside .git, so it never touches the working tree or
# creates dirty state. Failures are visible warnings but do not undo the commit.
# Complements the pipeline's human-readable per-story activity log.

log="$(git rev-parse --git-dir)/hooks-audit.jsonl"

sha=$(git rev-parse HEAD)
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if python3 -c 'import json' >/dev/null 2>&1; then
    python=python3
elif python -c 'import json' >/dev/null 2>&1; then
    python=python
else
    echo "WARNING: post-commit audit entry skipped because Python is unavailable." >&2
    exit 0
fi

git log -1 --format='%s' | LOG="$log" SHA="$sha" TS="$ts" "$python" -c '
import json
import ipaddress
import os
import re
import sys

subject = sys.stdin.read()
if subject.endswith("\n"):
    subject = subject[:-1]
subject = re.sub(r"(?i)\b(?:AKIA|ASIA)[0-9A-Z]{16}\b", "<redacted-credential>", subject)
subject = re.sub(
    r"(?i)\b((?:access|refresh|id|oauth|auth|bearer)[_-]?token|client[_-]?(?:secret|assertion)|consumer[_-]?secret|api[_-]?key|secret|token|password)\s*[:=]\s*(?:\x22[^\x22]*\x22|\x27[^\x27]*\x27|\S+)",
    r"\1=<redacted>",
    subject,
)
subject = re.sub(r"(?i)\bbearer\s+\S+", "Bearer <redacted>", subject)
subject = re.sub(r"(?i)(https?://)[^/@\s]+@", r"\1<redacted>@", subject)
subject = re.sub(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "<redacted-email>", subject)
subject = re.sub(r"(?i)([\x22\x27])(?:[A-Z]:\\|\\\\)[^\x22\x27\r\n]+\1", "<absolute-path>", subject)
subject = re.sub(r"(?i)(?<![A-Za-z0-9:])(?:[A-Z]:\\|\\\\)\S+", "<absolute-path>", subject)
subject = re.sub(r"(?<![A-Za-z0-9._:/-])/(?!/)(?:[^\s/]+/)*[^\s]*", "<absolute-path>", subject)

def redact_ip(match):
    candidate = match.group(0)
    try:
        ipaddress.ip_address(candidate)
    except ValueError:
        return candidate
    return "<ip-address>"

subject = re.sub(r"(?<![0-9A-Fa-f:.])(?:[0-9A-Fa-f:.]*[:.][0-9A-Fa-f:.]+)(?![0-9A-Fa-f:.])", redact_ip, subject)
subject = re.sub(r"(?i)\b(?:[A-Z0-9-]+\.)*(?:<CORP_INTERNAL_DOMAINS>)\b", "<internal-host>", subject)
with open(os.environ["LOG"], "a", encoding="utf-8", newline="\n") as audit_log:
    json.dump(
        {"ts": os.environ["TS"], "commit": os.environ["SHA"], "subject": subject},
        audit_log,
        ensure_ascii=True,
        separators=(",", ":"),
    )
    audit_log.write("\n")
'
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "WARNING: post-commit audit entry failed with status $rc; commit remains created." >&2
fi

exit 0
