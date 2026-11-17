#!/usr/bin/env bash
# Run a shell command inside the app's runtime base image (the Dockerfile's first FROM), so
# lint and tests use exactly the Python the image ships and follow the Dockerfile when the
# base image changes. The repository is mounted at the same path, so reports such as
# coverage.xml name files the host can resolve. The command runs as the calling user, with
# packages installed under a throwaway HOME, so no root-owned files are left behind.
#
# Usage: scripts/ci/in-runtime-image.sh '<command>'
#   e.g. scripts/ci/in-runtime-image.sh 'pip install -r requirements-dev.txt && python -m pytest'
set -euo pipefail

if (($# != 1)); then
  echo "Usage: $0 '<command>'" >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel)
image=$(awk 'toupper($1) == "FROM" { print $2; exit }' "$root/Dockerfile")
echo "Runtime image: $image" >&2

exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "$root:$root" --workdir "$root" \
  --env HOME=/tmp/home --env PYTHONUSERBASE=/tmp/home/.local --env PIP_USER=1 \
  --env PATH=/tmp/home/.local/bin:/usr/local/bin:/usr/bin:/bin \
  --env PIP_DISABLE_PIP_VERSION_CHECK=1 --env PIP_NO_CACHE_DIR=1 \
  "$image" sh -c "$1"
