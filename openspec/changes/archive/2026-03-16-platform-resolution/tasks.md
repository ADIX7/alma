## 1. Runtime identifier and selector model

- [x] 1.1 Add host platform detection helpers that produce Alma-Go-compatible identifiers with OS names `windows`, `macos`, `freebsd`, `linux`, optional Linux distro, and Zig arch spellings
- [x] 1.2 Define and validate the supported selector shapes: `default`, `unknown`, `<os>`, `<os>-<arch>`, `linux-<distro>`, and `linux-<distro>-<arch>`
- [x] 1.3 Implement segment-aware ancestor matching so selectors match only valid hierarchy prefixes of the active platform identifier

## 2. Configuration merge behavior

- [x] 2.1 Filter platform entries in `src/module.zig` to only `default` and matching Alma-Go-compatible selectors
- [x] 2.2 Merge matching entries deterministically from least specific to most specific selector
- [x] 2.3 Preserve existing field merge semantics while applying the new selector filtering and ordering
- [x] 2.4 Return a clear invalid-platform-selector error for malformed or unsupported selector names

## 3. Verification

- [x] 3.1 Add unit tests for Windows/macOS/FreeBSD-style selector matching (`<os>`, `<os>-<arch>`)
- [x] 3.2 Add unit tests for Linux matching with and without discovered distro (`linux`, `linux-<arch>`, `linux-<distro>`, `linux-<distro>-<arch>`)
- [x] 3.3 Add unit tests proving segment-aware matching rejects non-ancestor prefixes such as `linux-x86_64` for `linux-ubuntu-x86_64`
- [x] 3.4 Add unit tests that malformed selectors such as `darwin` and `x86_64-linux` fail with the expected error
- [x] 3.5 Run the project test command and fix any regressions introduced by the change
