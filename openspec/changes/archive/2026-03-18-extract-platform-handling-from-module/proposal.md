## Why

`src/module.zig` currently owns both module configuration loading and all platform parsing, detection, selector matching, and validation logic. That mixes two concerns in one file, makes the platform logic harder to reuse, and makes future platform-related changes riskier than they need to be.

## What Changes

- Extract platform identifier detection, parsing, selector parsing, matching, and related helpers from `src/module.zig` into a dedicated platform-focused module.
- Update module configuration loading to depend on the extracted platform module instead of embedding the logic locally.
- Preserve current platform-resolution behavior, errors, and precedence while improving separation of concerns and test organization.
- Move or split tests so platform behavior is verified alongside the new platform module.

## Capabilities

### New Capabilities
- `platform-handling`: Provide a dedicated platform subsystem responsible for runtime platform identification and platform selector evaluation used by module loading.

### Modified Capabilities
- `platform-resolution`: Module configuration loading uses the shared platform-handling subsystem while preserving existing selector semantics and merge behavior.

## Impact

- Affected code: `src/module.zig`, new extracted platform file(s), import sites such as `src/link.zig`, and tests.
- User-visible behavior: no intended behavior change; `alma link` should keep resolving platform blocks exactly as it does now.
- Risk: medium refactor risk because parsing and matching logic is being moved across module boundaries.