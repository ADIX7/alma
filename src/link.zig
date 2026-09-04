const std = @import("std");
const known_folders = @import("known-folders");
const module = @import("module.zig");
const LinkPayload = @import("command.zig").LinkPayload;
const log = std.log.scoped(.alma);

const PlannedLink = struct {
    source_path: []const u8,
    target_path: []const u8,
};

pub fn linkHandler(allocator: std.mem.Allocator, command: LinkPayload) !void {
    const module_source_path = try std.fmt.allocPrint(allocator, ".{s}{s}", .{std.fs.path.sep_str, command.module});
    defer allocator.free(module_source_path);

    try linkHandlerWithModuleSourcePath(allocator, command, module_source_path);
}

fn linkHandlerWithModuleSourcePath(allocator: std.mem.Allocator, command: LinkPayload, module_source_path: []const u8) !void {
    const context = module.ModuleContext{
        .module = command.module,
        .module_path = try std.fmt.allocPrint(allocator, "{s}/.alma.yml", .{module_source_path}),
    };
    defer allocator.free(context.module_path);

    const module_config = context.loadConfiguration(allocator) catch |err| {
        switch (err) {
            error.FileNotFound => log.info("Error: Configuration file not found at path: {s}\n", .{context.module_path}),
            else => log.info("Error loading configuration: {}\n", .{err}),
        }
        return err;
    };
    defer allocator.destroy(module_config);
    defer module_config.deinit();

    log.debug("Module configuration loaded successfully", .{});
    log.debug("target: {s}", .{module_config.target orelse "-"});

    const planned_links = try gatherItemsToLink(allocator, module_source_path, module_config);
    defer freeGatheredPlannedLinks(allocator, planned_links);

    if (planned_links.items.len == 0) {
        log.info("No links defined.", .{});
    }

    for (planned_links.items) |planned_link| {
        if (command.dry_run) {
            log.info("Would create symlink from {s} to {s}\n", .{ planned_link.source_path, planned_link.target_path });
        } else {
            log.info("Creating symlink from {s} to {s}\n", .{ planned_link.source_path, planned_link.target_path });
            try createSymlinkAbsolute(planned_link.source_path, planned_link.target_path);
        }
    }
}

pub fn freeGatheredPlannedLinks(allocator: std.mem.Allocator, planned_links: *std.ArrayList(PlannedLink)) void {
    for (planned_links.items) |planned_link| {
        allocator.free(planned_link.source_path);
        allocator.free(planned_link.target_path);
    }
    planned_links.deinit();
}

/// Recursively walks the module directory and plans a symlink for every file.
/// Explicit `links` entries override the mirrored target path when their source
/// matches the file's relative path.
fn gatherItemsToLink(
    allocator: std.mem.Allocator,
    module_source_path: []const u8,
    module_config: *const module.ModuleConfiguration,
) !*std.ArrayList(PlannedLink) {
    var planned = std.ArrayList(PlannedLink).init(allocator);
    errdefer planned.deinit();

    try gatherDir(allocator, module_source_path, "", module_config, &planned);
    return &planned;
}

fn gatherDir(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    rel_path: []const u8,
    module_config: *const module.ModuleConfiguration,
    planned: *std.ArrayList(PlannedLink),
) !void {
    var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = .{ .follow_links = false } });
    defer dir.close();
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind == .directory and std.mem.eql(u8, entry.name, ".git")) continue;

        switch (entry.kind) {
            .directory => {
                const child_rel = try joinRel(allocator, rel_path, entry.name);
                errdefer allocator.free(child_rel);
                if (isExcludedUserPath(module_config, child_rel)) {
                    allocator.free(child_rel);
                    continue;
                }
                const child_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                errdefer allocator.free(child_path);
                try gatherDir(allocator, child_path, child_rel, module_config, planned);
                allocator.free(child_path);
            },
            .file => {
                if (std.mem.eql(u8, entry.name, ".alma.yml")) continue;

                const rel = if (rel_path.len == 0)
                    entry.name
                else
                    try std.fs.path.join(allocator, &[_][]const u8{ rel_path, entry.name });
                var explicit_target: ?[]const u8 = null;
                errdefer {
                    if (rel_path.len != 0) allocator.free(rel);
                    if (explicit_target) |t| allocator.free(t);
                }

                if (isExcludedUserPath(module_config, rel)) {
                    if (rel_path.len != 0) allocator.free(rel);
                    continue;
                }
                if (module_config.exclude_readme and isReadmeFile(entry.name)) {
                    if (rel_path.len != 0) allocator.free(rel);
                    continue;
                }

                const source_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                errdefer allocator.free(source_path);

                if (findExplicitTarget(module_config, rel)) |target| explicit_target = try allocator.dupe(u8, target);
                const target_path = try resolvePath(allocator, module_config.target orelse ".", explicit_target orelse rel);
                errdefer allocator.free(target_path);

                if (std.mem.eql(u8, source_path, target_path)) {
                    log.err("Source path and target path are the same: {s}\n", .{source_path});
                    allocator.free(source_path);
                    allocator.free(target_path);
                    if (rel_path.len != 0) allocator.free(rel);
                    if (explicit_target) |t| allocator.free(t);
                    return error.InvalidLinkTarget;
                }

                try planned.append(.{ .source_path = source_path, .target_path = target_path });
                allocator.free(source_path);
                if (rel_path.len != 0) allocator.free(rel);
                if (explicit_target) |t| allocator.free(t);
            },
            else => {},
        }
    }
}

