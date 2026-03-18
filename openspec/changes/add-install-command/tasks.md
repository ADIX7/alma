## 1. CLI parsing

- [ ] 1.1 Add an `install` command payload to `src/command.zig` and preserve allocator cleanup for repo/module fields
- [ ] 1.2 Update `src/main.zig` argument parsing to recognize `alma install [-d] [repo] <module>` alongside existing commands
- [ ] 1.3 Update help text and add parser tests for install module-only, repo+module, and dry-run invocations

## 2. Install execution

- [ ] 2.1 Extract or add shared module-resolution logic needed to load a module configuration for install without coupling it to link-only behavior
- [ ] 2.2 Implement an install handler that loads the resolved module configuration, reports when no install command is configured, and executes the resolved install command when present
- [ ] 2.3 Add a child-process execution helper for module commands, using `sh -c` on Linux and `pwsh -c` on Windows; when `-d` is set only log the resolved install command and skip execution; propagate non-zero exit, spawn failures, and unsupported-platform failures as install command errors

## 3. Verification

- [ ] 3.1 Add tests covering successful install execution, missing install no-op reporting, and configuration/error propagation
- [ ] 3.2 Run the relevant Zig test suite and fix any regressions
