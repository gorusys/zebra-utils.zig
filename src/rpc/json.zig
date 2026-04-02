const std = @import("std");

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: []Value,
    object: []Field,

    pub const Field = struct {
        key: []const u8,
        value: Value,
    };

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(@constCast(s)),
            .array => |a| {
                for (a) |v| v.deinit(allocator);
                allocator.free(a);
            },
            .object => |o| {
                for (o) |f| {
                    allocator.free(@constCast(f.key));
                    f.value.deinit(allocator);
                }
                allocator.free(o);
            },
            else => {},
        }
    }

    pub fn get(self: Value, key: []const u8) ?Value {
        const obj = switch (self) {
            .object => |o| o,
            else => return null,
        };
        for (obj) |field| {
            if (std.mem.eql(u8, field.key, key)) return field.value;
        }
        return null;
    }

    pub fn at(self: Value, idx: usize) ?Value {
        const arr = switch (self) {
            .array => |a| a,
            else => return null,
        };
        if (idx >= arr.len) return null;
        return arr[idx];
    }

    pub fn asString(self: Value) error{NotAString}![]const u8 {
        return switch (self) {
            .string => |s| s,
            else => error.NotAString,
        };
    }

    pub fn asInt(self: Value) error{NotAnInt}!i64 {
        return switch (self) {
            .int => |n| n,
            else => error.NotAnInt,
        };
    }

    pub fn asBool(self: Value) error{NotABool}!bool {
        return switch (self) {
            .bool => |b| b,
            else => error.NotABool,
        };
    }

    pub fn eql(self: Value, other: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .null => true,
            .bool => |b| b == other.bool,
            .int => |n| n == other.int,
            .float => |f| f == other.float,
            .string => |s| std.mem.eql(u8, s, other.string),
            .array => |a| {
                const b = other.array;
                if (a.len != b.len) return false;
                for (a, b) |x, y| {
                    if (!x.eql(y)) return false;
                }
                return true;
            },
            .object => |a| {
                const ob = other.object;
                if (a.len != ob.len) return false;
                for (a) |f| {
                    const ov = other.get(f.key) orelse return false;
                    if (!f.value.eql(ov)) return false;
                }
                return true;
            },
        };
    }
};

pub const ParseError = error{
    UnexpectedChar,
    UnexpectedEnd,
    InvalidNumber,
    InvalidString,
    InvalidLiteral,
    TooDeep,
    OutOfMemory,
};

const max_depth = 32;

pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!Value {
    var p = Parser{ .input = input, .i = 0 };
    p.skipWs();
    const v = try p.parseValue(allocator, 0);
    p.skipWs();
    if (p.i != input.len) return error.UnexpectedChar;
    return v;
}

