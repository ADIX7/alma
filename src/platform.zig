const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
pub const LinuxOsReleasePath = "/etc/os-release";

pub const PlatformOs = enum {
    windows,
    macos,
    freebsd,
    linux,
    unknown,
};

pub const PlatformIdentifier = struct {
    os: PlatformOs,
    distro: ?[]const u8 = null,
    arch: ?[]const u8 = null,

    pub fn deinit(self: PlatformIdentifier, allocator: Allocator) void {
        if (self.os == .linux) {
            if (self.distro) |distro| allocator.free(distro);
        }
    }

    pub fn detect(allocator: Allocator, linux_os_release_path: []const u8) !PlatformIdentifier {
        const arch = @tagName(builtin.cpu.arch);
        return switch (builtin.os.tag) {
            .windows => .{ .os = .windows, .arch = arch },
            .macos => .{ .os = .macos, .arch = arch },
            .freebsd => .{ .os = .freebsd, .arch = arch },
            .linux => .{ .os = .linux, .distro = try readLinuxDistroId(allocator, linux_os_release_path), .arch = arch },
            else => .{ .os = .unknown },
        };
    }

    pub fn parse(raw: []const u8) !PlatformIdentifier {
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

    pub fn format(self: PlatformIdentifier, allocator: Allocator) ![]u8 {
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

pub const PlatformSelectorKind = enum {
    default,
    unknown,
    os,
    os_arch,
    linux_arch,
    linux_distro,
    linux_distro_arch,
};

pub const PlatformSelector = struct {
    raw: []const u8,
    kind: PlatformSelectorKind,
    os: ?PlatformOs = null,
    distro: ?[]const u8 = null,
    arch: ?[]const u8 = null,

    pub fn parse(raw: []const u8) !PlatformSelector {
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

    pub fn matches(self: PlatformSelector, identifier: PlatformIdentifier) bool {
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

    pub fn specificity(self: PlatformSelector) usize {
        return switch (self.kind) {
            .default => 0,
            .unknown, .os => 1,
            .os_arch, .linux_arch, .linux_distro => 2,
            .linux_distro_arch => 3,
        };
    }
};

pub fn readLinuxDistroId(allocator: Allocator, path: []const u8) !?[]const u8 {
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

test "runtime platform identifier uses linux distro before arch" {
    const allocator = std.testing.allocator;

    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();

    try dir.dir.writeFile(.{ .sub_path = "os-release", .data = "NAME=Ubuntu\nID=ubuntu\n" });
    const path = try dir.dir.realpathAlloc(allocator, "os-release");
    defer allocator.free(path);

    const runtime_platform = PlatformIdentifier{ .os = .linux, .distro = try readLinuxDistroId(allocator, path), .arch = "x86_64" };
    defer runtime_platform.deinit(allocator);

    const identifier = try runtime_platform.format(allocator);
    defer allocator.free(identifier);

    try std.testing.expectEqualStrings("linux-ubuntu-x86_64", identifier);
}

test "windows selectors match os and os arch" {
    const identifier = try PlatformIdentifier.parse("windows-x86_64");

    try std.testing.expect((try PlatformSelector.parse("default")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("windows")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("windows-x86_64")).matches(identifier));
    try std.testing.expect(!(try PlatformSelector.parse("linux")).matches(identifier));
}

test "linux selectors match distro hierarchy" {
    const identifier = try PlatformIdentifier.parse("linux-ubuntu-x86_64");

    try std.testing.expect((try PlatformSelector.parse("default")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("linux")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("linux-ubuntu")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("linux-ubuntu-x86_64")).matches(identifier));
    try std.testing.expect(!(try PlatformSelector.parse("linux-fedora")).matches(identifier));
    try std.testing.expect(!(try PlatformSelector.parse("linux-x86_64")).matches(identifier));
}

test "linux selectors match linux arch when distro unavailable" {
    const identifier = try PlatformIdentifier.parse("linux-x86_64");

    try std.testing.expect((try PlatformSelector.parse("linux")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("linux-x86_64")).matches(identifier));
    try std.testing.expect(!(try PlatformSelector.parse("linux-ubuntu")).matches(identifier));
}

test "segment aware matching rejects non ancestor prefixes" {
    const identifier = try PlatformIdentifier.parse("linux-ubuntu-x86_64");

    try std.testing.expect(!(try PlatformSelector.parse("linux-x86_64")).matches(identifier));
    try std.testing.expect((try PlatformSelector.parse("linux-ubuntu")).matches(identifier));
}

test "invalid selectors fail parsing" {
    try std.testing.expectError(error.InvalidPlatformSelector, PlatformSelector.parse("darwin"));
    try std.testing.expectError(error.InvalidPlatformSelector, PlatformSelector.parse("x86_64-linux"));
}
