const std = @import("std");
const Yaml = @import("yaml").Yaml;
const log = std.log.scoped(.alma);

pub const ModuleContext = struct {
    repo: ?[]u8 = null,
    module: []u8,
    module_path: []u8,

    // pub fn loadConfiguration(module: *const ModuleContext, allocator: std.mem.Allocator) !std.json.Parsed(ModuleConfigurartionRoot) {
    //     var buf: [1024 * 1024]u8 = undefined;
    //     var buf2: [1024 * 1024]u8 = undefined;
    //     const file = try std.fs.cwd().openFile(module.module_path, .{});
    //     var reader = file.reader(&buf);
    //     const read = try reader.interface.readSliceShort(&buf2);
    //     std.debug.print("Read {d} bytes from configuration file\n'{s}'", .{read, buf2[0..read]});
    //     //TODO: make it parse from stream
    //     return std.json.parseFromSlice(ModuleConfigurartionRoot, allocator, buf2[0..read], .{ .ignore_unknown_fields = true });
    // }

    pub fn loadConfiguration(module: *const ModuleContext, allocator: std.mem.Allocator) !*ModuleConfiguration {
        var buf: [1024 * 1024]u8 = undefined;
        var buf2: [1024 * 1024]u8 = undefined;
        const file = try std.fs.cwd().openFile(module.module_path, .{});
        var reader = file.reader(&buf);
        const read = try reader.interface.readSliceShort(&buf2);
        log.debug("Read {d} bytes from configuration file\n'{s}'", .{ read, buf2[0..read] });
        //TODO: make it parse from stream

        var yaml: Yaml = Yaml{ .source = buf2[0..read] };

        try yaml.load(allocator);
        defer yaml.deinit(allocator);

        var arena_alloc = std.heap.ArenaAllocator.init(allocator);
        defer arena_alloc.deinit();
        var arena = arena_alloc.allocator();

        const root = try yaml.parse(arena, ModuleConfigurartionRoot);

        var configurationBuilder: ModuleConfigurationBuilder = .{};

        {
            std.mem.sort(ModuleConfigurationPart, root.platforms, {}, orderPlatform);

            for (root.platforms) |value| {
                // TODO: check if platform is applicable
                if (value.links) |links| {
                    for (links) |link| {
                        try configurationBuilder.links.append(arena, link);
                    }
                }

                if (value.target) |target| {
                    configurationBuilder.target = try arena.dupe(u8, target);
                }

                if (value.install) |install| {
                    configurationBuilder.install = try arena.dupe(u8, install);
                }

                if (value.configure) |configure| {
                    configurationBuilder.configure = try arena.dupe(u8, configure);
                }
            }
        }

        const configuration = try allocator.create(ModuleConfiguration);
        configuration.* = .{
            .allocator = allocator,
            .target = if (configurationBuilder.target) |t| try allocator.dupe(u8, t) else null,
            .links = blk: {
                if (configurationBuilder.links.items.len == 0) break :blk null;
                const links_slice = try allocator.alloc(Link, configurationBuilder.links.items.len);
                for (configurationBuilder.links.items, 0..) |link, i| {
                    links_slice[i] = .{
                        .source = try allocator.dupe(u8, link.source),
                        .target = try allocator.dupe(u8, link.target),
                    };
                }
                break :blk links_slice;
            },
            .install = if (configurationBuilder.install) |install| try allocator.dupe(u8, install) else null,
            .configure = if (configurationBuilder.configure) |configure| try allocator.dupe(u8, configure) else null,
        };
        return configuration;
    }

    fn orderPlatform(_: void, a: ModuleConfigurationPart, b: ModuleConfigurationPart) bool {
        if (std.mem.eql(u8, a.platform, "default")) return true;
        if (std.mem.eql(u8, b.platform, "default")) return false;
        return a.platform.len > b.platform.len;
    }
};

pub const Link = struct {
    source: []u8,
    target: []u8,
};

pub const ModuleConfigurationBuilder = struct {
    target: ?[]u8 = null,
    links: std.ArrayList(Link) = .empty,
    // exclude: ?[][]u8 = null,
    // exclude_readme: bool = false,
    install: ?[]u8 = null,
    configure: ?[]u8 = null,

    pub fn deinit(self: *ModuleConfiguration) void {
        if (self.target) |t| {
            self.allocator.free(t);
        }
    }
};
pub const ModuleConfiguration = struct {
    allocator: std.mem.Allocator,
    target: ?[]u8 = null,
    links: ?[]Link = null,
    // exclude: ?[][]u8 = null,
    // exclude_readme: bool = false,
    install: ?[]u8 = null,
    configure: ?[]u8 = null,

    pub fn deinit(self: *ModuleConfiguration) void {
        if (self.target) |t| {
            self.allocator.free(t);
        }

        if (self.links) |links| {
            for (links) |link| {
                self.allocator.free(link.source);
                self.allocator.free(link.target);
            }
            self.allocator.free(links);
        }

        if (self.install) |install| {
            self.allocator.free(install);
        }

        if (self.configure) |configure| {
            self.allocator.free(configure);
        }
    }
};
pub const ModuleConfigurationPart = struct {
    platform: []u8,
    target: ?[]u8 = null,
    links: ?[]Link = null,
    // exclude: ?[][]u8 = null,
    // exclude_readme: bool = false,
    install: ?[]u8 = null,
    configure: ?[]u8 = null,
};

pub const ModuleConfigurartionRoot = struct {
    platforms: []ModuleConfigurationPart,
};
