#!/usr/bin/env bash
# =============================================================================
# build-gnustep.sh: cross-build NextBSD's GNUstep core for one architecture
# =============================================================================
#
# Builds tools-make, libobjc2, libs-base, libs-corebase, libs-gui, libs-back
# (X11) and libs-av from NextBSD's forks (sources.lock), on a Linux build host,
# for NextBSD amd64 or arm64, and installs them into $DESTDIR. The result is
# what pkgdemon/nextbsd-gnustep's build-core-libs-nextbsd-dispatch.sh installs
# on a machine: the gershwin filesystem layout, the SYSTEM domain, the
# ng-gnu-gnu library combo, libdispatch and the blocks runtime from NextBSD's
# base system (linked through -ldispatch and -lBlocksRuntime links in
# /Developer/Link), ICU, Bonjour through mDNSResponder, and libs-back's X11
# server with cairo.
#
# How it cross-builds, without running anything built for the target:
#   - every configure runs in --host mode with CONFIG_SITE=cross/nextbsd-<arch>.site,
#     which answers the checks that would run a program on NextBSD with what a
#     native NextBSD build found; libs-base also reads it as its
#     --with-cross-compilation-info file;
#   - CC is plain "clang": cross/bin/nextbsd-cc, linked as clang and clang++
#     first on PATH, runs the image's clang for the target, against the
#     sysroot, and points the native paths GNUstep records (-I/usr/include,
#     -L/usr/lib/system, -L/Developer/Link ...) into the sysroot. The installed
#     gnustep-make configuration therefore says clang, as a native one does;
#   - /System on the build host is a link to $DESTDIR/System, so each library
#     finds the ones built before it where GNUstep's configure scripts and
#     makefiles look for them (/System/Library/Headers, Libraries, Makefiles),
#     and installs into the staging root with DESTDIR=$DESTDIR;
#   - the build-time tools gnustep-make runs on bundles and apps (plmerge,
#     pl2link) are the build host's (Ubuntu's gnustep-base-runtime), not the
#     ones just built; libs-gui skips make_services when cross-compiling.
#
# Environment (the CI workflow sets these):
#   T             amd64 | arm64
#   SYSROOT       the NextBSD sysroot: compat's base, then nextbsd-userland,
#                 nextbsd-displayserver-support, nextbsd-xlibs and
#                 nextbsd-gnustep-support extracted over it. Scratch: the
#                 /Developer/Link links are made in it.
#   CROSS_BINDIR  the image's clang/lld (set by the nextbsd-toolchain image)
#   DESTDIR       the staging root (default /stage)
#   CCACHE        non-empty: compile through ccache
#
# Usage:
#   ./build-gnustep.sh               every library, in sources.lock order
#   ./build-gnustep.sh libs-gui ...  only those (the earlier ones must already
#                                    be in $DESTDIR)
#
# Per-library build times go to .build/times-<arch>.tsv; the files configure
# generated (config.h, config.make ...) are copied to .build/configs-<arch>/
# so they can be compared with a native build's.
# =============================================================================

set -euo pipefail

: "${T:?set T to amd64 or arm64}"
: "${SYSROOT:?set SYSROOT to the NextBSD sysroot}"
: "${CROSS_BINDIR:?set CROSS_BINDIR to the toolchain clang directory}"
: "${DESTDIR:=/stage}"
: "${CCACHE:=}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
SRC="$BUILD/src-$T"
WRAP="$BUILD/bin-$T"
TIMES="$BUILD/times-$T.tsv"
CONFIGS="$BUILD/configs-$T"
SITE="$ROOT/cross/nextbsd-$T.site"

case "$T" in
    amd64) GS_HOST=x86_64-nextbsd-freebsd;  CLANG_TARGET=x86_64-unknown-freebsd;  CPU=x86_64 ;;
    arm64) GS_HOST=aarch64-nextbsd-freebsd; CLANG_TARGET=aarch64-unknown-freebsd; CPU=aarch64 ;;
    *) echo "FAIL: T=$T is not amd64 or arm64" >&2; exit 1 ;;
esac
# config.guess output for the build host; GNUstep's --build.
BUILD_TRIPLE="$(uname -m)-pc-linux-gnu"
JOBS="$(nproc 2>/dev/null || echo 2)"

SYSROOT="$(cd "$SYSROOT" && pwd)"
mkdir -p "$DESTDIR"
DESTDIR="$(cd "$DESTDIR" && pwd)"