const Parser = struct {
    input: []const u8,
    i: usize,

    fn peek(self: Parser) ?u8 {
        if (self.i >= self.input.len) return null;
        return self.input[self.i];
    }

    fn bump(self: *Parser) void {
        self.i += 1;
    }

    fn skipWs(self: *Parser) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t', '\r', '\n' => self.bump(),
                else => return,
            }
        }
    }

    fn parseValue(self: *Parser, allocator: std.mem.Allocator, depth: usize) ParseError!Value {
        if (depth > max_depth) return error.TooDeep;
        self.skipWs();
        const c = self.peek() orelse return error.UnexpectedEnd;
        switch (c) {
            'n' => return try self.parseLiteral("null", .null),
            't' => return try self.parseLiteral("true", .{ .bool = true }),
            'f' => return try self.parseLiteral("false", .{ .bool = false }),
            '"' => return .{ .string = try self.parseStringContent(allocator) },
            '[' => return try self.parseArray(allocator, depth),
            '{' => return try self.parseObject(allocator, depth),
            '-', '0'...'9' => {
                const num = try self.parseNumber();
                return switch (num) {
                    .int => |n| .{ .int = n },
                    .float => |f| .{ .float = f },
                };
            },
            else => return error.UnexpectedChar,
        }
    }

    fn parseLiteral(self: *Parser, expected: []const u8, result: Value) ParseError!Value {
        if (self.i + expected.len > self.input.len) return error.UnexpectedEnd;
        if (!std.mem.eql(u8, self.input[self.i..][0..expected.len], expected)) return error.InvalidLiteral;
        self.i += expected.len;
        return result;
    }

    /// Reads string value after opening " already consumed... actually we consume " here
    fn parseStringContent(self: *Parser, allocator: std.mem.Allocator) ParseError![]const u8 {
        if (self.peek() != '"') return error.InvalidString;
        self.bump();
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        while (true) {
            const c = self.peek() orelse return error.InvalidString;
            if (c == '"') {
                self.bump();
                return try out.toOwnedSlice();
            }
            if (c == '\\') {
                self.bump();
                const esc = self.peek() orelse return error.InvalidString;
                if (esc == '"') {
                    self.bump();
                    try out.append('"');
                } else {
                    return error.InvalidString;
                }
            } else {
                self.bump();
                try out.append(c);
            }
        }
    }

    fn parseArray(self: *Parser, allocator: std.mem.Allocator, depth: usize) ParseError!Value {
        if (self.peek() != '[') return error.UnexpectedChar;
        self.bump();
        self.skipWs();
        var list = std.ArrayList(Value).init(allocator);
        errdefer {
            for (list.items) |v| v.deinit(allocator);
            list.deinit();
        }
        if (self.peek() == ']') {
            self.bump();
            return .{ .array = try list.toOwnedSlice() };
        }
        while (true) {
            const elem = try self.parseValue(allocator, depth + 1);
            try list.append(elem);
            self.skipWs();
            const sep = self.peek() orelse return error.UnexpectedEnd;
            if (sep == ']') {
                self.bump();
                break;
            }
            if (sep != ',') return error.UnexpectedChar;
            self.bump();
            self.skipWs();
        }
        return .{ .array = try list.toOwnedSlice() };
    }

    fn parseObject(self: *Parser, allocator: std.mem.Allocator, depth: usize) ParseError!Value {
        if (self.peek() != '{') return error.UnexpectedChar;
        self.bump();
        self.skipWs();
        var list = std.ArrayList(Value.Field).init(allocator);
        errdefer {
            for (list.items) |f| {
                allocator.free(@constCast(f.key));
                f.value.deinit(allocator);
            }
            list.deinit();
        }
        if (self.peek() == '}') {
            self.bump();
            return .{ .object = try list.toOwnedSlice() };
        }
        while (true) {
            self.skipWs();
            const key = try self.parseStringContent(allocator);
            self.skipWs();
            if (self.peek() != ':') return error.UnexpectedChar;
            self.bump();
            self.skipWs();
            const val = try self.parseValue(allocator, depth + 1);
            try list.append(.{ .key = key, .value = val });
            self.skipWs();
            const sep = self.peek() orelse return error.UnexpectedEnd;
            if (sep == '}') {
                self.bump();
                break;
            }
            if (sep != ',') return error.UnexpectedChar;
            self.bump();
        }
        return .{ .object = try list.toOwnedSlice() };
    }

    const Num = union(enum) {
        int: i64,
        float: f64,
    };

    fn parseNumber(self: *Parser) ParseError!Num {
        const start = self.i;
        if (self.peek() == '-') self.bump();
        if (self.peek() == '0') {
            self.bump();
        } else {
            const d = self.peek() orelse return error.InvalidNumber;
            if (d < '1' or d > '9') return error.InvalidNumber;
            while (self.peek()) |c| {
                if (c < '0' or c > '9') break;
                self.bump();
            }
        }
        var is_float = false;
        if (self.peek() == '.') {
            is_float = true;
            self.bump();
            const fd = self.peek() orelse return error.InvalidNumber;
            if (fd < '0' or fd > '9') return error.InvalidNumber;
            while (self.peek()) |c| {
                if (c < '0' or c > '9') break;
                self.bump();
            }
        }
        if (self.peek()) |c| {
            if (c == 'e' or c == 'E') {
                is_float = true;
                self.bump();
                if (self.peek()) |s| {
                    if (s == '+' or s == '-') self.bump();
                }
                while (self.peek()) |c2| {
                    if (c2 < '0' or c2 > '9') break;
                    self.bump();
                }
            }
        }
        const slice = self.input[start..self.i];
        if (is_float) {
            const f = std.fmt.parseFloat(f64, slice) catch return error.InvalidNumber;
            return .{ .float = f };
        }
        const n = std.fmt.parseInt(i64, slice, 10) catch return error.InvalidNumber;
        return .{ .int = n };
    }
};

