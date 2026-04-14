const std = @import("std");

pub const InstallPayload = struct {
    repo: ?[]u8,
    module: []u8,
};

pub const LinkPayload = struct {

    repo: ?[]u8,
    module: []u8,
    dry_run: bool,
};

pub const ConfigurePayload = struct {
    repo: ?[]u8,
    module: []u8,
};

pub const Command = union(enum) {
    unsupported: []u8,
    help,
    link: LinkPayload,
    install: InstallPayload,
    configure: ConfigurePayload,

    pub fn deinit(self: Command, allocator: std.mem.Allocator) void {
        switch (self) {
            Command.unsupported => |cmd| {
                allocator.free(cmd);
            },
            Command.help => {},
            Command.link => |cmd| {
                if (cmd.repo) |r| allocator.free(r);
                allocator.free(cmd.module);
            },
            Command.install => |cmd| {
                if (cmd.repo) |r| allocator.free(r);
                allocator.free(cmd.module);
            },
            Command.configure => |cmd| {
                if (cmd.repo) |r| allocator.free(r);
                allocator.free(cmd.module);
            },
        }
    }
};