comp() { echo; echo "==> [$T] $*"; }
note() { echo "    - $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# ---- the build environment ---------------------------------------------------

setup() {
    mkdir -p "$BUILD" "$SRC" "$WRAP" "$CONFIGS"

    # clang and clang++ are nextbsd-cc; the binutils are LLVM's, which handle
    # both targets (the runner's GNU ar/strip are x86-only). gmake is GNU make,
    # the name NextBSD has it under, which tools-make records.
    ln -sf "$ROOT/cross/bin/nextbsd-cc" "$WRAP/clang"
    ln -sf "$ROOT/cross/bin/nextbsd-cc" "$WRAP/clang++"
    for t in ar ranlib nm strip objcopy objdump readelf; do
        ln -sf "$CROSS_BINDIR/llvm-$t" "$WRAP/$t"
    done
    ln -sf "$(command -v make)" "$WRAP/gmake"

    export NEXTBSD_SYSROOT="$SYSROOT" NEXTBSD_TARGET="$CLANG_TARGET"
    export NEXTBSD_CLANG_BINDIR="$CROSS_BINDIR" NEXTBSD_WRAPDIR="$WRAP" NEXTBSD_CPU="$CPU"
    if [ -n "$CCACHE" ]; then
        export NEXTBSD_CCACHE=1
    else
        unset NEXTBSD_CCACHE
    fi

    # GNUstep's absolute paths: /System is the staging root's System, so each
    # library finds the ones already built where GNUstep looks for them.
    mkdir -p "$DESTDIR/System"
    if [ -L /System ]; then
        [ "$(readlink /System)" = "$DESTDIR/System" ] ||
            fail "/System links to $(readlink /System), not $DESTDIR/System"
    elif [ -e /System ]; then
        fail "/System exists on the build host; this must run in a disposable container"
    else
        ln -s "$DESTDIR/System" /System
    fi

    # NextBSD names its libraries libsystem_dispatch and libsystem_blocks;
    # GNUstep links -ldispatch and -lBlocksRuntime. As on a native build,
    # links in /Developer/Link satisfy the linker only (nextbsd-cc points
    # -L/Developer/Link at the sysroot's). Nothing records them at run time.
    mkdir -p "$SYSROOT/Developer/Link"
    ln -sf ../../usr/lib/system/libsystem_dispatch.so "$SYSROOT/Developer/Link/libdispatch.so"
    ln -sf ../../usr/lib/system/libsystem_blocks.so "$SYSROOT/Developer/Link/libBlocksRuntime.so"

    # The build host's plmerge and pl2link: gnustep-make runs them on bundles
    # and apps. /System/Library/Tools comes last, for gnustep-config (a shell
    # script); its programs are NextBSD's and never run here.
    command -v plmerge >/dev/null || fail "no plmerge on the build host (apt-get install gnustep-base-runtime)"
    command -v pl2link >/dev/null || fail "no pl2link on the build host (apt-get install gnustep-base-runtime)"
    export PATH="$WRAP:$PATH:/System/Library/Tools"

    # As build-core-libs-nextbsd-dispatch.sh.
    umask 022
    export CC=clang CXX=clang++ OBJC=clang
    export ac_cv_prog_cc_c23=no
    export GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
    export CONFIG_SITE="$SITE"
    unset CPATH LIBRARY_PATH LD_LIBRARY_PATH

    # pkg-config (pkgconf) sees only the sysroot's .pc files, and GNUstep's
    # own, as GNUstep.sh sets PKG_CONFIG_PATH natively. No
    # PKG_CONFIG_SYSROOT_DIR: the flags stay the native ones (-I/usr/include/
    # icucore ...), which nextbsd-cc points into the sysroot, so the
    # gnustep-make files GNUstep installs (base.make ...) match a native
    # build's instead of naming this build host's paths.
    export PKG_CONFIG_LIBDIR="$SYSROOT/usr/libdata/pkgconfig:$SYSROOT/usr/X11/lib/pkgconfig"
    export PKG_CONFIG_PATH="/System/Library/Libraries/pkgconfig"
    unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG

    [ -f "$SITE" ] || fail "no $SITE"
    "$WRAP/clang" --version | head -1
    note "host $GS_HOST (clang --target=$CLANG_TARGET), build $BUILD_TRIPLE, $JOBS jobs, ccache ${CCACHE:-off}"
    note "plmerge: $(command -v plmerge), pl2link: $(command -v pl2link)"
}

# GNUstep's environment once tools-make is installed. GNUstep.sh isn't
# sourced: it would put /System/Library/Tools (NextBSD programs) first on
# PATH and in LD_LIBRARY_PATH. gnustep-make reads GNUstep.conf itself.
gnustep_env() {
    export GNUSTEP_MAKEFILES=/System/Library/Makefiles
    export GNUSTEP_CONFIG_FILE=/System/Library/Preferences/GNUstep.conf
}

# ---- sources -----------------------------------------------------------------

# lock_field <name> <url|ref>
lock_field() {
    local col
    case "$2" in url) col=2 ;; ref) col=3 ;; *) fail "lock_field $2" ;; esac
    awk -v n="$1" -v c="$col" '$1 == n { print $c; found=1 } END { exit !found }' "$ROOT/sources.lock" ||
        fail "$1 is not in sources.lock"
}

