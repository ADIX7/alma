const std = @import("std");

pub const ModuleContext = struct {
    repo: ?[]u8 = null,
    module: []u8,
    module_path: []u8,

    pub fn loadConfiguration(module: *const ModuleContext, allocator: std.mem.Allocator) !std.json.Parsed(ModuleConfigurartionRoot) {
        var buf: [1024 * 1024]u8 = undefined;
        var buf2: [1024 * 1024]u8 = undefined;
        const file = try std.fs.cwd().openFile(module.module_path, .{});
        var reader = file.reader(&buf);
        const read = try reader.interface.readSliceShort(&buf2);
        std.debug.print("Read {d} bytes from configuration file\n'{s}'", .{read, buf2[0..read]});
        //TODO: make it parse from stream
        return std.json.parseFromSlice(ModuleConfigurartionRoot, allocator, buf2[0..read], .{ .ignore_unknown_fields = true });
    }
};

pub const ModuleConfigurartion = struct {
    // target: ?[]u8 = null,
    // links: ?[]struct { []u8, []u8 } = null,
    // exclude: ?[][]u8 = null,
    // exclude_readme: bool = false,
    // install: ?[]u8 = null,
    // configure: ?[]u8 = null,
};

pub const ModuleConfigurartionRoot = []struct { []u8, ModuleConfigurartion };
