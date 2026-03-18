# link-dry-run Specification

## Purpose
TBD - created by syncing change add-dry-run-link-install. Update Purpose after archive.
## Requirements
### Requirement: Link command supports dry-run mode
The system SHALL accept a `-d` flag on `alma link` that enables dry-run mode for that invocation.

#### Scenario: Dry-run flag is parsed for link
- **WHEN** the user runs `alma link -d dotfiles`
- **THEN** the parsed link command includes `dry_run = true`
- **AND** the module argument is `dotfiles`

#### Scenario: Link without dry-run keeps normal mode
- **WHEN** the user runs `alma link dotfiles`
- **THEN** the parsed link command includes `dry_run = false`
- **AND** the module argument is `dotfiles`

### Requirement: Dry-run mode previews filesystem changes without mutating them
The system SHALL resolve the same link operations in dry-run mode as in normal mode, but it MUST NOT create, replace, or modify filesystem entries while dry-run is enabled.

#### Scenario: Dry-run previews symlink creation
- **WHEN** module configuration resolves one or more links and the user runs `alma link -d <module>`
- **THEN** the system reports each planned source and target path
- **AND** the system does not create any symlinks

#### Scenario: Dry-run still validates configuration
- **WHEN** the module configuration is invalid and the user runs `alma link -d <module>`
- **THEN** the system returns the same configuration-loading error it would return in normal mode

### Requirement: Dry-run mode suppresses module-defined command execution
The system SHALL treat dry-run as a no-side-effect mode for any module-defined commands reached by the link flow, including install and configure commands.

#### Scenario: Dry-run suppresses install command execution
- **WHEN** the resolved module configuration includes an `install` command and the user runs `alma link -d <module>`
- **THEN** the system reports that the install command would run
- **AND** the system does not execute the command

#### Scenario: Dry-run suppresses configure command execution
- **WHEN** the resolved module configuration includes a `configure` command and the user runs `alma link -d <module>`
- **THEN** the system reports that the configure command would run
- **AND** the system does not execute the command
