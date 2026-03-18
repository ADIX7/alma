## 1. CLI parsing

- [x] 1.1 Add a `dry_run` field to the link command payload and preserve deinit behavior
- [x] 1.2 Update `parseLinkArgs` to accept `-d` while keeping `[repo] <module>` positional parsing intact
- [x] 1.3 Update help text and add parser tests for `alma link -d ...` and normal `alma link ...`

## 2. Link dry-run behavior

- [x] 2.1 Refactor `linkHandler` to build resolved link operations in one place shared by dry-run and normal execution
- [x] 2.2 Make dry-run report planned symlink operations without mutating the filesystem
- [x] 2.3 Gate future install/configure command execution behind the same dry-run mode and report skipped commands in preview output

## 3. Verification

- [x] 3.1 Add tests covering dry-run no-side-effect behavior and configuration-error parity
- [x] 3.2 Run the relevant test suite and fix any regressions
