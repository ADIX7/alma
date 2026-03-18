## Why

`alma` can read a module's `install` command from `.alma.yml`, but it cannot execute that command directly. Users currently have no first-class way to run module-defined install steps through the CLI.

## What Changes

- Add a new `alma install [-d] [repo] <module>` command.
- Load the target module configuration through the existing module-resolution flow.
- Execute the resolved module `install` command when present.
- When `-d` is supplied, log the resolved install command instead of executing it.
- Return a clear message when a module has no `install` command configured.
- Surface install command failures as command execution errors.

## Capabilities

### New Capabilities
- `module-install-command`: Run a module-defined install command through a dedicated CLI command.

### Modified Capabilities
- None.

## Impact

- Affected code: `src/main.zig`, `src/command.zig`, `src/link.zig` or shared command-execution helpers, and related tests.
- Affected UX: CLI help text and command parsing behavior.
- Dependencies/systems: process spawning for executing module-defined install commands.
