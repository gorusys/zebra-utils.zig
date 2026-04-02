const std = @import("std");

pub const FormatError = error{BufferTooSmall};

/// Format zatoshis as ZEC string: 100000000 → "1.00000000 ZEC"
pub fn zatToZec(zat: u64, buf: []u8) FormatError![]const u8 {
    const whole = zat / 100_000_000;
    const frac = zat % 100_000_000;
    const n = std.fmt.bufPrint(buf, "{d}.{d:0>8} ZEC", .{ whole, frac }) catch return error.BufferTooSmall;
    return n;
}

/// Format large block heights with commas: 2341892 → "2,341,892"
pub fn fmtHeight(height: u64, buf: []u8) FormatError![]const u8 {
    var tmp: [32]u8 = undefined;
    const num = std.fmt.bufPrint(&tmp, "{d}", .{height}) catch return error.BufferTooSmall;
    if (num.len <= 3) {
        if (num.len > buf.len) return error.BufferTooSmall;
        @memcpy(buf[0..num.len], num);
        return buf[0..num.len];
    }
    var out_i: usize = 0;
    const lead = num.len % 3;
    if (lead > 0) {
        if (lead > buf.len) return error.BufferTooSmall;
        @memcpy(buf[0..lead], num[0..lead]);
        out_i = lead;
    }
    var i: usize = lead;
    while (i < num.len) : (i += 3) {
        if (out_i >= buf.len) return error.BufferTooSmall;
        if (i > 0) {
            buf[out_i] = ',';
            out_i += 1;
        }
        if (out_i + 3 > buf.len) return error.BufferTooSmall;
        @memcpy(buf[out_i .. out_i + 3], num[i .. i + 3]);
        out_i += 3;
    }
    return buf[0..out_i];
}

/// Truncate a hash for display: first 8 + "..."
pub fn truncHash(hash: []const u8, buf: []u8) FormatError![]const u8 {
    const prefix_len = @min(8, hash.len);
    if (prefix_len + 3 > buf.len) return error.BufferTooSmall;
    @memcpy(buf[0..prefix_len], hash[0..prefix_len]);
    @memcpy(buf[prefix_len .. prefix_len + 3], "...");
    return buf[0 .. prefix_len + 3];
}

/// Format Unix timestamp as human-readable UTC: "2024-03-15 14:23:01 UTC"
pub fn fmtTimestamp(unix: i64, buf: []u8) FormatError![]const u8 {
    const epoch_sec: u64 = @intCast(@max(unix, 0));
    const days = epoch_sec / 86400;
    const rem = epoch_sec % 86400;
    const hour = rem / 3600;
    const minute = (rem % 3600) / 60;
    const sec = rem % 60;
    // Approximate calendar from days since 1970-01-01 (good for display; not leap-second aware)
    var y: u32 = 1970;
    var d_left: u32 = @intCast(days);
    while (true) {
        const diy: u32 = if (isLeap(y)) 366 else 365;
        if (d_left < diy) break;
        d_left -= diy;
        y += 1;
    }
    var month: u32 = 1;
    const mdays = [_]u32{ 31, if (isLeap(y)) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    while (month <= 12) {
        const dim = mdays[month - 1];
        if (d_left < dim) break;
        d_left -= dim;
        month += 1;
    }
    const day = d_left + 1;
    const n = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ y, month, day, hour, minute, sec }) catch return error.BufferTooSmall;
    return n;
}

fn isLeap(y: u32) bool {
    return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
}

test "zatToZec" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("1.00000000 ZEC", try zatToZec(100_000_000, &buf));
    try std.testing.expectEqualStrings("0.00050000 ZEC", try zatToZec(50_000, &buf));
}

test "fmtHeight" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("2,341,892", try fmtHeight(2_341_892, &buf));
}

test "truncHash" {
    var buf: [64]u8 = undefined;
    const h = try truncHash("00000a3fdeadbeefcafe", &buf);
    try std.testing.expect(std.mem.startsWith(u8, h, "00000a3f"));
}
