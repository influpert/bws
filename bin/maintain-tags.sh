#!/usr/bin/env bash
# Maintain the action's bare major tags (v1, v2, …). The action's major tracks
# the bws CLI major (derived from the ref at runtime), so there are no semver
# release tags — just moving major tags.
#
# It maintains the CURRENT and PREVIOUS bws major: the latest non-prerelease bws
# major upstream and the one before it (never below v1). For each, it ensures a
# vN tag exists and points at the current HEAD — creating a new major line
# automatically when bws bumps, and keeping both current with main. Tags for
# older majors are left frozen where they are.
set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

head="$(git rev-parse HEAD)"

# Latest non-prerelease bws major upstream (the "current" major).
latest_major="$(
  curl -fsSL -H "Authorization: Bearer ${GH_TOKEN}" \
    "https://api.github.com/repos/bitwarden/sdk-sm/releases?per_page=100" \
  | jq -r 'map(select((.tag_name | startswith("bws-v")) and (.prerelease | not)))
           | .[0].tag_name // empty | ltrimstr("bws-v") | split(".")[0]'
)"
[ -n "$latest_major" ] || { echo "could not determine the latest bws major"; exit 0; }

# The previous major, floored at 1.
prev_major=$(( latest_major - 1 ))
[ "$prev_major" -lt 1 ] && prev_major=1

for m in $(seq "$prev_major" "$latest_major"); do
  tag="v${m}"
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    if [ "$(git rev-list -n1 "$tag")" != "$head" ]; then
      git tag -f "$tag" "$head"
      git push -f origin "refs/tags/${tag}"
      echo "moved ${tag} -> ${head}"
    else
      echo "${tag} already at HEAD"
    fi
  else
    git tag "$tag" "$head"
    git push origin "refs/tags/${tag}"
    echo "created ${tag} (bws ${m}.x)"
  fi
done
