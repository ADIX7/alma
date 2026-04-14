const std = @import("std");
const module = @import("module.zig");
const Command = @import("command.zig");
const log = std.log.scoped(.alma);

pub fn installHandler(allocator: std.mem.Allocator, payload: Command.InstallPayload) !void {
    const module_source_path = try std.fmt.allocPrint(allocator, "/home/adam/dotconfig/{s}", .{payload.module});
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

    if (module_config.install) |install_cmd| {
        log.info("Executing install command: {s}\n", .{install_cmd});
        executeShellCommand(install_cmd);
    } else {
        log.info("No install command defined for module {s}.\n", .{payload.module});
    }
}

fn executeShellCommand(command: []const u8) void {
    std.debug.print("Execute shell command (not implemented for this Zig version): {s}\n", .{command});
}