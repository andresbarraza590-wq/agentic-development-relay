#!/usr/bin/env bash
# pre-commit — deterministic guard (belt-and-suspenders for guardrail PII-1 and
# "never commit secrets"). Rejects staged changes that look like secrets or that
# add oversized binaries to git history.
#
# Activate per repo with:  bash .github/scripts/githooks/install-hooks.sh

max_bytes=5242880   # 5 MiB - keep large binaries out of git

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/deva-pre-commit.XXXXXX") || {
    echo "pre-commit: unable to create safety-check workspace; commit rejected." >&2
    exit 1
}
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
paths_file="$work_dir/paths"
blob_file="$work_dir/blob"
entry_file="$work_dir/entry"
blocked=0

# Only newly added/copied/modified/renamed files, scanning each current staged blob.
# NUL delimiters preserve every literal path; Git would quote or
# C-escape for display and names containing embedded newlines.
if ! git diff --cached --name-only -z --diff-filter=ACMR > "$paths_file"; then
    echo "pre-commit: cannot enumerate staged files; commit rejected." >&2
    exit 1
fi

while IFS= read -r -d '' f; do
    if ! git ls-files --stage -z -- "$f" > "$entry_file"; then
        echo "pre-commit: cannot inspect staged index entry '$f'; commit rejected." >&2
        exit 1
    fi
    entry=""
    if ! IFS= read -r -d '' entry < "$entry_file"; then
        echo "pre-commit: missing staged index entry for '$f'; commit rejected." >&2
        exit 1
    fi
    metadata=${entry%%$'\t'*}
    read -r mode object_id stage <<< "$metadata"
    if [ "$stage" != "0" ] || ! object_type=$(git cat-file -t "$object_id" 2>/dev/null); then
        echo "pre-commit: invalid staged index entry for '$f'; commit rejected." >&2
        exit 1
    fi
    if [ "$mode" = "160000" ]; then
        if [ "$object_type" != "commit" ]; then
            echo "pre-commit: gitlink '$f' does not reference a commit; commit rejected." >&2
            exit 1
        fi
        continue
    fi
    if [ "$object_type" != "blob" ]; then
        echo "pre-commit: unsupported staged object type '$object_type' for '$f'; commit rejected." >&2
        exit 1
    fi

    # Size guard.
    if ! bytes=$(git cat-file -s "$object_id" 2>/dev/null); then
        echo "pre-commit: cannot inspect staged object '$f'; commit rejected." >&2
        exit 1
    fi
    bytes=${bytes//[[:space:]]/}
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "pre-commit: invalid staged object size for '$f'; commit rejected." >&2
        exit 1
    fi
    if [ "$bytes" -gt "$max_bytes" ]; then
        echo "BLOCKED: '$f' is ${bytes} bytes (> ${max_bytes} limit). Use artifact storage, not git." >&2
        blocked=1
    fi

    # High-confidence secret patterns (kept narrow to limit false positives).
    # Scan the staged object itself because Git emits no textual diff for a blob
    # it classifies as binary. grep -a keeps matching deterministic for such data.
    if ! git cat-file blob "$object_id" > "$blob_file" 2>/dev/null; then
        echo "pre-commit: cannot read staged object '$f'; commit rejected." >&2
        exit 1
    fi
    if grep -aEiq '(-----BEGIN [A-Z ]*PRIVATE KEY-----|A(KIA|SIA)[0-9A-Z]{16}|((access|refresh|id|oauth|auth|bearer)[_-]?token|client[_-]?(secret|assertion)|consumer[_-]?secret|api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*("[^"]+"|'\''[^'\'']+'\''|[A-Za-z0-9+/_=-]{16,}))' "$blob_file"; then
        echo "BLOCKED: '$f' appears to contain a secret or credential. Remove it or use a secrets manager." >&2
        blocked=1
    else
        grep_status=$?
        if [ "$grep_status" -gt 1 ]; then
            echo "pre-commit: secret scan failed for '$f'; commit rejected." >&2
            exit 1
        fi
    fi
done < "$paths_file"

if [ "$blocked" -ne 0 ]; then
    echo "pre-commit: commit rejected. Fix the issues above." >&2
    exit 1
fi

exit 0
