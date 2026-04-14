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
        try executeShellCommand(allocator, install_cmd);
    } else {
        log.info("No install command defined for module {s}.\n", .{payload.module});
    }
}

fn executeShellCommand(allocator: std.mem.Allocator, command: []const u8) !void {
    const shell = if (std.Target.current.os.tag == .windows) 
        "cmd" 
    else 
        "/bin/sh";
        
    const shell_flag = if (std.Target.current.os.tag == .windows) 
        "/C" 
    else 
        "-c";

    var child = std.ChildProcess.init(shell, allocator);
    child.addArg(shell_flag);
    child.addArg(command);
    
    try child.spawn();
    const term = try child.wait();
    
    if (term != 0) {
        log.err("Install command exited with non-zero status: {d}\n", .{term});
        return error.CommandFailed;
    }
}
