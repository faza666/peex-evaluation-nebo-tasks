#!/usr/bin/env bash
# Print the app version, MAJOR.MINOR.PATCH, with no tags or stored state:
#   MAJOR.MINOR  the VERSION file
#   PATCH        the commits on main since VERSION last changed
# Every squash-merge to main gets the next number; bumping VERSION restarts PATCH at 0.
# With PR_NUMBER set (pull request builds) it prints the version the merge would get, as a
# pre-release: 3.0.7-pr.42. Needs the full history (actions/checkout with fetch-depth: 0).
#
# Usage: [PR_NUMBER=42] core/scripts/ci/version.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ $(git rev-parse --is-shallow-repository) == true ]]; then
  echo "Shallow clone: the version needs the full history (fetch-depth: 0)." >&2
  exit 1
fi

base=$(tr -d '[:space:]' <VERSION)
if [[ ! $base =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must hold MAJOR.MINOR, e.g. 3.0; found '$base'." >&2
  exit 1
fi

since=$(git log -1 --format=%H -- VERSION)
if [[ -z $since ]]; then
  echo "VERSION is not committed yet." >&2
  exit 1
fi

if [[ -n ${PR_NUMBER:-} ]] && ! git diff --quiet HEAD^1 HEAD -- VERSION; then
  patch=0 # the pull request itself changes VERSION (HEAD is its merge commit, HEAD^1 is main)
else
  patch=$(git rev-list --count --first-parent "$since..HEAD")
fi

echo "$base.$patch${PR_NUMBER:+-pr.$PR_NUMBER}"
