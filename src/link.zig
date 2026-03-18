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
    const module_source_path = try std.fmt.allocPrint(allocator, "/home/adam/dotconfig/{s}", .{command.module});
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
    log.debug("install: {s}", .{module_config.install orelse "-"});
    log.debug("configure: {s}", .{module_config.configure orelse "-"});

    const planned_links = try buildPlannedLinks(allocator, module_source_path, module_config);
    defer freePlannedLinks(allocator, planned_links);

    if (planned_links.len == 0) {
        log.info("No links defined.", .{});
    }

    for (planned_links) |planned_link| {
        if (command.dry_run) {
            std.debug.print("Would create symlink from {s} to {s}\n", .{ planned_link.source_path, planned_link.target_path });
        } else {
            std.debug.print("Creating symlink from {s} to {s}\n", .{ planned_link.source_path, planned_link.target_path });
            try createSymlinkAbsolute(planned_link.source_path, planned_link.target_path);
        }
    }

    try reportModuleCommand(command.dry_run, "install", module_config.install);
    try reportModuleCommand(command.dry_run, "configure", module_config.configure);
}

fn buildPlannedLinks(allocator: std.mem.Allocator, module_source_path: []const u8, module_config: *const module.ModuleConfiguration) ![]PlannedLink {
    const links = module_config.links orelse return try allocator.alloc(PlannedLink, 0);

    var planned_links = try allocator.alloc(PlannedLink, links.len);
    var built_count: usize = 0;
    errdefer {
        for (planned_links[0..built_count]) |planned_link| {
            allocator.free(planned_link.source_path);
            allocator.free(planned_link.target_path);
        }
        allocator.free(planned_links);
    }

    for (links, 0..) |link, i| {
        const source_path = try resolvePath(allocator, module_source_path, link.source);
        errdefer allocator.free(source_path);

        const target_path = try resolvePath(allocator, module_config.target orelse ".", link.target);
        errdefer allocator.free(target_path);

        if (std.mem.eql(u8, source_path, target_path)) {
            log.err("Source path and target path are the same: {s}\n", .{source_path});
            allocator.free(source_path);
            allocator.free(target_path);
            return error.InvalidLinkTarget;
        }

        planned_links[i] = .{
            .source_path = source_path,
            .target_path = target_path,
        };
        built_count += 1;
    }

    return planned_links;
}

fn freePlannedLinks(allocator: std.mem.Allocator, planned_links: []PlannedLink) void {
    for (planned_links) |planned_link| {
        allocator.free(planned_link.source_path);
        allocator.free(planned_link.target_path);
    }
    allocator.free(planned_links);
}

fn reportModuleCommand(dry_run: bool, label: []const u8, command: ?[]const u8) !void {
    const value = command orelse return;
    if (dry_run) {
        std.debug.print("Would run {s} command: {s}\n", .{ label, value });
        return;
    }

    std.debug.print("Skipping {s} command execution (not implemented): {s}\n", .{ label, value });
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

test "build planned links resolves module and target paths" {
    const allocator = std.testing.allocator;
    const config = try allocator.create(module.ModuleConfiguration);
    defer allocator.destroy(config);

    const links = try allocator.alloc(module.Link, 1);
    links[0] = .{
        .source = try allocator.dupe(u8, "nvim/init.lua"),
        .target = try allocator.dupe(u8, "config/init.lua"),
    };

    config.* = .{
        .allocator = allocator,
        .target = try allocator.dupe(u8, "/tmp/alma-target"),
        .links = links,
    };
    defer config.deinit();

    const planned_links = try buildPlannedLinks(allocator, "/tmp/alma-module", config);
    defer freePlannedLinks(allocator, planned_links);

    try std.testing.expectEqual(@as(usize, 1), planned_links.len);
    try std.testing.expectEqualStrings("/tmp/alma-module/nvim/init.lua", planned_links[0].source_path);
    try std.testing.expectEqualStrings("/tmp/alma-target/config/init.lua", planned_links[0].target_path);
}

test "build planned links rejects identical source and target" {
    const allocator = std.testing.allocator;
    const config = try allocator.create(module.ModuleConfiguration);
    defer allocator.destroy(config);

    const links = try allocator.alloc(module.Link, 1);
    links[0] = .{
        .source = try allocator.dupe(u8, "same"),
        .target = try allocator.dupe(u8, "same"),
    };

    config.* = .{
        .allocator = allocator,
        .target = try allocator.dupe(u8, "/tmp/alma-module"),
        .links = links,
    };
    defer config.deinit();

    try std.testing.expectError(error.InvalidLinkTarget, buildPlannedLinks(allocator, "/tmp/alma-module", config));
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
