## ADDED Requirements

### Requirement: CLI accepts a dedicated install command
The system SHALL accept `alma install [-d] [repo] <module>` as a top-level command that targets a module using the same positional repo/module shape as other module-oriented commands.

#### Scenario: Install command parses module-only invocation
- **WHEN** the user runs `alma install dotfiles`
- **THEN** the parsed command is `install`
- **AND** the parsed module argument is `dotfiles`
- **AND** the parsed repo argument is absent

#### Scenario: Install command parses repo and module invocation
- **WHEN** the user runs `alma install repo dotfiles`
- **THEN** the parsed command is `install`
- **AND** the parsed repo argument is `repo`
- **AND** the parsed module argument is `dotfiles`

#### Scenario: Install command parses dry-run invocation
- **WHEN** the user runs `alma install -d dotfiles`
- **THEN** the parsed command is `install`
- **AND** the parsed module argument is `dotfiles`
- **AND** dry-run mode is enabled

### Requirement: Install command executes the resolved module install command
The system SHALL load the target module configuration using the normal module-resolution flow and execute the resolved `install` command when one is configured.

#### Scenario: Install command runs configured install step
- **WHEN** the resolved module configuration for the requested module includes `install: <command>`
- **AND** dry-run mode is not enabled
- **THEN** `alma install <module>` executes that command
- **AND** the command uses the resolved configuration after platform matching and merging

#### Scenario: Install command logs command in dry-run mode
- **WHEN** the resolved module configuration for the requested module includes `install: <command>`
- **AND** the user runs `alma install -d <module>`
- **THEN** the resolved install command is logged
- **AND** the system does not spawn a child process

#### Scenario: Install command reports missing install step
- **WHEN** the resolved module configuration for the requested module has no `install` command
- **THEN** `alma install <module>` reports that no install command is configured
- **AND** the system does not spawn a child process

### Requirement: Install command uses platform-defined shell invocation
The system SHALL execute configured install commands through a single shell command string using a documented shell per supported operating system.

#### Scenario: Linux install uses POSIX sh
- **WHEN** `alma install <module>` executes a resolved install command on Linux
- **THEN** the child process runs `sh -c <command>`

#### Scenario: Windows install uses PowerShell
- **WHEN** `alma install <module>` executes a resolved install command on Windows
- **THEN** the child process runs `pwsh -c <command>`

#### Scenario: Unsupported platform rejects install execution
- **WHEN** `alma install <module>` executes a resolved install command on a platform without a defined shell strategy
- **THEN** the command fails with a platform-not-supported execution error
- **AND** no best-effort fallback shell is used

### Requirement: Install command surfaces configuration and execution failures
The system SHALL fail the install command when configuration loading fails or when the configured install command cannot be executed successfully.

#### Scenario: Install command preserves configuration errors
- **WHEN** module configuration loading fails for the requested module
- **THEN** `alma install <module>` returns that configuration-loading error

#### Scenario: Install command reports install process failure
- **WHEN** the resolved `install` command exits non-zero or cannot be spawned
- **THEN** `alma install <module>` returns an execution error
- **AND** the failure is visible to the user
