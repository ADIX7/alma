const std = @import("std");
const module = @import("module.zig");

const Args = struct {
    repo: ?[]u8,
    module: []u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var argsAllocator = try std.process.argsWithAllocator(allocator);
    defer argsAllocator.deinit();

    _ = argsAllocator.skip();

    std.debug.print("1\n", .{});

    const args = parseArgs(allocator) catch |err| {
        switch (err) {
            error.MissingModuleName => {
                try stdout.print("Error: Missing module name argument\n", .{});
                return;
            },
            else => {
                try stdout.print("Error: Unknown error\n", .{});
                return;
            },
        }
    };
    defer {
        allocator.free(args.module);
        if (args.repo) |s| {
            allocator.free(s);
        }
    }

    std.debug.print("2\n", .{});

    const context = module.ModuleContext{
        .module = args.module,
        .module_path = try std.fmt.allocPrint(allocator, "/home/adam/dotconfig/{s}/.alma-config.json", .{args.module}),
    };
    defer allocator.free(context.module_path);

    std.debug.print("3\n", .{});

    const moduleConfig = context.loadConfiguration(allocator) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try stdout.print("Error: Configuration file not found at path: {s}\n", .{context.module_path});
            },
            else => {
                try stdout.print("Error loading configuration: {}\n", .{err});
            },
        }
        return err;
    };
    defer moduleConfig.deinit();

    std.debug.print("1\n", .{});
    std.debug.print("Module configuration loaded successfully: {}\n", .{moduleConfig.value.len});
}

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var argsAllocator = try std.process.argsWithAllocator(allocator);
    defer argsAllocator.deinit();

    _ = argsAllocator.skip();

    var repoName: ?[]u8 = null;
    var moduleName: ?[]u8 = null;
    while (argsAllocator.next()) |arg| {
        if (moduleName) |m| {
            repoName = m;
            moduleName = allocator.dupe(u8, arg) catch return error.OutOfMemory;
        } else {
            moduleName = allocator.dupe(u8, arg) catch return error.OutOfMemory;
        }
    }

    if (moduleName == null) {
        return error.MissingModuleName;
    }

    return .{
        .repo = repoName,
        .module = moduleName.?,
    };
}
