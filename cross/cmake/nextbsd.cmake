# CMake toolchain file for cross-building libobjc2 for NextBSD (amd64 or
# arm64). build-gnustep.sh passes it with -DCMAKE_TOOLCHAIN_FILE.
#
# The compilers are the clang/clang++ links to cross/bin/nextbsd-cc that
# build-gnustep.sh puts first on PATH (NEXTBSD_WRAPDIR); nextbsd-cc adds the
# target, the sysroot and lld. CMAKE_SYSTEM_NAME is FreeBSD: NextBSD's base is
# FreeBSD's libc and ABI, so upstream's FreeBSD code paths apply.
#
# Environment (exported by build-gnustep.sh):
#   NEXTBSD_WRAPDIR    directory holding the clang and clang++ links
#   NEXTBSD_SYSROOT    the NextBSD sysroot
#   NEXTBSD_CPU        x86_64 or aarch64

set(CMAKE_SYSTEM_NAME      FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR "$ENV{NEXTBSD_CPU}")

set(_wrap "$ENV{NEXTBSD_WRAPDIR}")
set(CMAKE_C_COMPILER      "${_wrap}/clang")
set(CMAKE_CXX_COMPILER    "${_wrap}/clang++")
set(CMAKE_ASM_COMPILER    "${_wrap}/clang")
set(CMAKE_OBJC_COMPILER   "${_wrap}/clang")
set(CMAKE_OBJCXX_COMPILER "${_wrap}/clang++")
set(CMAKE_AR      "${_wrap}/ar"      CACHE FILEPATH "")
set(CMAKE_RANLIB  "${_wrap}/ranlib"  CACHE FILEPATH "")
set(CMAKE_NM      "${_wrap}/nm"      CACHE FILEPATH "")
set(CMAKE_STRIP   "${_wrap}/strip"   CACHE FILEPATH "")
set(CMAKE_OBJCOPY "${_wrap}/objcopy" CACHE FILEPATH "")
set(CMAKE_READELF "${_wrap}/readelf" CACHE FILEPATH "")

set(CMAKE_SYSROOT        "$ENV{NEXTBSD_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "$ENV{NEXTBSD_SYSROOT}")

# Programs (gnustep-config) from the build host's PATH; libraries, headers and
# packages only from the sysroot.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
