const std = @import("std");
const builtin = @import("builtin");
const child_process = std.process;
const log = std.log.scoped(.alma);

pub fn executeShellCommand(command: []const u8) !void {
    const shell = if (builtin.os.tag == .windows) "cmd.exe" else "/bin/sh";
    const shell_arg = if (builtin.os.tag == .windows) "/C" else "-c";
    
    const argv = [_][]const u8{ shell, shell_arg, command };
    
    var child = child_process.Child.init(&argv, std.heap.page_allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    child.spawn() catch |err| {
        log.info("Failed to spawn shell process: {}\n", .{err});
        return err;
    };
    
    const term = child.wait() catch |err| {
        log.info("Failed to wait for shell process: {}\n", .{err});
        return err;
    };
    
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                log.info("Shell command failed with exit code: {}\n", .{code});
                return error.CommandFailed;
            }
        },
        .Signal, .Stopped, .Unknown => {
            log.info("Shell process terminated abnormally: {s}\n", .{@tagName(term)});
            return error.CommandTerminated;
        },
    }
}