const builtin = @import("builtin");
const std = @import("std");
const Yaml = @import("yaml").Yaml;
const log = std.log.scoped(.alma);

const Allocator = std.mem.Allocator;
const LinuxOsReleasePath = "/etc/os-release";

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

        const active_platform = if (module.platform_identifier) |platform_identifier|
            try PlatformIdentifier.parse(platform_identifier)
        else
            try PlatformIdentifier.detect(allocator, module.linux_os_release_path);

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

const PlatformOs = enum {
    windows,
    macos,
    freebsd,
    linux,
    unknown,
};

const PlatformIdentifier = struct {
    os: PlatformOs,
    distro: ?[]const u8 = null,
    arch: ?[]const u8 = null,

    fn detect(allocator: Allocator, linux_os_release_path: []const u8) !PlatformIdentifier {
        const arch = @tagName(builtin.cpu.arch);
        return switch (builtin.os.tag) {
            .windows => .{ .os = .windows, .arch = arch },
            .macos => .{ .os = .macos, .arch = arch },
            .freebsd => .{ .os = .freebsd, .arch = arch },
            .linux => .{ .os = .linux, .distro = try readLinuxDistroId(allocator, linux_os_release_path), .arch = arch },
            else => .{ .os = .unknown },
        };
    }

    fn parse(raw: []const u8) !PlatformIdentifier {
        if (std.mem.eql(u8, raw, "unknown")) return .{ .os = .unknown };
        if (raw.len == 0 or raw[0] == '-' or raw[raw.len - 1] == '-' or std.mem.indexOf(u8, raw, "--") != null) {
            return error.InvalidPlatformIdentifier;
        }

        const first_sep = std.mem.indexOfScalar(u8, raw, '-') orelse return error.InvalidPlatformIdentifier;
        const os_name = raw[0..first_sep];
        const rest = raw[first_sep + 1 ..];
        const os = parseOsName(os_name) orelse return error.InvalidPlatformIdentifier;

        switch (os) {
            .windows, .macos, .freebsd => {
                if (!isKnownArch(rest)) return error.InvalidPlatformIdentifier;
                return .{ .os = os, .arch = rest };
            },
            .linux => {
                const last_sep = std.mem.lastIndexOfScalar(u8, rest, '-') orelse {
                    if (!isKnownArch(rest)) return error.InvalidPlatformIdentifier;
                    return .{ .os = .linux, .arch = rest };
                };
                const distro = rest[0..last_sep];
                const arch = rest[last_sep + 1 ..];
                if (!isValidDistroValue(distro) or !isKnownArch(arch)) return error.InvalidPlatformIdentifier;
                return .{ .os = .linux, .distro = distro, .arch = arch };
            },
            .unknown => return error.InvalidPlatformIdentifier,
        }
    }

    fn format(self: PlatformIdentifier, allocator: Allocator) ![]u8 {
        return switch (self.os) {
            .unknown => allocator.dupe(u8, "unknown"),
            .linux => if (self.distro) |distro|
                std.fmt.allocPrint(allocator, "linux-{s}-{s}", .{ distro, self.arch.? })
            else
                std.fmt.allocPrint(allocator, "linux-{s}", .{self.arch.?}),
            .windows, .macos, .freebsd => std.fmt.allocPrint(allocator, "{s}-{s}", .{ @tagName(self.os), self.arch.? }),
        };
    }
};

const PlatformSelectorKind = enum {
    default,
    unknown,
    os,
    os_arch,
    linux_arch,
    linux_distro,
    linux_distro_arch,
};

