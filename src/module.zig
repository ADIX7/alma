const std = @import("std");
const platform = @import("platform.zig");
const Yaml = @import("yaml").Yaml;
const log = std.log.scoped(.alma);

const Allocator = std.mem.Allocator;
const LinuxOsReleasePath = platform.LinuxOsReleasePath;

pub const ModuleContext = struct {
    repo: ?[]u8 = null,
    module: []u8,
    module_path: []u8,
    platform_identifier: ?[]const u8 = null,
    linux_os_release_path: []const u8 = LinuxOsReleasePath,

    pub fn loadConfiguration(module: *const ModuleContext, allocator: Allocator) !*ModuleConfiguration {
        var buf: [1024 * 1024]u8 = undefined;
        var buf2: [1024 * 1024]u8 = undefined;
        const file = try std.fs.cwd().openFile(module.module_path, .{});
        defer file.close();

        var reader = file.reader(&buf);
        const read = try reader.interface.readSliceShort(&buf2);
        log.debug("Read {d} bytes from configuration file\n'{s}'", .{ read, buf2[0..read] });

        if (module.platform_identifier) |platform_identifier| {
            const active_platform = try platform.PlatformIdentifier.parse(platform_identifier);
            return loadConfigurationFromSource(allocator, buf2[0..read], active_platform);
        }

        const active_platform = try platform.PlatformIdentifier.detect(allocator, module.linux_os_release_path);
        defer active_platform.deinit(allocator);
        return loadConfigurationFromSource(allocator, buf2[0..read], active_platform);
    }
};

pub const Link = struct {
    source: []u8,
    target: []u8,
};

pub const ModuleConfigurationBuilder = struct {
    target: ?[]const u8 = null,
    links: std.ArrayList(Link) = .empty,
    install: ?[]const u8 = null,
    configure: ?[]const u8 = null,

    pub fn deinit(self: *ModuleConfigurationBuilder) void {
        self.links.deinit(std.heap.page_allocator);
    }
};

pub const ModuleConfiguration = struct {
    allocator: Allocator,
    target: ?[]u8 = null,
    links: ?[]Link = null,
    install: ?[]u8 = null,
    configure: ?[]u8 = null,

    pub fn deinit(self: *ModuleConfiguration) void {
        if (self.target) |t| self.allocator.free(t);

        if (self.links) |links| {
            for (links) |link| {
                self.allocator.free(link.source);
                self.allocator.free(link.target);
            }
            self.allocator.free(links);
        }

        if (self.install) |install| self.allocator.free(install);
        if (self.configure) |configure| self.allocator.free(configure);
    }
};

pub const ModuleConfigurationPart = struct {
    platform: []u8,
    target: ?[]u8 = null,
    links: ?[]Link = null,
    install: ?[]u8 = null,
    configure: ?[]u8 = null,
};

pub const ModuleConfigurartionRoot = struct {
    platforms: []ModuleConfigurationPart,
};

const MatchingConfigurationPart = struct {
    part: ModuleConfigurationPart,
    specificity: usize,
};

fn loadConfigurationFromSource(allocator: Allocator, source: []const u8, active_platform: platform.PlatformIdentifier) !*ModuleConfiguration {
    var yaml: Yaml = .{ .source = source };
    try yaml.load(allocator);
    defer yaml.deinit(allocator);

    var arena_alloc = std.heap.ArenaAllocator.init(allocator);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const root = try yaml.parse(arena, ModuleConfigurartionRoot);

    var matching_parts = std.ArrayList(MatchingConfigurationPart).empty;
    defer matching_parts.deinit(arena);

    for (root.platforms) |part| {
        const selector = try platform.PlatformSelector.parse(part.platform);
        if (!selector.matches(active_platform)) continue;
        try matching_parts.append(arena, .{
            .part = part,
            .specificity = selector.specificity(),
        });
    }

    std.mem.sort(MatchingConfigurationPart, matching_parts.items, {}, orderMatchingConfigurationPart);

    var configuration_builder: ModuleConfigurationBuilder = .{};
    defer configuration_builder.links.deinit(arena);

    for (matching_parts.items) |matching_part| {
        const value = matching_part.part;
        if (value.links) |links| {
            for (links) |link| {
                try configuration_builder.links.append(arena, link);
            }
        }

        if (value.target) |target| configuration_builder.target = target;
        if (value.install) |install| configuration_builder.install = install;
        if (value.configure) |configure| configuration_builder.configure = configure;
    }

    const configuration = try allocator.create(ModuleConfiguration);
    configuration.* = .{
        .allocator = allocator,
        .target = if (configuration_builder.target) |target| try allocator.dupe(u8, target) else null,
        .links = blk: {
            if (configuration_builder.links.items.len == 0) break :blk null;
            const links_slice = try allocator.alloc(Link, configuration_builder.links.items.len);
            for (configuration_builder.links.items, 0..) |link, i| {
                links_slice[i] = .{
                    .source = try allocator.dupe(u8, link.source),
                    .target = try allocator.dupe(u8, link.target),
                };
            }
            break :blk links_slice;
        },
        .install = if (configuration_builder.install) |install| try allocator.dupe(u8, install) else null,
        .configure = if (configuration_builder.configure) |configure| try allocator.dupe(u8, configure) else null,
    };
    return configuration;
}