# fetch <name>: a fresh shallow clone of the library's ref; sets S.
fetch() {
    local name="$1" url ref
    url=$(lock_field "$name" url)
    ref=$(lock_field "$name" ref)
    S="$SRC/$name"
    if [ -e "$S" ]; then
        # A rerun in the same tree: build in a new directory, never delete.
        S="$SRC/$name.$(date +%s)"
    fi
    git clone -q --depth 1 --branch "$ref" "$url" "$S"
    printf '%s\t%s\t%s\t%s\n' "$name" "$url" "$ref" "$(git -C "$S" rev-parse HEAD)" >> "$BUILD/BUILD-INFO-$T"
    note "$name $ref $(git -C "$S" rev-parse --short HEAD)"
}

# keep_configs <name> <files...>: copy what configure generated, for comparison
# with a native build.
keep_configs() {
    local name="$1" f
    shift
    mkdir -p "$CONFIGS/$name"
    for f in "$@"; do
        [ -e "$S/$f" ] && cp "$S/$f" "$CONFIGS/$name/$(echo "$f" | tr / _)"
    done
    return 0
}

# ---- the libraries -----------------------------------------------------------

build_tools_make() {
    fetch tools-make
    cd "$S"
    # As natively: libobjc_LIBS and --with-objc-lib-flag keep -lobjc out of
    # configure's link tests, since libobjc2 isn't built yet.
    ./configure \
        --build="$BUILD_TRIPLE" --host="$GS_HOST" \
        --with-config-file=/System/Library/Preferences/GNUstep.conf \
        --with-layout=gershwin \
        --with-library-combo=ng-gnu-gnu \
        --with-objc-lib-flag=" " \
        LDFLAGS="-L/System/Library/Libraries" \
        CPPFLAGS="-I/System/Library/Headers" \
        libobjc_LIBS=" "
    keep_configs tools-make config.log config.make config-noarch.make
    make
    make install DESTDIR="$DESTDIR"
    gnustep_env
}

build_libobjc2() {
    fetch libobjc2
    # As natively, with the cross toolchain file. The blocks runtime is the
    # base system's libsystem_blocks.
    cmake -S "$S" -B "$S/Build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/cross/cmake/nextbsd.cmake" \
        -DGNUSTEP_INSTALL_TYPE=SYSTEM \
        -DCMAKE_BUILD_TYPE=Release \
        -DEMBEDDED_BLOCKS_RUNTIME=OFF \
        -DBlocksRuntime_INCLUDE_DIR="$SYSROOT/usr/include" \
        -DBlocksRuntime_LIBRARIES="$SYSROOT/usr/lib/system/libsystem_blocks.so"
    keep_configs libobjc2 Build/CMakeCache.txt Build/objc/objc-config.h
    cmake --build "$S/Build" -j "$JOBS"
    DESTDIR="$DESTDIR" cmake --install "$S/Build"
}

# make_install [make variables...]: as natively, a parallel build then
# install, into the staging root.
make_install() {
    make -j"$JOBS" "$@"
    make install DESTDIR="$DESTDIR"
}

build_libs_base() {
    fetch libs-base
    cd "$S"
    # As natively (-L/usr/lib/system finds libdns_sd, for Bonjour), with the
    # site file as the cross-compilation answers. --with-dispatch-include
    # isn't given: natively it adds -I/usr/include, which the compiler
    # searches anyway.
    ./configure \
        --build="$BUILD_TRIPLE" --host="$GS_HOST" \
        --with-cross-compilation-info="$SITE" \
        --with-dispatch-library=/Developer/Link \
        --with-zeroconf-api=mdns \
        LDFLAGS="-L/System/Library/Libraries -L/Developer/Link -L/usr/lib/system"
    keep_configs libs-base config.log config.mak base.make \
        Headers/GNUstepBase/config.h Headers/GNUstepBase/GSConfig.h
    make_install
}

# The ICU flags, as `pkg-config --cflags icu-i18n` gives them natively.
icu_cflags() { pkg-config --cflags icu-i18n; }

