#!/usr/bin/env bash
# =============================================================================
# make-sdk.sh: assemble the GNUstep SDK for one architecture
# =============================================================================
#
# After build-gnustep.sh, packs nextbsd-gnustep-sdk-<arch>.tar.gz: a sysroot
# for cross-compiling GNUstep software for NextBSD, as nextbsd-kernel's
# kernel-sdk is for kexts. It holds:
#   - from the NextBSD sysroot, what compiling and linking need: /lib,
#     /usr/include, /usr/lib (without debug files), /usr/libdata/pkgconfig,
#     /usr/X11/include, /usr/X11/lib and /Developer/Link (compat, userland,
#     displayserver-support, xlibs, gnustep-support);
#   - the whole staged GNUstep (/System), gnustep-make's configuration included;
#   - bin/: clang, clang++ (cross/bin/nextbsd-cc) and LLVM's binutils;
#   - share/nextbsd-gnustep/: the arch's CONFIG_SITE file and the CMake
#     toolchain file;
#   - env.sh, which sets a shell up to use it (see sdk/env.sh.in), and
#     BUILD-INFO, the commits it was built from.
#
# Environment: T, SYSROOT, DESTDIR (as build-gnustep.sh), OUT (where the
# tarball goes; default .build/out).
# =============================================================================

set -euo pipefail

: "${T:?set T to amd64 or arm64}"
: "${SYSROOT:?set SYSROOT to the NextBSD sysroot}"
: "${DESTDIR:=/stage}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
: "${OUT:=$BUILD/out}"
NAME="nextbsd-gnustep-sdk-$T"
SDK="$BUILD/sdk-$T/$NAME"

case "$T" in
    amd64) GS_HOST=x86_64-nextbsd-freebsd;  CLANG_TARGET=x86_64-unknown-freebsd ;;
    arm64) GS_HOST=aarch64-nextbsd-freebsd; CLANG_TARGET=aarch64-unknown-freebsd ;;
    *) echo "FAIL: T=$T is not amd64 or arm64" >&2; exit 1 ;;
esac

[ -f "$DESTDIR/System/Library/Makefiles/common.make" ] || { echo "FAIL: no GNUstep in $DESTDIR; run build-gnustep.sh first" >&2; exit 1; }
[ ! -e "$SDK" ] || { echo "FAIL: $SDK already exists" >&2; exit 1; }
mkdir -p "$SDK" "$OUT"

echo "==> [$T] NextBSD sysroot"
(
    cd "$SYSROOT"
    tar -cf - --exclude=./usr/lib/debug \
        ./lib ./usr/include ./usr/lib ./usr/libdata/pkgconfig \
        ./usr/X11/include ./usr/X11/lib ./Developer/Link
) | tar -xf - -C "$SDK"

echo "==> [$T] GNUstep"
tar -C "$DESTDIR" -cf - ./System | tar -xf - -C "$SDK"

echo "==> [$T] tools and configuration"
mkdir -p "$SDK/bin" "$SDK/share/nextbsd-gnustep"
cp "$ROOT/cross/bin/nextbsd-cc" "$ROOT/cross/bin/nextbsd-llvm" "$SDK/bin/"
ln -s nextbsd-cc "$SDK/bin/clang"
ln -s nextbsd-cc "$SDK/bin/clang++"
for t in ar ranlib nm strip objcopy objdump readelf; do
    ln -s nextbsd-llvm "$SDK/bin/$t"
done
cp "$ROOT/cross/nextbsd-$T.site" "$ROOT/cross/cmake/nextbsd.cmake" "$SDK/share/nextbsd-gnustep/"
sed -e "s/@T@/$T/g" -e "s/@CLANG_TARGET@/$CLANG_TARGET/g" -e "s/@GS_HOST@/$GS_HOST/g" \
    "$ROOT/sdk/env.sh.in" > "$SDK/env.sh"
[ -f "$BUILD/BUILD-INFO-$T" ] && cp "$BUILD/BUILD-INFO-$T" "$SDK/BUILD-INFO"

tar -C "$BUILD/sdk-$T" -czf "$OUT/$NAME.tar.gz" "$NAME"
ls -la "$OUT/$NAME.tar.gz"
