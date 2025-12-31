const std = @import("std");
const known_folders = @import("known-folders");
const module = @import("module.zig");
const LinkPayload = @import("command.zig").LinkPayload;
const log = std.log.scoped(.alma);

pub fn linkHandler(allocator: std.mem.Allocator, command: LinkPayload) !void {
    //TODO: implement proper module source path resolution based on repo and module name
    // const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    const module_source_path = try std.fmt.allocPrint(allocator, "/home/adam/dotconfig/{s}", .{command.module});
    defer allocator.free(module_source_path);

    const context = module.ModuleContext{
        .module = command.module,
        .module_path = try std.fmt.allocPrint(allocator, "{s}/.alma.yml", .{module_source_path}),
    };
    defer allocator.free(context.module_path);

    const moduleConfig = context.loadConfiguration(allocator) catch |err| {
        switch (err) {
            error.FileNotFound => {
                log.info("Error: Configuration file not found at path: {s}\n", .{context.module_path});
            },
            else => {
                log.info("Error loading configuration: {}\n", .{err});
            },
        }
        return err;
    };
    defer allocator.destroy(moduleConfig);
    defer moduleConfig.deinit();

    log.debug("Module configuration loaded successfully", .{});
    log.debug("target: {s}", .{moduleConfig.target orelse "-"});
    log.debug("install: {s}", .{moduleConfig.install orelse "-"});
    log.debug("configure: {s}", .{moduleConfig.configure orelse "-"});
    if (moduleConfig.links) |links| {
        log.debug("Links:", .{});
        for (links) |link| {
            log.debug(" - {s} -> {s}", .{ link.source, link.target });
        }
    } else {
        std.debug.print("No links defined.", .{});
    }

    const links = moduleConfig.links orelse {
        log.info("No links defined.", .{});
        return;
    };

    for (links) |link| {
        const sourcePath = try resolvePath(allocator, module_source_path, link.source);
        defer allocator.free(sourcePath);
        const targetPath = try resolvePath(allocator, moduleConfig.target orelse ".", link.target);
        defer allocator.free(targetPath);

        if (std.mem.eql(u8, sourcePath, targetPath)) {
            log.err("Source path and target path are the same: {s}\n", .{sourcePath});
            continue;
        }
        std.debug.print("Creating symlink from {s} to {s}\n", .{ sourcePath, targetPath });

        // std.fs.symLinkAbsolute(link.source, link.target, .{}) catch |err| {
        //     log.err("Error creating symlink from {s} to {s}: {}\n", .{ link.source, link.target, err });
        // };
    }
}

fn resolvePath(allocator: std.mem.Allocator, relativePart: []const u8, path: []const u8) ![]const u8 {
    const preProcessResult = try specialPathResolver(allocator, path);
    if (preProcessResult.processed) {
        return preProcessResult.path;
    }

    const path2 = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ relativePart, std.fs.path.sep_str, path });
    const processedResult = try specialPathResolver(allocator, path2);
    if (processedResult.processed) {
        allocator.free(path2);
    }
    return processedResult.path;
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