pub fn stringify(value: Value, writer: anytype) @TypeOf(writer).Error!void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .int => |n| try std.fmt.format(writer, "{d}", .{n}),
        .float => |f| try std.fmt.format(writer, "{any}", .{f}),
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| {
                if (c == '"') try writer.writeAll("\\\"") else try writer.writeByte(c);
            }
            try writer.writeByte('"');
        },
        .array => |a| {
            try writer.writeByte('[');
            for (a, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try stringify(item, writer);
            }
            try writer.writeByte(']');
        },
        .object => |o| {
            try writer.writeByte('{');
            for (o, 0..) |field, i| {
                if (i > 0) try writer.writeByte(',');
                try stringify(.{ .string = field.key }, writer);
                try writer.writeByte(':');
                try stringify(field.value, writer);
            }
            try writer.writeByte('}');
        },
    }
}

test "null true false" {
    const a = std.testing.allocator;
    var v = try parse(a, "null");
    defer v.deinit(a);
    try std.testing.expectEqual(@as(std.meta.Tag(Value), .null), std.meta.activeTag(v));

    var v2 = try parse(a, " true ");
    defer v2.deinit(a);
    try std.testing.expectEqual(true, try v2.asBool());

    var v3 = try parse(a, "false");
    defer v3.deinit(a);
    try std.testing.expectEqual(false, try v3.asBool());
}

test "int and float" {
    const a = std.testing.allocator;
    var v = try parse(a, "42");
    defer v.deinit(a);
    try std.testing.expectEqual(@as(i64, 42), try v.asInt());

    var v2 = try parse(a, "3.14");
    defer v2.deinit(a);
    try std.testing.expectEqual(@as(f64, 3.14), v2.float);
}

test "string escaped quote" {
    const a = std.testing.allocator;
    var v = try parse(a, "\"foo\\\"bar\"");
    defer v.deinit(a);
    try std.testing.expectEqualStrings("foo\"bar", try v.asString());
}

test "nested object" {
    const a = std.testing.allocator;
    var v = try parse(a, "{\"a\":{\"b\":1}}");
    defer v.deinit(a);
    const inner = v.get("a").?;
    try std.testing.expectEqual(@as(i64, 1), (inner.get("b").?).int);
}

test "mixed array" {
    const a = std.testing.allocator;
    var v = try parse(a, "[1,\"x\",true]");
    defer v.deinit(a);
    try std.testing.expectEqual(@as(i64, 1), (v.at(0).?).int);
    try std.testing.expectEqualStrings("x", (v.at(1).?).string);
    try std.testing.expectEqual(true, (v.at(2).?).bool);
}

test "get at" {
    const a = std.testing.allocator;
    var v = try parse(a, "{\"k\":\"v\"}");
    defer v.deinit(a);
    try std.testing.expectEqualStrings("v", (v.get("k").?).string);
}

test "round-trip" {
    const a = std.testing.allocator;
    var v = try parse(a, "{\"x\":[1,2],\"y\":null}");
    defer v.deinit(a);
    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    try stringify(v, buf.writer());
    var v2 = try parse(a, buf.items);
    defer v2.deinit(a);
    try std.testing.expect(v.eql(v2));
}

test "unterminated string" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidString, parse(a, "\"abc"));
}

test "unexpected char" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.UnexpectedChar, parse(a, "xyz"));
}
