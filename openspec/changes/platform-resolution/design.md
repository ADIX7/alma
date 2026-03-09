## Context

`ModuleContext.loadConfiguration` currently sorts `platforms` entries, then merges every entry without checking whether the selector applies to the current platform. That makes platform-specific `links`, `target`, `install`, and `configure` fields leak across environments. The code already hints at intended precedence (`default` first, longer selectors later), so the missing piece is selector evaluation and validation.

## Goals / Non-Goals

**Goals:**
- Define supported platform selectors for `.alma.yml`.
- Apply only `default` and selectors matching the current build/runtime platform.
- Preserve deterministic merge behavior so specific matches override generic ones.
- Add tests for matching, precedence, and invalid selectors.

**Non-Goals:**
- Redesign module source path resolution in `src/link.zig`.
- Add user-defined boolean expressions or glob matching for platforms.
- Change merge semantics beyond platform applicability.

## Decisions

- Supported selectors will be `default`, `<os>`, and `<arch>-<os>` using Zig tag names (for example `linux`, `darwin`, `x86_64-linux`, `aarch64-darwin`). This is simple, deterministic, and matches the existing idea that longer selectors are more specific.
- Configuration loading will derive the current selector set once, then keep only entries that are either `default` or exact matches. Alternatives considered: prefix matching and arbitrary triples. Rejected because they are harder to validate and document.
- Merge order stays `default` first, then matching selectors from least to most specific, so generic values provide defaults and more specific values override later. Existing append behavior for `links` stays unchanged.
- Unsupported selectors will return an error during configuration load instead of being ignored. Alternative considered: warn and skip. Rejected because silent skips hide broken configuration.
- Tests should target the configuration loader with small inline YAML fixtures rather than full `link` command integration, because the behavior change is centered in `src/module.zig`.

## Risks / Trade-offs

- [Selector syntax too narrow] → Start with exact selectors only; extend later through a new change if needed.
- [Validation may reject existing informal values] → Document accepted forms in the spec and provide clear error messages.
- [Runtime platform vs compiled target ambiguity] → Use a single definition consistently in code and tests; avoid mixing host probing with config resolution.

## Migration Plan

- Implement selector parsing and matching in `src/module.zig`.
- Add tests covering default-only, OS match, arch+OS precedence, mismatch exclusion, and invalid selector failure.
- No data migration required; existing configs using supported selector names continue to work.
- Rollback is code-only: revert the change if matching semantics break existing modules.

## Open Questions

- None for proposal stage; exact selector forms are intentionally constrained to keep implementation small.
