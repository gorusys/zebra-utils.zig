const std = @import("std");

pub const Config = struct {
    node: struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 8232,
        username: []const u8 = "",
        password: []const u8 = "",
    } = .{},
    display: struct {
        color: bool = true,
        format: []const u8 = "table",
    } = .{},

    pub fn load(allocator: std.mem.Allocator) !Config {
        const home = std.posix.getenv("HOME") orelse return .{};
        const path = try std.fs.path.join(allocator, &.{ home, ".config", "zebra-utils", "config.toml" });
        defer allocator.free(path);
        return loadFromPath(allocator, path) catch |err| switch (err) {
            error.FileNotFound => .{},
            else => |e| return e,
        };
    }

    pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !Config {
        var f = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => |e| return e,
        };
        defer f.close();
        const data = try f.readToEndAlloc(allocator, 1 << 20);
        defer allocator.free(data);
        return parseToml(allocator, data);
    }
};

fn parseToml(allocator: std.mem.Allocator, source: []const u8) !Config {
    var cfg = Config{};
    var section: enum { none, node, display } = .none;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        var s = std.mem.trim(u8, line, " \t\r");
        if (s.len == 0) continue;
        if (std.mem.startsWith(u8, s, "#")) continue;
        if (std.mem.startsWith(u8, s, "[") and std.mem.endsWith(u8, s, "]")) {
            const name = s[1 .. s.len - 1];
            if (std.mem.eql(u8, name, "node")) {
                section = .node;
            } else if (std.mem.eql(u8, name, "display")) {
                section = .display;
            } else {
                section = .none;
            }
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, s, '=') orelse continue;
        const key = std.mem.trim(u8, s[0..eq], " \t");
        var val = std.mem.trim(u8, s[eq + 1 ..], " \t");
        if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
            val = val[1 .. val.len - 1];
        }
        switch (section) {
            .node => {
                if (std.mem.eql(u8, key, "host")) {
                    cfg.node.host = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "port")) {
                    cfg.node.port = try std.fmt.parseInt(u16, val, 10);
                } else if (std.mem.eql(u8, key, "username")) {
                    cfg.node.username = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "password")) {
                    cfg.node.password = try allocator.dupe(u8, val);
                }
            },
            .display => {
                if (std.mem.eql(u8, key, "color")) {
                    cfg.display.color = std.mem.eql(u8, val, "true");
                } else if (std.mem.eql(u8, key, "format")) {
                    cfg.display.format = try allocator.dupe(u8, val);
                }
            },
            .none => {},
        }
    }
    return cfg;
}

test "parse example" {
    const a = std.testing.allocator;
    const src =
        \\[node]
        \\host = "127.0.0.1"
        \\port = 8232
        \\username = ""
        \\password = ""
        \\
        \\[display]
        \\color = true
        \\format = "table"
    ;
    const c = try parseToml(a, src);
    defer {
        a.free(@constCast(c.node.host));
        a.free(@constCast(c.node.username));
        a.free(@constCast(c.node.password));
        a.free(@constCast(c.display.format));
    }
    try std.testing.expectEqualStrings("127.0.0.1", c.node.host);
    try std.testing.expectEqual(@as(u16, 8232), c.node.port);
    try std.testing.expectEqualStrings("table", c.display.format);
}

test "missing file errors" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.FileNotFound, Config.loadFromPath(a, "/nonexistent/zebra-utils-config-xyz.toml"));
}
