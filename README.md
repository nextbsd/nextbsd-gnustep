# nextbsd-gnustep

Cross-builds NextBSD's GNUstep core for amd64 and arm64 in CI:
[tools-make](https://github.com/nextbsd/tools-make),
[libobjc2](https://github.com/nextbsd/libobjc2),
[libs-base](https://github.com/nextbsd/libs-base),
[libs-corebase](https://github.com/nextbsd/libs-corebase),
[libs-gui](https://github.com/nextbsd/libs-gui),
[libs-back](https://github.com/nextbsd/libs-back) and
[libs-av](https://github.com/nextbsd/libs-av), all from NextBSD's forks.

It publishes, for each architecture:

- **the build**, which [nextbsd-pkg](https://github.com/nextbsd/nextbsd-pkg)
  packages as `NextBSD-gnustep`;
- **a GNUstep SDK**: GNUstep's headers, libraries and gnustep-make
  configuration over the NextBSD userland, which
  [nextbsd-desktop](https://github.com/nextbsd/nextbsd-desktop) and WebKit
  cross-compile against.

It builds on Ubuntu with the same FreeBSD cross-toolchain container as the
kernel and userland. GitHub's arm64 runners have no KVM, so building inside an
emulated NextBSD VM would be too slow. Configure checks that need to run a
program on the target are answered from a native NextBSD build, per
architecture, instead of being run.

Planned in [nextbsd/nextbsd#674](https://github.com/nextbsd/nextbsd/issues/674)
and [#673](https://github.com/nextbsd/nextbsd/issues/673) (epic
[E47](https://github.com/nextbsd/nextbsd/issues/671)). Libraries come from
NextBSD's base system for libdispatch and the blocks runtime, and from
[NextBSD-gnustep-support](https://github.com/nextbsd/nextbsd-gnustep-support)
for the rest.

## How it builds

`build-gnustep.sh` runs in the `nextbsd-toolchain` container (clang/lld 19)
for one architecture (`T=amd64` or `T=arm64`) and does what
pkgdemon/nextbsd-gnustep's `build-core-libs-nextbsd-dispatch.sh` does on a
machine, into a staging root (`DESTDIR`, `/stage` in CI): the gershwin
filesystem layout, the SYSTEM domain, the ng-gnu-gnu library combo, ICU,
Bonjour through mDNSResponder, libs-back's X11 server with cairo, and
libdispatch and the blocks runtime from NextBSD's base system, linked through
`-ldispatch`/`-lBlocksRuntime` links in `/Developer/Link`. The staged install
ships those two links too, because the installed makefiles link every app with
`-L/Developer/Link -ldispatch -lBlocksRuntime`; without them, building an app
on NextBSD (Software.app, or `gmake` by hand) fails with `unable to find
library -ldispatch`.

| File | What it is |
|---|---|
| `sources.lock` | the fork and branch of each library, in build order |
| `build-gnustep.sh` | the cross build, with per-library times and checks of the result |
| `cross/nextbsd-<arch>.site` | `CONFIG_SITE`: the answers to configure checks that would run a NextBSD program, from a native build, each marked verified or derived |
| `cross/bin/nextbsd-cc` | `clang`/`clang++` for the target (links to it go first on `PATH`) |
| `cross/cmake/nextbsd.cmake` | the CMake toolchain file (libobjc2) |
| `make-sdk.sh`, `sdk/env.sh.in` | the GNUstep SDK |
| `test-sdk-app.sh` | cross-builds apps-terminal with the SDK alone |

Nothing built for NextBSD runs during the build:

- every configure runs with `--host=<arch>-nextbsd-freebsd` and
  `CONFIG_SITE=cross/nextbsd-<arch>.site`; libs-base also reads that file as its
  `--with-cross-compilation-info`;
- `CC` is plain `clang`, as natively, so the installed gnustep-make
  configuration says `clang`. `nextbsd-cc` runs the image's clang with the
  target and the sysroot, and points the native paths GNUstep records
  (`-I/usr/include`, `-L/usr/lib/system`, `-L/Developer/Link`, the `.pc` files'
  flags) into the sysroot, so nothing from the build host's `/usr` is used;
- `/System` in the container is a link to `$DESTDIR/System`, so each library
  finds the ones built before it where GNUstep's configure scripts and
  makefiles look;
- gnustep-make's `plmerge` and `pl2link` are the build host's
  (`gnustep-base-runtime`); libs-gui skips `make_services` when cross-compiling.

The sysroot is the `continuous` artifacts of nextbsd-freebsd-compat,
nextbsd-userland, nextbsd-displayserver-support, nextbsd-xlibs,
nextbsd-gnustep-support, nextbsd-printing-support (CUPS) and nextbsd-mesa
(libGL), extracted in that order.

```
T=arm64 SYSROOT=/path/to/sysroot DESTDIR=/stage ./build-gnustep.sh
T=arm64 SYSROOT=/path/to/sysroot DESTDIR=/stage ./make-sdk.sh
```

## The GNUstep SDK

`nextbsd-gnustep-sdk-<arch>.tar.gz` holds the NextBSD sysroot's headers and
libraries, the staged GNUstep (`/System`, gnustep-make's configuration
included), `bin/clang` and `bin/clang++`, the arch's site file and CMake
toolchain file, and `env.sh`. In the toolchain container:

```
apt-get install -y gnustep-base-runtime          # plmerge, pl2link
tar -C /opt -xzf nextbsd-gnustep-sdk-arm64.tar.gz
export NEXTBSD_SDK=/opt/nextbsd-gnustep-sdk-arm64
. $NEXTBSD_SDK/env.sh                            # links /System to the SDK's
cd MyApp && make && make install DESTDIR=/tmp/stage
```

Autotools projects also get `--host=$NEXTBSD_HOST`; CMake projects
`-DCMAKE_TOOLCHAIN_FILE=$NEXTBSD_SDK/share/nextbsd-gnustep/nextbsd.cmake` with
`NEXTBSD_WRAPDIR=$NEXTBSD_SDK/bin`, `NEXTBSD_SYSROOT` and `NEXTBSD_CPU` set.

## License

BSD 2-Clause. See [LICENSE](LICENSE). This covers this repository's build
scripts; each GNUstep library keeps its own license.
