## Why

`alma-zig` currently merges every platform block in `.alma.yml` without checking whether the block applies to the current machine. That is already wrong on its own, but it also diverges from Alma-Go, which resolves configuration through a platform hierarchy and only applies matching prefixes. If `alma-zig` is meant to be compatible, platform selection must follow the same model.

## What Changes

- Make platform resolution in `alma-zig` follow the same hierarchy as Alma-Go: `default`, OS, optional Linux distro, and architecture.
- Keep Alma-Go OS vocabulary: `windows`, `macos`, `freebsd`, `linux`.
- Keep Alma-Go Linux distro behavior by reading `/etc/os-release` and using the distro `ID` when available.
- Use Zig architecture spellings in the platform identifier and selectors.
- Apply segment-aware prefix matching so only ancestor selectors in the Alma-Go hierarchy match.
- Merge matching entries deterministically from least specific to most specific.
- Add tests for Linux distro-aware matching, non-Linux matching, mismatch cases, and invalid selectors.

## Capabilities

### New Capabilities
- `platform-resolution`: Resolve module configuration with Alma-Go-compatible platform hierarchy, matching, and precedence.

### Modified Capabilities

## Impact

- Affected code: `src/module.zig`, likely `src/link.zig`, and new/updated tests.
- User-visible behavior: `alma link` will apply only matching platform blocks and will align with Alma-Go selector semantics.
- Compatibility impact: Alma-Go-style config names become the supported contract for `alma-zig`.