fn findExplicitTarget(module_config: *const module.ModuleConfiguration, rel_path: []const u8) ?[]const u8 {
    const links = module_config.links orelse return null;
    for (links) |link| {
        if (std.mem.eql(u8, link.source, rel_path)) return link.target;
    }
    return null;
}

/// Matches user-defined exclude entries against a relative path: exact match
/// (file or directory) or directory prefix (everything under the path).
fn isExcludedUserPath(module_config: *const module.ModuleConfiguration, rel_path: []const u8) bool {
    const excludes = module_config.exclude orelse return false;
    for (excludes) |ex| {
        if (std.mem.eql(u8, ex, rel_path)) return true;
        if (rel_path.len > ex.len and std.mem.startsWith(u8, rel_path, ex) and rel_path[ex.len] == '/') return true;
    }
    return false;
}

fn isReadmeFile(name: []const u8) bool {
    if (name.len < 6) return false;
    if (!std.ascii.eqlIgnoreCase("readme", name[0..6])) return false;
    return name.len == 6 or name[6] == '.';
}

fn joinRel(allocator: std.mem.Allocator, rel_path: []const u8, name: []const u8) ![]const u8 {
    if (rel_path.len == 0) return try allocator.dupe(u8, name);
    return std.fs.path.join(allocator, &[_][]const u8{ rel_path, name });
}

fn createSymlinkAbsolute(source_path: []const u8, target_path: []const u8) !void {
    if (std.fs.path.isAbsolute(target_path)) {
        if (std.fs.path.dirname(target_path)) |target_dir| try std.fs.cwd().makePath(target_dir);
        try std.fs.symLinkAbsolute(source_path, target_path, .{});
        return;
    }

    return error.RelativeTargetPathUnsupported;
}

fn resolvePath(allocator: std.mem.Allocator, relative_part: []const u8, path: []const u8) ![]const u8 {
    const pre_process_result = try specialPathResolver(allocator, path);
    if (pre_process_result.processed) return pre_process_result.path;

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ relative_part, std.fs.path.sep_str, path });
    const processed_result = try specialPathResolver(allocator, combined);
    if (processed_result.processed) allocator.free(combined);
    return processed_result.path;
}

fn specialPathResolver(allocator: std.mem.Allocator, path: []const u8) !struct { processed: bool, path: []const u8 } {
    if (std.mem.startsWith(u8, path, "~")) {
        const home = try known_folders.getPath(allocator, known_folders.KnownFolder.home) orelse return error.HomeFolderNotFound;
        defer allocator.free(home);
        return .{
            .processed = true,
            .path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home, path[1..] }),
        };
    }

    return .{ .processed = false, .path = path };
}

test "gatherItemsToLink rejects identical source and target" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.writeFile(.{ .sub_path = "module/same.txt", .data = "" });
    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);

    const config = try allocator.create(module.ModuleConfiguration);
    defer allocator.destroy(config);
    config.* = .{
        .allocator = allocator,
        .target = module_source_path,
    };
    defer config.deinit();

    try std.testing.expectError(error.InvalidLinkTarget, gatherItemsToLink(allocator, module_source_path, config));
}

test "dry run does not create symlink" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.makePath("module/nvim");
    try dir.dir.makePath("target");
    try dir.dir.writeFile(.{ .sub_path = "module/nvim/init.lua", .data = "return {}\n" });

    const target_path = try dir.dir.realpathAlloc(allocator, "target");
    defer allocator.free(target_path);
    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);

    const config = try std.fmt.allocPrint(allocator,
        "platforms:\n  - platform: default\n    target: {s}\n    install: echo install\n    configure: echo configure\n    links:\n      - source: nvim/init.lua\n        target: config/init.lua\n",
        .{target_path},
    );
    defer allocator.free(config);
    try dir.dir.writeFile(.{ .sub_path = "module/.alma.yml", .data = config });

    const module_name = try allocator.dupe(u8, "dotfiles");
    defer allocator.free(module_name);

    try linkHandlerWithModuleSourcePath(allocator, .{ .repo = null, .module = module_name, .dry_run = true }, module_source_path);

    const created_path = try std.fmt.allocPrint(allocator, "{s}/config/init.lua", .{target_path});
    defer allocator.free(created_path);
    try std.testing.expectError(error.FileNotFound, std.fs.accessAbsolute(created_path, .{}));
}

