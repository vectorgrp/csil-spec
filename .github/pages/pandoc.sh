#!/usr/bin/env bash
# Run pandoc from the `pandoc/core` image on the current directory.
# Usage: .github/pages/pandoc.sh [pandoc-args...]
set -euo pipefail

exec docker run --rm --interactive \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/data" \
  "pandoc/core:${PANDOC_VERSION:-3.6.4}" \
  "$@"
