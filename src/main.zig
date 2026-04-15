const std = @import("std");
const Command = @import("command.zig").Command;
const linkHandler = @import("link.zig").linkHandler;
const installHandler = @import("install.zig").installHandler;
const configureHandler = @import("configure.zig").configureHandler;

const log = std.log.scoped(.alma);

pub const std_options: std.Options = .{
    .log_level = std.log.Level.debug,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const maybeCommand = parseArgs(allocator) catch |err| {
        switch (err) {
            error.MissingModuleName => {
                log.info("Error: Missing module name argument\n", .{});
                return;
            },
            error.UnknownLinkFlag => {
                log.info("Error: Unknown link flag\n\n", .{});
                printHelp();
                return;
            },
            error.UnknownInstallFlag => {
                log.info("Error: Unknown install flag\n\n", .{});
                printHelp();
                return;
            },
            error.ConfigureUnknownFlag => {
                log.info("Error: Unknown configure flag\n\n", .{});
                printHelp();
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
        Command.help => printHelp(),
        Command.link => |linkCmd| {
            linkHandler(allocator, linkCmd) catch |err| {
                log.info("Error executing link command: {}\n\n", .{err});
                return err;
            };
        },
        Command.install => |installCmd| {
            installHandler(allocator, installCmd) catch |err| {
                log.info("Error executing install command: {}\n\n", .{err});
                return err;
            };
        },
        Command.configure => |configureCmd| {
            configureHandler(allocator, configureCmd) catch |err| {
                log.info("Error executing configure command: {}\n\n", .{err});
                return err;
            };
        },
    }
}

fn parseArgs(allocator: std.mem.Allocator) !?Command {
    var arg_iter = try std.process.argsWithAllocator(allocator);
    defer arg_iter.deinit();

    _ = arg_iter.skip();

    const arg = arg_iter.next() orelse return null;
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return Command.help;
    if (std.mem.eql(u8, arg, "link")) return try parseLinkArgs(&arg_iter, allocator);
    if (std.mem.eql(u8, arg, "install")) return try parseInstallArgs(&arg_iter, allocator);
    if (std.mem.eql(u8, arg, "configure")) return try parseConfigureArgs(&arg_iter, allocator);
    return Command{ .unsupported = try allocator.dupe(u8, arg) };
}

fn parseInstallArgs(arg_iter: *std.process.ArgIterator, allocator: std.mem.Allocator) !Command {
    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);

    while (arg_iter.next()) |arg| try raw_args.append(allocator, arg);
    return parseInstallArgsSlice(raw_args.items, allocator);
}

fn parseInstallArgsSlice(args: []const []const u8, allocator: std.mem.Allocator) !Command {
    var dry_run = false;
    var repo_name: ?[]u8 = null;
    var module_name: ?[]u8 = null;
    errdefer {
        if (repo_name) |repo| allocator.free(repo);
        if (module_name) |module| allocator.free(module);
    }

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-d")) {
                dry_run = true;
                continue;
            }
            return error.UnknownInstallFlag;
        }

        if (module_name) |existing_module| {
            repo_name = existing_module;
            module_name = try allocator.dupe(u8, arg);
        } else {
            module_name = try allocator.dupe(u8, arg);
        }
    }

    if (module_name == null) return error.MissingModuleName;

    return Command{ .install = .{
        .repo = repo_name,
        .module = module_name.?,
        .dry_run = dry_run,
    }};
}

fn parseLinkArgs(arg_iter: *std.process.ArgIterator, allocator: std.mem.Allocator) !Command {
    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);

    while (arg_iter.next()) |arg| try raw_args.append(allocator, arg);
    return parseLinkArgsSlice(raw_args.items, allocator);
}

fn parseLinkArgsSlice(args: []const []const u8, allocator: std.mem.Allocator) !Command {
    var dry_run = false;
    var repo_name: ?[]u8 = null;
    var module_name: ?[]u8 = null;
    errdefer {
        if (repo_name) |repo| allocator.free(repo);
        if (module_name) |module| allocator.free(module);
    }

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-d")) {
                dry_run = true;
                continue;
            }
            return error.UnknownLinkFlag;
        }

        if (module_name) |existing_module| {
            repo_name = existing_module;
            module_name = try allocator.dupe(u8, arg);
        } else {
            module_name = try allocator.dupe(u8, arg);
        }
    }

    if (module_name == null) return error.MissingModuleName;

    return Command{ .link = .{
        .repo = repo_name,
        .module = module_name.?,
        .dry_run = dry_run,
    }};
}

fn parseConfigureArgs(arg_iter: *std.process.ArgIterator, allocator: std.mem.Allocator) !Command {
    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);

    while (arg_iter.next()) |arg| try raw_args.append(allocator, arg);
    return parseConfigureArgsSlice(raw_args.items, allocator);
}

fn parseConfigureArgsSlice(args: []const []const u8, allocator: std.mem.Allocator) !Command {
    var dry_run = false;
    var repo_name: ?[]u8 = null;
    var module_name: ?[]u8 = null;
    errdefer {
        if (repo_name) |repo| allocator.free(repo);
        if (module_name) |module| allocator.free(module);
    }

    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-d")) {
                dry_run = true;
                continue;
            }
            return error.ConfigureUnknownFlag;
        }

        if (module_name) |existing_module| {
            repo_name = existing_module;
            module_name = try allocator.dupe(u8, arg);
        } else {
            module_name = try allocator.dupe(u8, arg);
        }
    }

    if (module_name == null) return error.MissingModuleName;

    return Command{ .configure = .{
        .repo = repo_name,
        .module = module_name.?,
        .dry_run = dry_run,
    }};
}

fn printHelp() void {
    log.info("Usage: alma <command> [options]\n", .{});
    log.info("Commands:\n", .{});
    log.info("  link [-d] [repo] <module>           Link a module from an optional repo\n", .{});
    log.info("  install [-d] [repo] <module>        Install a module from an optional repo\n", .{});
    log.info("  configure [-d] [repo] <module>      Configure a module from an optional repo\n", .{});
    log.info("  --help, -h                          Show this help message\n", .{});
    log.info("\nOptions:\n", .{});
    log.info("  -d                                   Dry run - show what would be executed\n", .{});
}