fn orderMatchingConfigurationPart(_: void, a: MatchingConfigurationPart, b: MatchingConfigurationPart) bool {
    if (a.specificity != b.specificity) return a.specificity < b.specificity;
    return a.part.platform.len < b.part.platform.len;
}

fn expectLoadedConfiguration(source: []const u8, platform_identifier: []const u8) !*ModuleConfiguration {
    return loadConfigurationFromSource(std.testing.allocator, source, try platform.PlatformIdentifier.parse(platform_identifier));
}

test "windows configuration merges matching selectors" {
    const configuration = try expectLoadedConfiguration(
        \\platforms:
        \\  - platform: default
        \\    target: default-target
        \\  - platform: windows
        \\    target: windows-target
        \\  - platform: windows-x86_64
        \\    install: win-install
        \\  - platform: linux
        \\    configure: linux-configure
    , "windows-x86_64");
    defer std.testing.allocator.destroy(configuration);
    defer configuration.deinit();

    try std.testing.expectEqualStrings("windows-target", configuration.target.?);
    try std.testing.expectEqualStrings("win-install", configuration.install.?);
    try std.testing.expect(configuration.configure == null);
}

test "linux configuration merges distro hierarchy" {
    const configuration = try expectLoadedConfiguration(
        \\platforms:
        \\  - platform: default
        \\    target: default-target
        \\    links:
        \\      - source: default-source
        \\        target: default-target-link
        \\  - platform: linux
        \\    target: linux-target
        \\  - platform: linux-ubuntu
        \\    install: ubuntu-install
        \\  - platform: linux-ubuntu-x86_64
        \\    configure: ubuntu-configure
        \\    links:
        \\      - source: ubuntu-source
        \\        target: ubuntu-target-link
        \\  - platform: linux-fedora
        \\    install: fedora-install
        \\  - platform: linux-x86_64
        \\    configure: linux-arch-configure
    , "linux-ubuntu-x86_64");
    defer std.testing.allocator.destroy(configuration);
    defer configuration.deinit();

    try std.testing.expectEqualStrings("linux-target", configuration.target.?);
    try std.testing.expectEqualStrings("ubuntu-install", configuration.install.?);
    try std.testing.expectEqualStrings("ubuntu-configure", configuration.configure.?);
    try std.testing.expectEqual(@as(usize, 2), configuration.links.?.len);
    try std.testing.expectEqualStrings("default-source", configuration.links.?[0].source);
    try std.testing.expectEqualStrings("ubuntu-source", configuration.links.?[1].source);
}

test "linux configuration matches linux arch when distro unavailable" {
    const configuration = try expectLoadedConfiguration(
        \\platforms:
        \\  - platform: default
        \\    target: default-target
        \\  - platform: linux
        \\    target: linux-target
        \\  - platform: linux-x86_64
        \\    install: linux-arch-install
        \\  - platform: linux-ubuntu
        \\    configure: ubuntu-configure
    , "linux-x86_64");
    defer std.testing.allocator.destroy(configuration);
    defer configuration.deinit();

    try std.testing.expectEqualStrings("linux-target", configuration.target.?);
    try std.testing.expectEqualStrings("linux-arch-install", configuration.install.?);
    try std.testing.expect(configuration.configure == null);
}

test "configuration loading rejects invalid selectors" {
    try std.testing.expectError(error.InvalidPlatformSelector, expectLoadedConfiguration(
        \\platforms:
        \\  - platform: darwin
        \\    target: bad
    , "macos-aarch64"));

    try std.testing.expectError(error.InvalidPlatformSelector, expectLoadedConfiguration(
        \\platforms:
        \\  - platform: x86_64-linux
        \\    target: bad
    , "linux-ubuntu-x86_64"));
}
