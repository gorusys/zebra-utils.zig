const std = @import("std");

pub fn colorSupported() bool {
    if (std.posix.getenv("NO_COLOR")) |_| return false;
    return std.io.tty.detectConfig(std.io.getStdOut()) != .no_color;
}

pub const Color = enum {
    reset,
    bold,
    red,
    green,
    yellow,
    blue,
    cyan,
    white,
    dim,
};

pub fn setColor(writer: anytype, color: Color) @TypeOf(writer).Error!void {
    if (!colorSupported()) return;
    const s = switch (color) {
        .reset => "\x1b[0m",
        .bold => "\x1b[1m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .dim => "\x1b[2m",
    };
    try writer.writeAll(s);
}

pub fn clearLine(writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll("\x1b[2K\r");
}

pub fn cursorUp(writer: anytype, n: u16) @TypeOf(writer).Error!void {
    try std.fmt.format(writer, "\x1b[{d}A", .{n});
}

pub const Table = struct {
    headers: []const []const u8,
    rows: std.ArrayList([]const []const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, headers: []const []const u8) Table {
        return .{
            .headers = headers,
            .rows = std.ArrayList([]const []const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        for (self.rows.items) |r| self.allocator.free(r);
        self.rows.deinit();
    }

    pub fn addRow(self: *Table, row: []const []const u8) !void {
        const copy = try self.allocator.alloc([]const u8, row.len);
        @memcpy(copy, row);
        try self.rows.append(copy);
    }

    pub fn render(self: Table, writer: anytype, max_cell: usize) (error{TooManyColumns} || @TypeOf(writer).Error)!void {
        const ncols = self.headers.len;
        if (ncols > 32) return error.TooManyColumns;
        var widths: [32]usize = undefined;
        for (self.headers, 0..) |h, i| {
            widths[i] = @min(max_cell, displayLen(h, max_cell));
        }
        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                if (i < ncols) widths[i] = @max(widths[i], displayLen(cell, max_cell));
            }
        }
        for (self.headers, 0..) |h, i| {
            if (i > 0) try writer.writeAll("  ");
            try writeCell(writer, h, widths[i], max_cell);
        }
        try writer.writeByte('\n');
        var total: usize = 0;
        for (widths[0..ncols]) |w| total += w + 2;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            try writer.writeAll("─");
        }
        try writer.writeByte('\n');
        for (self.rows.items) |row| {
            for (row, 0..) |cell, j| {
                if (j > 0) try writer.writeAll("  ");
                try writeCell(writer, cell, widths[j], max_cell);
            }
            try writer.writeByte('\n');
        }
    }
};

fn displayLen(cell: []const u8, max_cell: usize) usize {
    return @min(max_cell, cell.len);
}

fn writeCell(writer: anytype, cell: []const u8, width: usize, max_cell: usize) !void {
    const s = if (cell.len > max_cell) cell[0..max_cell] else cell;
    if (s.len >= width) {
        try writer.writeAll(s[0..width]);
    } else {
        try writer.writeAll(s);
        try writer.writeByteNTimes(' ', width - s.len);
    }
}

test "table render" {
    const a = std.testing.allocator;
    var t = Table.init(a, &.{ "NAME", "ADDR" });
    defer t.deinit();
    try t.addRow(&.{ "peer-1", "203.0.113.4" });
    try t.addRow(&.{ "peer-2", "198.51.100.2" });
    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    try t.render(buf.writer(), 40);
    const s = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, s, "NAME") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "peer-1") != null);
}