build_libs_corebase() {
    fetch libs-corebase
    cd "$S"
    ./configure \
        --build="$BUILD_TRIPLE" --host="$GS_HOST" \
        CPPFLAGS="-I/System/Library/Headers" \
        LDFLAGS="-L/System/Library/Libraries -L/Developer/Link"
    keep_configs libs-corebase config.log Source/config.h Headers/CoreFoundation/CFBase.h
    # configure doesn't pass the ICU header path on to the compile.
    make_install CPPFLAGS="-I/System/Library/Headers $(icu_cflags)"
}

build_libs_gui() {
    fetch libs-gui
    cd "$S"
    ./configure --build="$BUILD_TRIPLE" --host="$GS_HOST" CPPFLAGS="$(icu_cflags)"
    keep_configs libs-gui config.log config.make gui.make Headers/Additions/GNUstepGUI/config.h
    make_install
}

build_libs_back() {
    fetch libs-back
    cd "$S"
    fonts=no ./configure --build="$BUILD_TRIPLE" --host="$GS_HOST"
    keep_configs libs-back config.log config.make back.make config.h
    fonts=no make_install
}

build_libs_av() {
    fetch libs-av
    cd "$S"
    make_install
}

# ---- checks ------------------------------------------------------------------

# Every ELF file staged is for the target, and records no build-host path, no
# /Developer/Link and no RPATH/RUNPATH outside /System and /usr; every
# DT_NEEDED is a library the target has (sysroot or staged GNUstep). Text
# files (makefiles, .pc, .cmake, scripts) name no build-host path.
check_stage() {
    comp "checking $DESTDIR"
    local readelf="$CROSS_BINDIR/llvm-readelf" want f dyn n d found bad=0 count=0
    case "$T" in amd64) want='X86-64' ;; arm64) want='AArch64' ;; esac
    while IFS= read -r -d '' f; do
        head -c 4 "$f" | grep -q 'ELF' || continue
        count=$((count + 1))
        "$readelf" -h "$f" | grep -q "Machine:.*$want" || { echo "  not $want: $f"; bad=1; continue; }
        dyn=$("$readelf" -d "$f" 2>/dev/null || true)
        if printf '%s\n' "$dyn" | grep -E '\((RPATH|RUNPATH)\)' | grep -vE '\[(/System|/usr)[^]]*\]$' | grep -q .; then
            echo "  RPATH/RUNPATH outside /System and /usr: $f"
            printf '%s\n' "$dyn" | grep -E '\((RPATH|RUNPATH)\)'
            bad=1
        fi
        for n in $(printf '%s\n' "$dyn" | sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p'); do
            found=
            for d in /lib /usr/lib /usr/lib/system /usr/X11/lib; do
                [ -e "$SYSROOT$d/$n" ] && { found=1; break; }
            done
            [ -n "$found" ] || [ -n "$(find "$DESTDIR/System" -name "$n" -print -quit)" ] ||
                { echo "  $f: DT_NEEDED $n is in neither the sysroot nor the staged GNUstep"; bad=1; }
        done
    done < <(find "$DESTDIR" -type f -print0)
    note "$count ELF files are $want"
    if grep -rIl -e "$SYSROOT" -e "$BUILD" -e "$WRAP" "$DESTDIR" 2>/dev/null | grep -q .; then
        echo "  files naming a build-host path:"
        grep -rIl -e "$SYSROOT" -e "$BUILD" -e "$WRAP" "$DESTDIR" | sed 's/^/    /'
        bad=1
    fi
    [ "$bad" = 0 ] || fail "the staged GNUstep has problems (above)"
    note "no build-host paths; every DT_NEEDED resolves; no stray RPATH"
}

# ---- main --------------------------------------------------------------------

LIBS="tools-make libobjc2 libs-base libs-corebase libs-gui libs-back libs-av"
[ $# -gt 0 ] && LIBS="$*"

setup
[ -f "$DESTDIR/System/Library/Makefiles/common.make" ] && gnustep_env
total0=$(date +%s)
for lib in $LIBS; do
    comp "$lib"
    t0=$(date +%s)
    ( "build_${lib//-/_}" )
    [ "$lib" = tools-make ] && gnustep_env
    t1=$(date +%s)
    printf '%s\t%s\t%d\n' "$T" "$lib" "$((t1 - t0))" >> "$TIMES"
    note "$lib built in $((t1 - t0))s"
done
total1=$(date +%s)
printf '%s\t%s\t%d\n' "$T" total "$((total1 - total0))" >> "$TIMES"
check_stage
comp "done in $((total1 - total0))s"
column -t "$TIMES" 2>/dev/null || cat "$TIMES"
