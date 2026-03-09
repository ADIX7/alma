## 1. Platform selector resolution

- [ ] 1.1 Define the supported selector forms (`default`, `<os>`, `<arch>-<os>`) and add validation helpers in `src/module.zig`
- [ ] 1.2 Derive the current platform context and filter configuration entries to only matching selectors before merge
- [ ] 1.3 Preserve deterministic merge precedence so `default` loads first, OS-specific values override it, and arch+OS values override OS values
- [ ] 1.4 Return a clear error for unsupported or malformed platform selectors during configuration loading

## 2. Verification

- [ ] 2.1 Add unit tests for default-only and OS-specific matching behavior in the configuration loader
- [ ] 2.2 Add unit tests for arch+OS override precedence and exclusion of non-matching selectors
- [ ] 2.3 Add a unit test that invalid selectors fail with the expected error
- [ ] 2.4 Run the project test command and fix any regressions introduced by the change
