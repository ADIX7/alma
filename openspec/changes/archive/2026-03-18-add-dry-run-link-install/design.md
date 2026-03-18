## Context

`alma link` currently parses only repo/module positional args and hands them to `linkHandler`. The handler resolves module config and prints planned symlink creation, but the side-effect boundary is implicit and not yet modeled as an execution mode. Adding dry-run is small in scope but crosses CLI parsing, command payload shape, and link execution behavior.

## Goals / Non-Goals

**Goals:**
- Add a dry-run flag to `alma link` without breaking existing positional argument parsing.
- Carry dry-run explicitly from parsed CLI args into the link handler.
- Ensure dry-run never creates symlinks and never runs module-defined commands once command execution is added.
- Keep dry-run output aligned with the real operations so it is trustworthy for previewing side effects.
- Add focused tests for parsing and no-side-effect behavior.

**Non-Goals:**
- Implement a separate `alma install` command.
- Redesign module source path resolution.
- Implement actual install/configure command execution beyond dry-run-aware plumbing.
- Change module configuration semantics.

## Decisions

### Add dry-run to the link command payload
`LinkPayload` should gain a boolean dry-run field so the mode is explicit after parsing and easy to thread into handlers and tests.

Alternative considered: inspect raw argv in `linkHandler`. Rejected because it hides command state outside the parsed command model.

### Parse `-d` as a link subcommand flag before positional args
`parseLinkArgs` should accept `-d` while preserving the current `[repo] <module>` positional contract. Flag parsing stays local to the link subcommand, so help and future subcommands can evolve independently.

Alternative considered: only support a long global flag later. Rejected because the requested UX is `-d` on `link` now.

### Centralize side effects behind dry-run checks in `linkHandler`
The link flow should build the same resolved source/target operations in both modes, then either report them or execute them depending on `dry_run`. The same pattern should guard future install/configure command execution so preview and execution stay coupled.

Alternative considered: early-return in dry-run before computing operations. Rejected because a useful dry run must still validate config and show concrete resolved paths.

### Test parsing separately from execution behavior
Argument parsing tests should verify `alma link -d foo` yields `dry_run=true` with the expected repo/module mapping. Link-flow tests should verify dry-run produces no side effects while still surfacing planned actions.

Alternative considered: cover everything only through integration tests. Rejected because parser edge cases are easier to pin down with unit tests.

## Risks / Trade-offs

- [Flag parsing ambiguity] → Keep `-d` scoped to `link` args and preserve current positional order rules in tests.
- [Preview drifts from real behavior] → Resolve paths and build operation descriptions in one place used by both dry-run and real execution.
- [Future command execution forgets dry-run] → Model dry-run on the payload now and document that install/configure execution must pass through the same gate.
- [Current handler already avoids symlink creation] → Keep the spec focused on the intended side-effect contract, not the temporary stubbed state.

## Migration Plan

1. Extend command payloads and parsing with a dry-run flag.
2. Update help text to advertise `alma link -d`.
3. Refactor link execution so planned actions are built once, then previewed or executed by mode.
4. Add/adjust tests for parser behavior and dry-run no-side-effect guarantees.

No user migration needed; existing `alma link` behavior remains default when `-d` is absent.

## Open Questions

- Exact preview text format can stay implementation-defined as long as planned filesystem changes and command skips are clear.