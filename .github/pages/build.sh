#!/usr/bin/env bash
# Complete the compiled HTML into a publishable site.
# Usage: .github/pages/build.sh [output-dir]
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${1:-$root/_site}"

if [[ ! -f "$out/spec/SPEC.html" ]]; then
  echo "No compiled HTML in $out, compile the specification first" >&2
  exit 1
fi

# Send visitors of the bare site URL to the entrypoint.
cat > "$out/index.html" <<'HTML'
<!DOCTYPE html>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=spec/SPEC.html">
<link rel="canonical" href="spec/SPEC.html">
<a href="spec/SPEC.html">CSIL Node Packaging Specification</a>
HTML
