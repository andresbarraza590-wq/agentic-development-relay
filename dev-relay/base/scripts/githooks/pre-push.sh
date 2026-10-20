#!/bin/sh
# pre-push — deterministic guard (belt-and-suspenders for governance.never).
# Blocks direct pushes to protected branches and non-fast-forward (force)
# pushes, so the git rules cannot be skipped even if an agent ignores its prose.
#
# Activate per repo with:  bash .github/scripts/githooks/install-hooks.sh
#
# git passes, on stdin, one line per ref being pushed:
#   <local ref> <local sha> <remote ref> <remote sha>

protected="develop master main"

# true when the sha is all zeros (branch create or delete)
is_zero() {
    case "$1" in
        "" ) return 1 ;;
        *[!0]* ) return 1 ;;
        * ) return 0 ;;
    esac
}

status=0
while read -r local_ref local_sha remote_ref remote_sha; do
    branch=${remote_ref#refs/heads/}

    # Block direct pushes that target a protected branch.
    for p in $protected; do
        if [ "$branch" = "$p" ]; then
            echo "BLOCKED: direct push to protected branch '$p'. Open a pull request from a feature/* branch." >&2
            status=1
        fi
    done
    case "$branch" in
        release/*)
            echo "BLOCKED: direct push to protected branch '$branch'. Open a pull request from a feature/* branch." >&2
            status=1
            ;;
    esac

    # Deletion of a remote branch: nothing further to check on this ref.
    is_zero "$local_sha" && continue

    # Force / non-fast-forward: the remote tip exists but is not an ancestor
    # of the local tip, so this push would rewrite published history.
    if ! is_zero "$remote_sha"; then
        if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
            echo "BLOCKED: non-fast-forward (force) push to '$branch' would rewrite remote history." >&2
            status=1
        fi
    fi
done

exit $status
