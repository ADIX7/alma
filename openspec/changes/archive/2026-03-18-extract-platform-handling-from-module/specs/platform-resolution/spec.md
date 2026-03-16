## ADDED Requirements

### Requirement: Module configuration loading delegates platform interpretation
Module configuration loading SHALL obtain runtime platform identifiers and platform selector evaluation from the shared platform-handling subsystem while preserving existing merge order, matching results, and validation errors.

#### Scenario: Configuration loading evaluates platform blocks after extraction
- **WHEN** `src/module.zig` loads a module configuration containing platform entries
- **THEN** it delegates platform detection and selector interpretation to the shared platform-handling subsystem
- **AND** it still applies the same matching entries in the same precedence order as before
