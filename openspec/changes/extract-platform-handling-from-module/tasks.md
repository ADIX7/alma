## 1. Extract platform subsystem

- [ ] 1.1 Create a dedicated platform source file that owns platform identifier and platform selector types plus parse/detect/match helpers moved from `src/module.zig`
- [ ] 1.2 Expose the minimal public API needed by module loading, including selector specificity used for precedence ordering
- [ ] 1.3 Move platform-focused unit tests to the new platform module and keep coverage for parsing, detection, matching, and validation behavior

## 2. Rewire module loading

- [ ] 2.1 Update `src/module.zig` to import the extracted platform module and remove duplicated platform logic from the module loader
- [ ] 2.2 Keep configuration filtering and merge ordering in `src/module.zig` while delegating platform interpretation to the shared subsystem
- [ ] 2.3 Adjust any imports or call sites affected by the extraction and ensure the project still builds/tests cleanly

## 3. Verify behavior parity

- [ ] 3.1 Confirm existing platform-resolution behavior remains unchanged for valid selectors, invalid selectors, and precedence cases
- [ ] 3.2 Run the relevant test suite and fix any regressions caused by the refactor