const PlatformSelector = struct {
    raw: []const u8,
    kind: PlatformSelectorKind,
    os: ?PlatformOs = null,
    distro: ?[]const u8 = null,
    arch: ?[]const u8 = null,

    fn parse(raw: []const u8) !PlatformSelector {
        if (std.mem.eql(u8, raw, "default")) {
            return .{ .raw = raw, .kind = .default };
        }
        if (std.mem.eql(u8, raw, "unknown")) {
            return .{ .raw = raw, .kind = .unknown, .os = .unknown };
        }
        if (raw.len == 0 or raw[0] == '-' or raw[raw.len - 1] == '-' or std.mem.indexOf(u8, raw, "--") != null) {
            return error.InvalidPlatformSelector;
        }

        const first_sep = std.mem.indexOfScalar(u8, raw, '-') orelse {
            const os = parseOsName(raw) orelse return error.InvalidPlatformSelector;
            if (os == .unknown) return error.InvalidPlatformSelector;
            return .{ .raw = raw, .kind = .os, .os = os };
        };

        const os_name = raw[0..first_sep];
        const rest = raw[first_sep + 1 ..];
        const os = parseOsName(os_name) orelse return error.InvalidPlatformSelector;

        switch (os) {
            .windows, .macos, .freebsd => {
                if (!isKnownArch(rest)) return error.InvalidPlatformSelector;
                return .{ .raw = raw, .kind = .os_arch, .os = os, .arch = rest };
            },
            .linux => {
                const last_sep = std.mem.lastIndexOfScalar(u8, rest, '-') orelse {
                    if (isKnownArch(rest)) {
                        return .{ .raw = raw, .kind = .linux_arch, .os = .linux, .arch = rest };
                    }
                    if (!isValidDistroValue(rest)) return error.InvalidPlatformSelector;
                    return .{ .raw = raw, .kind = .linux_distro, .os = .linux, .distro = rest };
                };
                const distro = rest[0..last_sep];
                const arch = rest[last_sep + 1 ..];
                if (!isValidDistroValue(distro) or !isKnownArch(arch)) return error.InvalidPlatformSelector;
                return .{ .raw = raw, .kind = .linux_distro_arch, .os = .linux, .distro = distro, .arch = arch };
            },
            .unknown => return error.InvalidPlatformSelector,
        }
    }

    fn matches(self: PlatformSelector, identifier: PlatformIdentifier) bool {
        return switch (self.kind) {
            .default => true,
            .unknown => identifier.os == .unknown,
            .os => self.os.? == identifier.os,
            .os_arch => self.os.? == identifier.os and std.mem.eql(u8, self.arch.?, identifier.arch orelse return false),
            .linux_arch => identifier.os == .linux and identifier.distro == null and std.mem.eql(u8, self.arch.?, identifier.arch orelse return false),
            .linux_distro => identifier.os == .linux and identifier.distro != null and std.mem.eql(u8, self.distro.?, identifier.distro.?),
            .linux_distro_arch => identifier.os == .linux and identifier.distro != null and std.mem.eql(u8, self.distro.?, identifier.distro.?) and std.mem.eql(u8, self.arch.?, identifier.arch orelse return false),
        };
    }

    fn specificity(self: PlatformSelector) usize {
        return switch (self.kind) {
            .default => 0,
            .unknown, .os => 1,
            .os_arch, .linux_arch, .linux_distro => 2,
            .linux_distro_arch => 3,
        };
    }
};

const MatchingConfigurationPart = struct {
    part: ModuleConfigurationPart,
    specificity: usize,
};

fn loadConfigurationFromSource(allocator: Allocator, source: []const u8, active_platform: PlatformIdentifier) !*ModuleConfiguration {
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
        const selector = try PlatformSelector.parse(part.platform);
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

fn parseOsName(value: []const u8) ?PlatformOs {
    if (std.mem.eql(u8, value, "windows")) return .windows;
    if (std.mem.eql(u8, value, "macos")) return .macos;
    if (std.mem.eql(u8, value, "freebsd")) return .freebsd;
    if (std.mem.eql(u8, value, "linux")) return .linux;
    if (std.mem.eql(u8, value, "unknown")) return .unknown;
    return null;
}

fn isKnownArch(value: []const u8) bool {
    return std.meta.stringToEnum(std.Target.Cpu.Arch, value) != null;
}

fn isValidDistroValue(value: []const u8) bool {
    if (value.len == 0 or value[0] == '-' or value[value.len - 1] == '-' or std.mem.indexOf(u8, value, "--") != null) {
        return false;
    }

    for (value) |char| {
        if (std.ascii.isLower(char) or std.ascii.isDigit(char) or char == '-' or char == '_' or char == '.') continue;
        return false;
    }
    return true;
}

fn readLinuxDistroId(allocator: Allocator, path: []const u8) !?[]const u8 {
    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "ID=")) continue;

        var id = trimmed[3..];
        if (id.len >= 2 and id[0] == '"' and id[id.len - 1] == '"') {
            id = id[1 .. id.len - 1];
        }
        const lower = try std.ascii.allocLowerString(allocator, id);
        errdefer allocator.free(lower);
        if (!isValidDistroValue(lower)) {
            allocator.free(lower);
            return null;
        }
        return lower;
    }

    return null;
}

fn expectLoadedConfiguration(source: []const u8, platform_identifier: []const u8) !*ModuleConfiguration {
    return loadConfigurationFromSource(std.testing.allocator, source, try PlatformIdentifier.parse(platform_identifier));
}

test "runtime platform identifier uses linux distro before arch" {
    const allocator = std.testing.allocator;

    const dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.writeFile(.{ .sub_path = "os-release", .data = "NAME=Ubuntu\nID=ubuntu\n" });
    const path = try dir.dir.realpathAlloc(allocator, "os-release");
    defer allocator.free(path);

    const identifier = try (PlatformIdentifier{ .os = .linux, .distro = try readLinuxDistroId(allocator, path), .arch = "x86_64" }).format(allocator);
    defer allocator.free(identifier);

    try std.testing.expectEqualStrings("linux-ubuntu-x86_64", identifier);
}

test "windows selectors match os and os arch" {
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

test "linux selectors match distro hierarchy" {
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

test "linux selectors match linux arch when distro unavailable" {
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

test "segment aware matching rejects non ancestor prefixes" {
    const configuration = try expectLoadedConfiguration(
        \\platforms:
        \\  - platform: default
        \\    target: default-target
        \\  - platform: linux-x86_64
        \\    target: wrong-target
        \\  - platform: linux-ubuntu
        \\    target: ubuntu-target
    , "linux-ubuntu-x86_64");
    defer std.testing.allocator.destroy(configuration);
    defer configuration.deinit();

    try std.testing.expectEqualStrings("ubuntu-target", configuration.target.?);
}

test "invalid selectors fail configuration loading" {
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
