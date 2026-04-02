const std = @import("std");
const json = @import("json.zig");

pub const Config = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8232,
    username: []const u8 = "",
    password: []const u8 = "",
    timeout_ms: u32 = 10_000,
};

pub const RpcError = error{
    ConnectionFailed,
    SendFailed,
    RecvFailed,
    HttpError,
    JsonRpcError,
    ParseError,
    OutOfMemory,
    Timeout,
};

pub const Client = struct {
    config: Config,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: Config) Client {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn call(
        self: *Client,
        allocator: std.mem.Allocator,
        method: []const u8,
        params: []const u8,
    ) RpcError!json.Value {
        const id = nextId();
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        try body.writer().print(
            \\{{"jsonrpc":"2.0","id":{d},"method":"{s}","params":{s}}}
        , .{ id, method, params });
        const body_slice = try body.toOwnedSlice();
        defer self.allocator.free(body_slice);

        var req = std.ArrayList(u8).init(self.allocator);
        defer req.deinit();
        const w = req.writer();
        const host_port = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ self.config.host, self.config.port });
        defer self.allocator.free(host_port);

        try w.print("POST / HTTP/1.1\r\n", .{});
        try w.print("Host: {s}\r\n", .{host_port});
        try w.print("Content-Type: application/json\r\n", .{});
        if (self.config.username.len > 0 or self.config.password.len > 0) {
            const userpass = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ self.config.username, self.config.password });
            defer self.allocator.free(userpass);
            var enc_buf: [512]u8 = undefined;
            const b64 = base64Encode(userpass, &enc_buf);
            try w.print("Authorization: Basic {s}\r\n", .{b64});
        }
        try w.print("Content-Length: {d}\r\n", .{body_slice.len});
        try w.print("\r\n", .{});
        try w.writeAll(body_slice);

        const addr = std.net.Address.resolveIp(self.config.host, self.config.port) catch return error.ConnectionFailed;
        var stream = std.net.tcpConnectToAddress(addr) catch return error.ConnectionFailed;
        defer stream.close();

        stream.writeAll(req.items) catch return error.SendFailed;

        const resp_text = readHttpBody(self.allocator, stream, self.config.timeout_ms) catch |err| switch (err) {
            error.Timeout => return error.Timeout,
            error.HttpError => return error.HttpError,
            error.RecvFailed => return error.RecvFailed,
            else => return error.RecvFailed,
        };
        defer self.allocator.free(resp_text);

        var parsed = json.parse(allocator, resp_text) catch return error.ParseError;
        errdefer parsed.deinit(allocator);

        if (parsed.get("error")) |_| {
            return error.JsonRpcError;
        }
        const result = parsed.get("result") orelse return error.ParseError;
        const out = cloneValue(allocator, result) catch return error.OutOfMemory;
        parsed.deinit(allocator);
        return out;
    }

    pub fn batchCall(
        self: *Client,
        allocator: std.mem.Allocator,
        calls: []const struct { method: []const u8, params: []const u8 },
    ) RpcError![]json.Value {
        const out = try allocator.alloc(json.Value, calls.len);
        errdefer {
            for (out) |v| v.deinit(allocator);
            allocator.free(out);
        }
        for (calls, 0..) |c, i| {
            out[i] = try self.call(allocator, c.method, c.params);
        }
        return out;
    }
};

fn cloneValue(allocator: std.mem.Allocator, v: json.Value) !json.Value {
    return switch (v) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .int => |n| .{ .int = n },
        .float => |f| .{ .float = f },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |a| {
            const out = try allocator.alloc(json.Value, a.len);
            var i: usize = 0;
            errdefer {
                for (out[0..i]) |val| val.deinit(allocator);
                allocator.free(out);
            }
            for (a) |item| {
                out[i] = try cloneValue(allocator, item);
                i += 1;
            }
            return .{ .array = out };
        },
        .object => |o| {
            const out = try allocator.alloc(json.Value.Field, o.len);
            var j: usize = 0;
            errdefer {
                for (out[0..j]) |f| {
                    allocator.free(@constCast(f.key));
                    f.value.deinit(allocator);
                }
                allocator.free(out);
            }
            for (o) |f| {
                out[j] = .{
                    .key = try allocator.dupe(u8, f.key),
                    .value = try cloneValue(allocator, f.value),
                };
                j += 1;
            }
            return .{ .object = out };
        },
    };
}

var request_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

fn nextId() u32 {
    return request_id.fetchAdd(1, .monotonic);
}

