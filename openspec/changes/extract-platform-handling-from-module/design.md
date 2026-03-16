## Context

`src/module.zig` currently mixes YAML parsing, configuration merging, platform identifier detection, platform selector parsing, selector matching, and validation. The recent `platform-resolution` change made that file even more platform-heavy. The requested change is a structural refactor: keep the same behavior, but move platform responsibilities behind a dedicated module boundary.

## Goals / Non-Goals

**Goals:**
- Isolate platform-specific logic from module configuration loading.
- Keep current runtime platform detection, selector parsing, matching, precedence, and error behavior unchanged.
- Make platform logic reusable and testable without going through `ModuleContext` or YAML loading.
- Leave `src/module.zig` focused on reading and merging module configuration.

**Non-Goals:**
- Changing selector syntax or precedence.
- Changing link-time behavior in `src/link.zig` beyond import/wiring updates.
- Redesigning module source path resolution.
- Introducing new platform semantics beyond the existing Alma-Go-compatible model.

## Decisions

### Extract a dedicated platform module
Create a new source file for platform responsibilities, likely exposing a runtime platform identifier type plus selector parsing/matching helpers. `src/module.zig` will import this module and use its public API instead of owning private platform internals.

Alternative considered: keep the code in `src/module.zig` and only split tests. Rejected because reuse and ownership remain unclear.

### Preserve current public behavior exactly
The extracted module will carry over the same supported OS names, Linux distro handling, `unknown` handling, selector validation, match rules, and specificity ordering. This is a refactor, not a behavior change.

Alternative considered: simplify the model while moving it. Rejected because the active archived spec already defines current behavior and this change is about separation, not semantics.

### Move platform-focused tests with the extracted code
Tests covering identifier parsing, detection formatting, selector parsing, and selector matching should live with the new platform module. Module-loading tests should stay in `src/module.zig` and focus on YAML parsing plus merge application.

Alternative considered: leave every test in `src/module.zig`. Rejected because it preserves the same coupling the refactor is trying to remove.

### Keep module configuration merge orchestration in `src/module.zig`
`src/module.zig` should still decide how parsed YAML platform entries are collected, sorted, and merged into `ModuleConfiguration`. The new platform module should answer platform questions, not take over module configuration assembly.

Alternative considered: move the full platform-entry filtering pipeline out of `src/module.zig`. Rejected for now to keep the extraction focused and low-risk.

## Risks / Trade-offs

- [Refactor drift] → Rewritten boundaries could subtly change error behavior or matching semantics. Mitigation: preserve tests and add coverage at the extracted-module boundary.
- [API too narrow] → `src/module.zig` may still need private details and leak coupling back in. Mitigation: expose small focused helpers for parse/detect/match/specificity rather than many raw internals.
- [API too broad] → Over-designing a reusable platform abstraction may add unnecessary complexity. Mitigation: extract only what current call sites and tests need.
- [Test churn] → Moving tests can briefly reduce confidence if coverage gaps appear. Mitigation: keep scenario parity and run the full test suite after extraction.

## Migration Plan

1. Add the new platform module with extracted types and helpers.
2. Update `src/module.zig` to import and use the new module.
3. Move/split tests so platform tests live with the platform module and module tests stay focused on configuration loading.
4. Run tests and confirm no behavior changes.

No user migration or rollout steps are needed because behavior is intended to remain unchanged.

## Open Questions

- Exact file name and surface area of the extracted module (`platform.zig` seems most likely).
- Whether `unknown` selector support should remain publicly exposed or stay an implementation detail carried over as-is.