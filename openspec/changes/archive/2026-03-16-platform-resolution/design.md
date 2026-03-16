## Context

`ModuleContext.loadConfiguration` currently sorts `platforms` entries, then merges every entry without checking whether the selector applies to the current host. Alma-Go already has a defined model here: it builds a runtime identifier from OS, optional Linux distro, and architecture, then applies matching platform prefixes. `alma-zig` should adopt that same hierarchy so module configuration behaves consistently across implementations.

## Goals / Non-Goals

**Goals:**
- Match Alma-Go platform hierarchy and selector semantics.
- Keep Alma-Go OS vocabulary: `windows`, `macos`, `freebsd`, `linux`.
- Keep Alma-Go Linux distro behavior from `/etc/os-release`.
- Use Zig architecture spellings in the final identifier and selectors.
- Apply deterministic merge order from least to most specific matching selector.
- Add tests for Linux distro-aware and non-Linux cases.

**Non-Goals:**
- Redesign module source path resolution in `src/link.zig`.
- Introduce a new cross-platform selector DSL beyond Alma-Go compatibility.
- Change merge semantics beyond adding selector applicability and deterministic ordering.

## Decisions

- Platform resolution is host-side, not build-target-side. `alma link` performs host actions such as reading local files, creating symlinks, and running local commands, so the active platform must reflect the machine running `alma`.
- Runtime identifiers will follow Alma-Go hierarchy with Zig arch spellings:
  - `windows-<arch>`
  - `macos-<arch>`
  - `freebsd-<arch>`
  - `linux-<arch>` when distro is unavailable
  - `linux-<distro>-<arch>` when `/etc/os-release` exposes `ID`
  - `unknown` if no supported OS can be identified
- Selector vocabulary will be the valid ancestors of those identifiers plus `default`:
  - `default`
  - `windows`, `windows-<arch>`
  - `macos`, `macos-<arch>`
  - `freebsd`, `freebsd-<arch>`
  - `linux`, `linux-<arch>`, `linux-<distro>`, `linux-<distro>-<arch>`
  - `unknown`
- Matching will use segment-aware prefix logic, not raw string prefix logic. A selector matches when it is exactly one of the identifier's ancestor paths split on `-`. This preserves Alma-Go hierarchy while avoiding accidental substring matches such as `lin` or `linux-u`.
- Merge order will be deterministic by specificity: `default` first, then matching ancestors from shortest to longest. For example, on `linux-ubuntu-x86_64`, the order is `default -> linux -> linux-ubuntu -> linux-ubuntu-x86_64`.
- Existing field merge semantics stay in place: scalar fields are overridden by later matches; `links` continue to accumulate.
- Invalid selectors will fail configuration loading. Unknown OS names, malformed segment counts, or impossible shapes such as `x86_64-linux` are configuration errors, not ignored input.
- Tests should primarily target selector parsing, matching, and configuration merging in `src/module.zig`, with small focused fixtures rather than full command integration.

## Risks / Trade-offs

- [Distro behavior depends on `/etc/os-release`] → Treat distro as optional, matching Alma-Go fallback to `linux-<arch>` when distro cannot be discovered.
- [Segment-aware matching is not bug-for-bug `StartsWith`] → Preserve the same hierarchy and intended matches while deliberately rejecting accidental substring prefixes.
- [Strict compatibility constrains future selector design] → Keep this change narrow; evolve only through later explicit changes.
- [Validation may reject ad-hoc existing config names] → Make supported selector forms explicit in errors and docs.

## Migration Plan

- Add a helper that computes the runtime platform identifier using Alma-Go OS names, Linux distro lookup, and Zig arch names.
- Add selector validation and segment-aware ancestor matching in `src/module.zig`.
- Merge only matching selectors in deterministic specificity order.
- Add tests for `linux`, `linux-<arch>`, `linux-<distro>`, `linux-<distro>-<arch>`, non-Linux OS selectors, mismatch exclusion, and invalid selector errors.
- No data migration required; compatibility is achieved by using Alma-Go-style selector names.

## Open Questions

- None. The compatibility target is now explicit.
