#!/usr/bin/env bash
# =============================================================================
# sources-state.sh: print what a GNUstep build would be made from right now
# =============================================================================
#
# One line per sources.lock repository, with the commit at the tip of its
# ref. The workflow publishes this as SOURCES next to the tarballs; the
# scheduled run compares it with the published one and builds only when
# something moved, so a merge to libs-base, libs-gui or any other fork
# rebuilds GNUstep without that repo dispatching anything. The sysroot's
# `continuous` artifacts aren't listed: they move with nearly every base or
# userland merge, and a push or manual run picks them up.
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")"

grep -v '^#' sources.lock | while read -r name url ref; do
    [ -n "$name" ] || continue
    commit=$(git ls-remote "$url" "refs/heads/$ref" | awk '{ print $1 }')
    [ -n "$commit" ] || { echo "FAIL: $name: no branch $ref at $url" >&2; exit 1; }
    printf '%s\t%s\t%s\n' "$name" "$ref" "$commit"
done
