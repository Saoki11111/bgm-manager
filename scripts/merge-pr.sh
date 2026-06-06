#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 PR_NUMBER" >&2
    exit 2
fi

pr_number="$1"

current_branch="$(git branch --show-current)"
pr_json="$(gh pr view "$pr_number" --json headRefName,baseRefName,state,mergeStateStatus,statusCheckRollup)"

state="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
base_branch="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["baseRefName"])')"
head_branch="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headRefName"])')"
merge_state="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["mergeStateStatus"])')"
failed_checks="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(sum(1 for c in data["statusCheckRollup"] if c.get("conclusion") not in ("SUCCESS", "SKIPPED")))')"

if [ "$state" != "OPEN" ]; then
    echo "PR #$pr_number is not open: $state" >&2
    exit 1
fi

if [ "$base_branch" != "main" ]; then
    echo "PR #$pr_number base is not main: $base_branch" >&2
    exit 1
fi

if [ "$merge_state" != "CLEAN" ]; then
    echo "PR #$pr_number is not cleanly mergeable: $merge_state" >&2
    exit 1
fi

if [ "$failed_checks" != "0" ]; then
    echo "PR #$pr_number has failing or incomplete checks." >&2
    gh pr checks "$pr_number"
    exit 1
fi

gh pr merge "$pr_number" --squash --delete-branch
git switch main
git pull --ff-only origin main

if git show-ref --verify --quiet "refs/heads/$head_branch"; then
    git branch -d "$head_branch"
fi

git fetch --prune origin

echo
echo "Merged PR #$pr_number."
echo "Previous branch: $current_branch"
echo
git status --short --branch
echo
git branch -a
