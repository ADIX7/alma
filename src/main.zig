const std = @import("std");
const module = @import("module.zig");
const Command = @import("command.zig").Command;
const linkHandler = @import("link.zig").linkHandler;

const log = std.log.scoped(.alma);

pub const std_options: std.Options = .{
    .log_level = std.log.Level.debug,
};

pub fn main() !void {
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var argsAllocator = try std.process.argsWithAllocator(allocator);
    defer argsAllocator.deinit();

    _ = argsAllocator.skip();

    const maybeCommand = parseArgs(allocator) catch |err| {
        switch (err) {
            error.MissingModuleName => {
                log.info("Error: Missing module name argument\n", .{});
                return;
            },
            else => {
                log.info("Error: Unknown error\n", .{});
                return;
            },
        }
    };

    var command = maybeCommand orelse {
        log.info("No command supplied.", .{});
        printHelp();
        return;
    };

    defer command.deinit(allocator);

    switch (command) {
        Command.unsupported => |cmd| {
            log.info("Error: Unsupported command: {s}\n\n", .{cmd});
            printHelp();
        },
        Command.help => {
            printHelp();
        },
        Command.link => |linkCmd| {
            linkHandler(allocator, linkCmd) catch |err| {
                log.info("Error executing link command: {}\n\n", .{err});
                return err;
            };
        },
    }
}

fn parseArgs(allocator: std.mem.Allocator) !?Command {
    var argIter = try std.process.argsWithAllocator(allocator);
    defer argIter.deinit();

    _ = argIter.skip();

    const arg = argIter.next() orelse return null;
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        return Command.help;
    } else if (std.mem.eql(u8, arg, "link")) {
        return parseLinkArgs(&argIter, allocator) catch |err| {
            return err;
        };
    } else return Command{ .unsupported = try allocator.dupe(u8, arg) };
}

fn parseLinkArgs(argIter: *std.process.ArgIterator, allocator: std.mem.Allocator) !Command {
    var repoName: ?[]u8 = null;
    var moduleName: ?[]u8 = null;
    while (argIter.next()) |arg| {
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

    return Command{ .link = .{
        .repo = repoName,
        .module = moduleName.?,
    } };
}

fn printHelp() void {
    log.info("Usage: alma <command> [options]\n", .{});
    log.info("Commands:\n", .{});
    log.info("  link [repo] <module>   Link a module from an optional repo\n", .{});
    log.info("  --help, -h             Show this help message\n", .{});
}
