# platform-resolution Specification

## Purpose
TBD - created by archiving change platform-resolution. Update Purpose after archive.
## Requirements
### Requirement: Runtime platform identifiers follow the Alma-Go hierarchy
The system SHALL derive the active platform identifier from the host environment using Alma-Go OS vocabulary and hierarchy. The identifier MUST use `windows`, `macos`, `freebsd`, or `linux` for recognized operating systems, MUST append the architecture using Zig architecture spellings, and on Linux MUST insert the distro `ID` from `/etc/os-release` when available before the architecture segment. If the operating system cannot be recognized, the identifier MUST be `unknown`.

#### Scenario: Linux identifier includes distro before architecture
- **WHEN** the host platform is Linux, `/etc/os-release` contains `ID=ubuntu`, and the host architecture is `x86_64`
- **THEN** the active platform identifier is `linux-ubuntu-x86_64`

#### Scenario: Non-Linux identifier omits distro
- **WHEN** the host platform is macOS and the host architecture is `aarch64`
- **THEN** the active platform identifier is `macos-aarch64`

### Requirement: Configuration loader matches Alma-Go-compatible selector ancestors
The system SHALL apply configuration entries whose selector is `default` or a valid ancestor of the active platform identifier using segment-aware prefix matching. The system MUST NOT treat arbitrary raw string prefixes as matches.

#### Scenario: Linux distro hierarchy matches ancestor selectors
- **WHEN** the active platform identifier is `linux-ubuntu-x86_64` and the configuration contains `default`, `linux`, `linux-ubuntu`, `linux-ubuntu-x86_64`, `linux-fedora`, and `linux-x86_64` entries
- **THEN** the resulting configuration includes values from `default`, `linux`, `linux-ubuntu`, and `linux-ubuntu-x86_64`
- **THEN** the resulting configuration excludes values from `linux-fedora` and `linux-x86_64`

#### Scenario: Non-Linux hierarchy matches OS and OS-arch selectors
- **WHEN** the active platform identifier is `windows-x86_64` and the configuration contains `default`, `windows`, `windows-x86_64`, and `linux` entries
- **THEN** the resulting configuration includes values from `default`, `windows`, and `windows-x86_64`
- **THEN** the resulting configuration excludes values from `linux`

### Requirement: Matching selectors merge from least specific to most specific
The system SHALL merge matching platform entries deterministically from least specific to most specific so generic values are established first and more specific matches override them later.

#### Scenario: Linux distro-specific architecture overrides generic Linux values
- **WHEN** the active platform identifier is `linux-ubuntu-x86_64` and matching configuration entries define conflicting values in `default`, `linux`, `linux-ubuntu`, and `linux-ubuntu-x86_64`
- **THEN** the merge order is `default`, then `linux`, then `linux-ubuntu`, then `linux-ubuntu-x86_64`
- **THEN** the final scalar values come from the most specific matching entry

### Requirement: Invalid selectors fail configuration loading
The system MUST reject platform selectors that are not `default` or a valid Alma-Go-compatible selector shape.

#### Scenario: Invalid selector is reported
- **WHEN** a module configuration contains a selector such as `darwin`, `x86_64-linux`, or any malformed raw prefix that is not a valid hierarchy segment path
- **THEN** configuration loading fails with an explicit invalid-platform-selector error

### Requirement: Module configuration loading delegates platform interpretation
Module configuration loading SHALL obtain runtime platform identifiers and platform selector evaluation from the shared platform-handling subsystem while preserving existing merge order, matching results, and validation errors.

#### Scenario: Configuration loading evaluates platform blocks after extraction
- **WHEN** `src/module.zig` loads a module configuration containing platform entries
- **THEN** it delegates platform detection and selector interpretation to the shared platform-handling subsystem
- **AND** it still applies the same matching entries in the same precedence order as before