test "normal mode creates symlink" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.makePath("module/nvim");
    try dir.dir.makePath("target");
    try dir.dir.writeFile(.{ .sub_path = "module/nvim/init.lua", .data = "return {}\n" });

    const target_path = try dir.dir.realpathAlloc(allocator, "target");
    defer allocator.free(target_path);
    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);

    const config = try std.fmt.allocPrint(allocator,
        "platforms:\n  - platform: default\n    target: {s}\n    links:\n      - source: nvim/init.lua\n        target: config/init.lua\n",
        .{target_path},
    );
    defer allocator.free(config);
    try dir.dir.writeFile(.{ .sub_path = "module/.alma.yml", .data = config });

    const module_name = try allocator.dupe(u8, "dotfiles");
    defer allocator.free(module_name);

    try linkHandlerWithModuleSourcePath(allocator, .{ .repo = null, .module = module_name, .dry_run = false }, module_source_path);

    const created_path = try std.fmt.allocPrint(allocator, "{s}/config/init.lua", .{target_path});
    defer allocator.free(created_path);
    try std.fs.accessAbsolute(created_path, .{});
}

test "gatherItemsToLink mirrors nested files and applies explicit overrides" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.makePath("module/nvim/lsp");
    try dir.dir.writeFile(.{ .sub_path = "module/nvim/init.lua", .data = "" });
    try dir.dir.writeFile(.{ .sub_path = "module/nvim/lsp/kick.lua", .data = "" });
    try dir.dir.writeFile(.{ .sub_path = "module/top.txt", .data = "" });

    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);
    const target_path = try dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(target_path);

    const config = try allocator.create(module.ModuleConfiguration);
    defer allocator.destroy(config);
    const links = try allocator.alloc(module.Link, 1);
    links[0] = .{
        .source = try allocator.dupe(u8, "nvim/init.lua"),
        .target = try allocator.dupe(u8, "alt/init.lua"),
    };
    config.* = .{
        .allocator = allocator,
        .target = try allocator.dupe(u8, target_path),
        .links = links,
    };
    defer config.deinit();

    const planned = try gatherItemsToLink(allocator, module_source_path, config);
    defer freeGatheredPlannedLinks(allocator, planned);

    try std.testing.expectEqual(@as(usize, 3), planned.items.len);

    const found = blk: {
        for (planned.items) |planned_link| {
            if (std.mem.endsWith(u8, planned_link.source_path, "lsp/kick.lua")) break :blk planned_link;
        }
        @panic("mirrored nested file not found");
    };
    try std.testing.expect(std.mem.endsWith(u8, found.target_path, "/lsp/kick.lua"));

    const overridden = blk: {
        for (planned.items) |planned_link| {
            if (std.mem.endsWith(u8, planned_link.source_path, "nvim/init.lua")) break :blk planned_link;
        }
        @panic("overridden file not found");
    };
    const expected_target = try std.fs.path.join(allocator, &[_][]const u8{ target_path, "alt/init.lua" });
    defer allocator.free(expected_target);
    try std.testing.expectEqualStrings(expected_target, overridden.target_path);
}

test "gatherItemsToLink applies exclusion filters" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.makePath("module/skipme");
    try dir.dir.makePath("module/keep/nested");
    try dir.dir.writeFile(.{ .sub_path = "module/.alma.yml", .data = "" });
    try dir.dir.writeFile(.{ .sub_path = "module/README.md", .data = "" });
    try dir.dir.writeFile(.{ .sub_path = "module/skipme/secret.txt", .data = "" });
    try dir.dir.writeFile(.{ .sub_path = "module/keep/nested/stay.txt", .data = "" });

    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);
    const target_path = try dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(target_path);

    const config = try allocator.create(module.ModuleConfiguration);
    defer allocator.destroy(config);
    const exclude_slice = try allocator.alloc([]const u8, 1);
    exclude_slice[0] = try allocator.dupe(u8, "skipme");
    config.* = .{
        .allocator = allocator,
        .target = try allocator.dupe(u8, target_path),
        .exclude = exclude_slice,
        .exclude_readme = true,
    };
    defer config.deinit();

    const planned = try gatherItemsToLink(allocator, module_source_path, config);
    defer freeGatheredPlannedLinks(allocator, planned);

    try std.testing.expectEqual(@as(usize, 1), planned.items.len);
    try std.testing.expect(std.mem.endsWith(u8, planned.items[0].source_path, "keep/nested/stay.txt"));
}

test "dry run preserves configuration errors" {
    const allocator = std.testing.allocator;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.makePath("module");
    try dir.dir.writeFile(.{ .sub_path = "module/.alma.yml", .data = "platforms:\n  - platform: darwin\n    target: /tmp/nope\n" });

    const module_source_path = try dir.dir.realpathAlloc(allocator, "module");
    defer allocator.free(module_source_path);
    const module_name = try allocator.dupe(u8, "dotfiles");
    defer allocator.free(module_name);

    try std.testing.expectError(error.InvalidPlatformSelector, linkHandlerWithModuleSourcePath(allocator, .{ .repo = null, .module = module_name, .dry_run = true }, module_source_path));
}
