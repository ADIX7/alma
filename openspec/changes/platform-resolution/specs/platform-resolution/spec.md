## ADDED Requirements

### Requirement: Configuration loader applies only matching platform entries
The system SHALL include configuration values from the `default` platform entry and from platform entries whose selector exactly matches the current platform context. The system MUST ignore non-matching supported selectors.

#### Scenario: Default and matching OS entry are applied
- **WHEN** a module configuration contains `default`, `linux`, and `darwin` entries and the current platform is `linux`
- **THEN** the resulting configuration includes values from `default` and `linux`
- **THEN** the resulting configuration excludes values from `darwin`

### Requirement: More specific matching selectors override less specific matches
The system SHALL apply matching platform entries in deterministic specificity order so generic defaults are set first and more specific matches override them later. Supported specificity order MUST be `default`, then `<os>`, then `<arch>-<os>`.

#### Scenario: Arch-and-OS selector overrides OS selector
- **WHEN** a module configuration contains matching `default`, `linux`, and `x86_64-linux` entries for a current platform of `x86_64-linux`
- **THEN** values from `default` are applied first
- **THEN** values from `linux` override conflicting default values
- **THEN** values from `x86_64-linux` override conflicting `linux` values

### Requirement: Unsupported selectors fail configuration loading
The system MUST reject platform selectors that are not `default`, `<os>`, or `<arch>-<os>` using recognized Zig target tag names.

#### Scenario: Invalid selector is reported
- **WHEN** a module configuration contains a platform selector with an unsupported format or unknown tag name
- **THEN** configuration loading fails with an explicit invalid-platform-selector error
