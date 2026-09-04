# Implementation Plan: Hybrid Mirroring for Link Command

Goal: Transition `alma-zig` from an explicit-only linking strategy to a hybrid strategy that recursively mirrors the module directory to the target, while respecting explicit overrides and exclusion rules.

## Phase 1: Configuration Schema Update
- [x] **Step 1: Add Exclusions to `ModuleConfiguration`**
    - Update `src/module.zig` to include `exclude: ?[]const []const u8` and `exclude_readme: bool` in `ModuleConfiguration`, `ModuleConfigurationBuilder`, and `ModuleConfigurationPart`.
    - Implement additive merging for `exclude` and boolean OR for `exclude_readme` in `loadConfigurationFromSource`.
    - Update `ModuleConfiguration.deinit` to properly free the `exclude` list and its elements.
    - Update YAML decoding logic to map these fields from `.alma.yml`.

## Phase 2: Recursive Gathering Logic
- [x] **Step 2: Implement `gatherItemsToLink` with `ArrayList`**
    - In `src/link.zig`, implement a recursive walker using `std.fs.Dir.iterate()`.
    - For each entry:
        - Calculate the relative path from the module root.
        - Use explicit target if defined in `links` config; otherwise, use the mirrored target path.
        - Store as `PlannedLink` in a `std.ArrayList`.
- [x] **Step 3: Implement Exclusion Filtering**
    - Filter the gathered items:
        - Mandatory: Exclude `.alma.yml`.
        - Safety: Exclude `.git`.
        - User-defined: Exclude paths matching the `exclude` list.
        - Readme: Exclude common README filenames if `exclude_readme` is true.

## Phase 3: Execution & Pathing
- [x] **Step 4: Integrate Gatherer into `linkHandler`**
    - Update `linkHandlerWithModuleSourcePath` to use the new recursive gatherer.
    - Ensure proper memory management for the `ArrayList` and duplicated strings.
- [x] **Step 5: Robust Target Path Creation**
    - Enhance `createSymlinkAbsolute` to ensure all parent directories of the target path are created recursively.

## Phase 4: Testing & Validation
- [x] **Step 6: Comprehensive Test Suite**
    - Test recursive mirroring of nested directory structures.
    - Test explicit overrides taking precedence over mirrored paths.
    - Test exclusion list filtering.
    - Test `exclude_readme` functionality.
