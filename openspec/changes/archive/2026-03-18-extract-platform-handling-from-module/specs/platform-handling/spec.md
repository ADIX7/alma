## ADDED Requirements

### Requirement: Platform logic is provided by a dedicated subsystem
The system SHALL provide a dedicated platform-handling subsystem that owns runtime platform identification, platform identifier parsing, platform selector parsing, selector matching, and selector specificity evaluation independent of module configuration loading.

#### Scenario: Module loading needs platform evaluation
- **WHEN** module configuration loading needs to detect the active platform or evaluate a platform selector
- **THEN** it uses the dedicated platform-handling subsystem instead of local platform logic embedded in `src/module.zig`

### Requirement: Extracted platform handling preserves current selector semantics
The dedicated platform-handling subsystem SHALL preserve the current Alma-Go-compatible selector validation and matching semantics used by module configuration loading.

#### Scenario: Existing valid selectors are evaluated after extraction
- **WHEN** selectors such as `default`, `linux`, `linux-ubuntu`, or `linux-ubuntu-x86_64` are evaluated through the extracted subsystem
- **THEN** they produce the same match and specificity outcomes as before the extraction
