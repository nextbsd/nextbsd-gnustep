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

## License

BSD 2-Clause. See [LICENSE](LICENSE). This covers this repository's build
scripts; each GNUstep library keeps its own license.
