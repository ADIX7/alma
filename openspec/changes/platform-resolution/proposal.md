## Why

Module configuration currently merges every platform block after sorting by platform name length, but it never checks whether a block actually matches the current runtime or target platform. That can apply Linux-, macOS-, or Windows-specific links and commands on the wrong machine, making `alma link` unreliable as soon as a module defines more than `default` behavior.

## What Changes

- Add explicit platform matching when loading `.alma.yml` so only `default` and matching platform entries are applied.
- Define deterministic precedence between `default` and more specific platform selectors when multiple entries match.
- Reject or surface unsupported platform selectors instead of silently applying them.
- Cover platform resolution with tests for default-only, exact-match, and mismatch cases.

## Capabilities

### New Capabilities
- `platform-resolution`: Resolve module configuration from platform-scoped entries using the current environment with deterministic override rules.

### Modified Capabilities

## Impact

- Affected code: `src/module.zig`, likely `src/link.zig`, and new/updated tests.
- User-visible behavior: `alma link` will stop applying non-matching platform configuration.
- Risk: platform selector semantics become part of the supported config contract and must stay stable.
