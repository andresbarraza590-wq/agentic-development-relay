#!/bin/sh
# install-hooks.sh — point this git repository at the framework hooks.
#
# Run once per code repo, from the repo where .github/scripts/githooks was deployed
# (a per-repo framework install):
#
#    bash .github/scripts/githooks/install-hooks.sh
#
# It copies extensionless runtime hooks into Git's private framework-hooks
# directory, points core.hooksPath there, and marks the hooks executable.
# Re-run after re-installing the framework.
set -e

dir=$(cd "$(dirname "$0")" && pwd)
if ! git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null); then
    echo "ERROR: hooks directory ($dir) is not inside a git repository." >&2
    echo "Deploy the framework into this repo's .github before installing hooks." >&2
    exit 1
fi
common_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || printf '%s' "$git_dir")
existing_hook_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-path hooks 2>/dev/null || printf '%s/hooks' "$git_dir")
hook_dir="$common_dir/framework-hooks"
previous_dir="$hook_dir/previous"

mkdir -p "$hook_dir" "$previous_dir"

# Preserve active hook types that the framework does not wrap. Once
# core.hooksPath changes, hooks left only in the prior directory stop running.
if [ "$existing_hook_dir" != "$hook_dir" ]; then
    for existing_hook in "$existing_hook_dir"/*; do
        [ -f "$existing_hook" ] && [ -x "$existing_hook" ] || continue
        hook_name=${existing_hook##*/}
        case "$hook_name" in
            *.sample|pre-push|pre-commit|post-commit) continue ;;
        esac
        cp "$existing_hook" "$hook_dir/$hook_name"
        chmod +x "$hook_dir/$hook_name"
    done
fi

for hook in pre-push pre-commit post-commit; do
    # On a re-run core.hooksPath already resolves here, so leave the retired copy alone.
    if [ "$existing_hook_dir" != "$hook_dir" ]; then
        if [ -f "$existing_hook_dir/$hook" ]; then
            cp "$existing_hook_dir/$hook" "$previous_dir/$hook"
            chmod +x "$previous_dir/$hook"
        else
            rm -f "$previous_dir/$hook"
        fi
    fi

    cp "$dir/$hook.sh" "$hook_dir/$hook.framework"
    chmod +x "$hook_dir/$hook.framework"
    if [ "$hook" = "pre-push" ]; then
        cat > "$hook_dir/$hook" <<'EOF'
#!/bin/sh
refs_file=$(mktemp "${TMPDIR:-/tmp}/deva-pre-push.XXXXXX") || exit 1
trap 'rm -f "$refs_file"' EXIT HUP INT TERM
cat > "$refs_file" || exit 1
status=0
"$(dirname "$0")/pre-push.framework" "$@" < "$refs_file" || status=$?
if [ -f "$(dirname "$0")/previous/pre-push" ]; then
    previous_status=0
    "$(dirname "$0")/previous/pre-push" "$@" < "$refs_file" || previous_status=$?
    if [ "$status" -eq 0 ]; then
        status=$previous_status
    fi
fi
exit "$status"
EOF
    else
        cat > "$hook_dir/$hook" <<EOF
#!/bin/sh
set -e
"\$(dirname "\$0")/$hook.framework" "\$@"
if [ -f "\$(dirname "\$0")/previous/$hook" ]; then
    exec "\$(dirname "\$0")/previous/$hook" "\$@"
fi
EOF
    fi
    chmod +x "$hook_dir/$hook"
done
git -C "$dir" config core.hooksPath "$hook_dir"

echo "core.hooksPath set to: $hook_dir"
echo "Active hooks: pre-push (protected-branch + force-push guard), pre-commit (secret + large-file guard), post-commit (audit trail). Existing hooks ar"

