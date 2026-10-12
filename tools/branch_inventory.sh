#!/usr/bin/env bash
# Read-only branch inventory. Prints a markdown table of every local/remote branch and worktree branch,
# its relationship to the AUTHORITATIVE line, and any commits NOT patch-equivalent to the authoritative line.
# Usage: tools/branch_inventory.sh [authoritative-ref]   (default: origin/dev)
# Never modifies refs, the working tree or the remote.
set -euo pipefail
AUTH="${1:-origin/dev}"
git rev-parse --verify -q "$AUTH" >/dev/null || { echo "authoritative ref $AUTH not found" >&2; exit 2; }
echo "Authoritative line: \`$AUTH\` @ $(git rev-parse --short "$AUTH")"
echo
echo "| ref | tip | behind auth | ahead of auth (commits) | patch-unique vs auth | status |"
echo "|---|---|---|---|---|---|"
unmerged=0
while read -r ref; do
  [ "$ref" = "$AUTH" ] && continue
  case "$ref" in origin/HEAD|*/HEAD) continue;; esac
  behind=$(git rev-list --count "$ref..$AUTH")
  ahead=$(git rev-list --count "$AUTH..$ref")
  uniq=$(git cherry "$AUTH" "$ref" 2>/dev/null | grep -c '^+' || true)
  if [ "$ahead" = "0" ]; then status="integrated (fully reachable from auth)"
  elif [ "$uniq" = "0" ]; then status="integrated (patch-equivalent)"
  else status="UNMERGED WORK - see recovery ledger"; unmerged=$((unmerged+1)); fi
  echo "| \`$ref\` | $(git rev-parse --short "$ref") | $behind | $ahead | $uniq | $status |"
done < <(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes)
echo
echo "Tags: $(git tag -l | tr '\n' ' ')"
echo "Worktrees: $(git worktree list | wc -l)"
echo "Branches with unmerged work: $unmerged"
