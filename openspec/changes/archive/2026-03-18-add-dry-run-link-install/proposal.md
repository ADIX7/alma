## Why

`alma link` is about to perform filesystem changes and may later run module-defined commands, but there is no safe preview mode. A dry-run flag makes it possible to inspect what would happen before touching symlinks or invoking commands.

## What Changes

- Add a `-d` dry-run flag to `alma link`.
- Parse dry-run at the CLI layer and pass it through the link execution path.
- Make dry-run report planned actions instead of mutating the filesystem.
- Reserve the same dry-run behavior for module-defined command execution in the link flow so future command execution can be previewed safely.
- Add tests for argument parsing and dry-run link behavior.

## Capabilities

### New Capabilities
- `link-dry-run`: Preview link actions without creating symlinks or running module-defined commands.

### Modified Capabilities

## Impact

- Affected code: `src/main.zig`, `src/command.zig`, `src/link.zig`, and tests.
- User-visible behavior: `alma link -d ...` prints what it would do and performs no side effects.
- Risk: low-medium because command parsing and side-effect boundaries must change together.