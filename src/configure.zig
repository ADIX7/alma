const std = @import("std");
const module = @import("module.zig");
const Command = @import("command.zig");
const log = std.log.scoped(.alma);

pub fn configureHandler(allocator: std.mem.Allocator, payload: Command.ConfigurePayload) !void {
    const module_source_path = try std.fmt.allocPrint(allocator, ".{s}{s}", .{std.fs.path.sep_str, payload.module});
    defer allocator.free(module_source_path);

    const context = module.ModuleContext{
        .module = payload.module,
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

    if (module_config.configure) |configure_cmd| {
        log.info("Executing configure command: {s}\n", .{configure_cmd});
        try executeShellCommand(configure_cmd);
    } else {
        log.info("No configure command defined for module {s}.\n", .{payload.module});
    }
}

fn executeShellCommand(command: []const u8) !void {
    std.debug.print("Executing configure command: {s}\n", .{command});
    // For now, just log the command. Full implementation would use
    // std.ChildProcess.init() when Zig version supports it properly.
}