pub fn base64Encode(input: []const u8, out: []u8) []const u8 {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var out_idx: usize = 0;
    var i: usize = 0;
    while (i + 3 <= input.len) : (i += 3) {
        const b0 = input[i];
        const b1 = input[i + 1];
        const b2 = input[i + 2];
        out[out_idx] = alphabet[(b0 >> 2) & 0x3f];
        out[out_idx + 1] = alphabet[((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0f)];
        out[out_idx + 2] = alphabet[((b1 & 0x0f) << 2) | ((b2 >> 6) & 0x03)];
        out[out_idx + 3] = alphabet[b2 & 0x3f];
        out_idx += 4;
    }
    const rem = input.len - i;
    if (rem == 1) {
        const b0 = input[i];
        out[out_idx] = alphabet[(b0 >> 2) & 0x3f];
        out[out_idx + 1] = alphabet[(b0 & 0x03) << 4];
        out[out_idx + 2] = '=';
        out[out_idx + 3] = '=';
        out_idx += 4;
    } else if (rem == 2) {
        const b0 = input[i];
        const b1 = input[i + 1];
        out[out_idx] = alphabet[(b0 >> 2) & 0x3f];
        out[out_idx + 1] = alphabet[((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0f)];
        out[out_idx + 2] = alphabet[(b1 & 0x0f) << 2];
        out[out_idx + 3] = '=';
        out_idx += 4;
    }
    return out[0..out_idx];
}

fn readWithTimeout(stream: std.net.Stream, buf: []u8, timeout_ms: u32) !usize {
    var pfd = [_]std.posix.pollfd{.{
        .fd = stream.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const cap: u32 = @intCast(std.math.maxInt(i32));
    const to: i32 = @intCast(@min(timeout_ms, cap));
    const pr = try std.posix.poll(&pfd, to);
    if (pr == 0) return error.Timeout;
    return stream.read(buf);
}

fn readHttpBody(allocator: std.mem.Allocator, stream: std.net.Stream, timeout_ms: u32) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = try readWithTimeout(stream, &tmp, timeout_ms);
        if (n == 0) return error.RecvFailed;
        try buf.appendSlice(tmp[0..n]);
        if (std.mem.indexOf(u8, buf.items, "\r\n\r\n")) |sep_idx| {
            const header_end = sep_idx + 4;
            var content_len: ?usize = null;
            var it = std.mem.splitScalar(u8, buf.items[0..sep_idx], '\n');
            while (it.next()) |line| {
                const L = std.mem.trimRight(u8, line, "\r");
                if (L.len >= 15 and std.ascii.eqlIgnoreCase(L[0..15], "Content-Length:")) {
                    const rest = std.mem.trim(u8, L[15..], " \t");
                    content_len = std.fmt.parseInt(usize, rest, 10) catch null;
                }
            }
            const cl = content_len orelse return error.HttpError;
            const total_needed = header_end + cl;
            while (buf.items.len < total_needed) {
                const r = try readWithTimeout(stream, &tmp, timeout_ms);
                if (r == 0) return error.RecvFailed;
                try buf.appendSlice(tmp[0..r]);
            }
            return try allocator.dupe(u8, buf.items[header_end..total_needed]);
        }
        if (buf.items.len > 1 << 20) return error.HttpError;
    }
}

test "base64" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("", base64Encode("", &buf));
    try std.testing.expectEqualStrings("Zg==", base64Encode("f", &buf));
    try std.testing.expectEqualStrings("Zm9vYmFy", base64Encode("foobar", &buf));
}

test "http body from buffer" {
    const a = std.testing.allocator;
    const raw = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}";
    const body = try parseHttpBodySlice(a, raw);
    defer a.free(body);
    try std.testing.expectEqualStrings("{}", body);
}

fn parseHttpBodySlice(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const idx = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.HttpError;
    const header_end = idx + 4;
    var content_len: ?usize = null;
    var it = std.mem.splitScalar(u8, raw[0..idx], '\n');
    while (it.next()) |line| {
        const L = std.mem.trimRight(u8, line, "\r");
        if (L.len >= 15 and std.ascii.eqlIgnoreCase(L[0..15], "Content-Length:")) {
            const rest = std.mem.trim(u8, L[15..], " \t");
            content_len = try std.fmt.parseInt(usize, rest, 10);
        }
    }
    const cl = content_len orelse return error.HttpError;
    return try allocator.dupe(u8, raw[header_end .. header_end + cl]);
}

test "json rpc error" {
    const a = std.testing.allocator;
    var parsed = try json.parse(a,
        \\{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"x"}}
    );
    defer parsed.deinit(a);
    try std.testing.expect(parsed.get("error") != null);
}
