#!/usr/bin/env bash
# =============================================================================
# test-sdk-app.sh: cross-build a GNUstep app with the SDK alone
# =============================================================================
#
# Shows the SDK is enough to cross-compile GNUstep software: in a fresh
# toolchain container that has only the SDK (no sysroot, no build tree), it
# builds NextBSD's Terminal (nextbsd/apps-terminal: gnustep-make, an Info
# plist merged with plmerge, X11 through pkg-config) and installs it into a
# staging root, then checks the app's binary.
#
# Environment: T, SDK_TARBALL (the SDK tarball), OUT (where the app's tarball
# goes; default .build/out), APP_REPO and APP_REF (default nextbsd/apps-terminal,
# its default branch).
# =============================================================================

set -euo pipefail

: "${T:?set T to amd64 or arm64}"
: "${SDK_TARBALL:?set SDK_TARBALL to nextbsd-gnustep-sdk-<arch>.tar.gz}"
: "${APP_REPO:=https://github.com/nextbsd/apps-terminal.git}"
: "${APP_REF:=}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
: "${OUT:=$BUILD/out}"
WORK="$BUILD/sdk-test-$T"
mkdir -p "$WORK" "$OUT"
case "$T" in amd64) want='X86-64' ;; arm64) want='AArch64' ;; *) exit 1 ;; esac

t0=$(date +%s)
tar -C "$WORK" -xzf "$SDK_TARBALL"
export NEXTBSD_SDK="$WORK/nextbsd-gnustep-sdk-$T"
# shellcheck disable=SC1091
. "$NEXTBSD_SDK/env.sh"
export GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

git clone -q --depth 1 ${APP_REF:+--branch "$APP_REF"} "$APP_REPO" "$WORK/app"
cd "$WORK/app"
make -j"$(nproc)" messages=yes
make install DESTDIR="$WORK/stage"
t1=$(date +%s)

bin=$(find "$WORK/stage" -type f -path '*.app/*' -perm -u+x | while read -r f; do
    head -c 4 "$f" | grep -q ELF && echo "$f"; done | head -1)
[ -n "$bin" ] || { echo "FAIL: no ELF executable in the installed app" >&2; exit 1; }
echo "==> $bin"
"$NEXTBSD_CLANG_BINDIR/llvm-readelf" -h "$bin" | grep -E 'Class|OS/ABI|Machine'
"$NEXTBSD_CLANG_BINDIR/llvm-readelf" -h "$bin" | grep -q "Machine:.*$want" || { echo "FAIL: not $want" >&2; exit 1; }
"$NEXTBSD_CLANG_BINDIR/llvm-readelf" -d "$bin" | grep -E 'NEEDED|RPATH|RUNPATH'
"$NEXTBSD_CLANG_BINDIR/llvm-readelf" -d "$bin" | grep -q 'NEEDED.*libgnustep-gui' || { echo "FAIL: does not link libgnustep-gui" >&2; exit 1; }
find "$WORK/stage" | sed "s#^$WORK/stage##" | sort
tar -C "$WORK/stage" -czf "$OUT/sdk-test-app-$T.tar.gz" .
echo "app cross-built with the SDK in $((t1 - t0))s (including unpacking the SDK)"
printf '%s\t%s\t%d\n' "$T" sdk-app "$((t1 - t0))" > "$OUT/sdk-test-time-$T.tsv"
