## Context

`alma` already resolves a module's merged configuration and exposes the resolved `install` string, but normal CLI flows never execute it. The current `link` flow only reports install/configure commands as skipped, and command parsing only understands `link` plus help. Adding `alma install` crosses CLI parsing, module resolution, and process execution, so a small design keeps the command model and side-effect boundary explicit.

## Goals / Non-Goals

**Goals:**
- Add a dedicated `alma install [-d] [repo] <module>` CLI command.
- Reuse existing module configuration loading so platform-specific `install` resolution stays consistent.
- Execute the resolved install command and surface success/failure clearly.
- When `-d` is supplied, log the resolved install command and skip execution.
- Return a stable user-facing result when no install command is configured.
- Add tests for parsing and install execution behavior.

**Non-Goals:**
- Change module configuration schema or merge semantics.
- Implement `configure` as a separate command in this change.
- Redesign repo/module source resolution beyond what the install path needs.
- Change `alma link` behavior beyond any helper extraction needed to share module loading.

## Decisions

### Add a distinct install command payload
The command union should gain an `install` variant with payload fields matching the existing module-targeting shape (`repo`, `module`). This keeps parsing explicit and lets `main` dispatch install independently from link.

Alternative considered: treat install as a flag on `link`. Rejected because install is a different user action with different side effects.

### Reuse module resolution before execution
The install flow should load `.alma.yml` through the same `ModuleContext.loadConfiguration` path used elsewhere, then read the resolved `install` field from `ModuleConfiguration`. That preserves existing platform matching and keeps install behavior aligned with the rest of the app.

Alternative considered: parse only the raw `install` field separately. Rejected because it would bypass platform-aware merge behavior.

### Execute install commands through a shell boundary
Because module config stores `install` as a single command string, the implementation should execute it through a shell command invocation rather than trying to split argv itself. This keeps authored module commands compatible with shell syntax already implied by the config format.

For the first implementation, shell selection should match current Alma-Go behavior:
- Linux: `sh -c <command>`
- Windows: `pwsh -c <command>`
- macOS, FreeBSD, and other platforms: reject execution as unsupported instead of guessing a fallback shell

When install runs in dry-run mode (`-d`), it should stop at logging the resolved install command and skip process creation entirely.

Alternative considered: whitespace-split and exec directly. Rejected because quoted args, env assignments, pipes, and compound shell commands would break.

### Treat missing install as a handled no-op outcome
If the resolved module configuration has no `install` command, `alma install` should report that nothing is configured and exit without attempting process execution. That gives users a deterministic result instead of an obscure null-path failure.

Alternative considered: silently succeed. Rejected because users need to know why nothing ran.

### Keep command execution isolated from link-specific reporting
Any process-spawning helper extracted for install should be named around module-command execution rather than embedded in `link.zig`. That leaves room for future `configure` support without coupling unrelated commands to link semantics.

Alternative considered: implement install logic inside `link.zig`. Rejected because the new command is not part of the link flow.

## Risks / Trade-offs

- [Shell execution semantics vary by platform] → Use one documented shell strategy for the first implementation and cover the expected environment in tests.
- [Repo/module resolution duplication] → Extract only the shared module-loading or source-path logic needed by both commands.
- [Child-process failures become user-visible] → Propagate non-zero exit or spawn failures with clear CLI error output.
- [Future configure support may want the same helper] → Keep helper names generic around module command execution.

## Migration Plan

1. Extend the command model and parser with `install` support.
2. Add a dedicated install handler that resolves module configuration and checks for `install`.
3. Execute the resolved install command through a child-process helper, with `-d` logging only.
4. Update help text and add parser/handler tests.
5. Run the relevant Zig test suite.

No data migration needed. Existing commands remain unchanged.

## Open Questions

- Whether install should inherit the child process stdio directly or capture output for formatted reporting can stay implementation-defined if failures remain visible.
- Repo path handling is currently limited elsewhere too; this change can follow current behavior unless implementation exposes a sharper inconsistency.
