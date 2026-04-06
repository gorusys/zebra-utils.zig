const std = @import("std");
const client = @import("client.zig");
const types = @import("types.zig");
const json = @import("json.zig");

pub const Methods = struct {
    c: *client.Client,

    pub fn init(c: *client.Client) Methods {
        return .{ .c = c };
    }

    pub fn getInfo(self: Methods, arena: std.mem.Allocator) !types.GetInfo {
        const v = try self.c.call(arena, "getinfo", "[]");
        defer v.deinit(arena);
        return try types.GetInfo.fromJson(arena, v);
    }

    pub fn getBlockchainInfo(self: Methods, arena: std.mem.Allocator) !types.BlockchainInfo {
        const v = try self.c.call(arena, "getblockchaininfo", "[]");
        defer v.deinit(arena);
        return try types.BlockchainInfo.fromJson(arena, v);
    }

    pub fn getBlockCount(self: Methods, arena: std.mem.Allocator) !u64 {
        const v = try self.c.call(arena, "getblockcount", "[]");
        defer v.deinit(arena);
        return switch (v) {
            .int => |n| if (n < 0) error.InvalidResult else @intCast(n),
            else => error.InvalidResult,
        };
    }

    pub fn getBestBlockHash(self: Methods, arena: std.mem.Allocator) ![]const u8 {
        const v = try self.c.call(arena, "getbestblockhash", "[]");
        defer v.deinit(arena);
        return switch (v) {
            .string => |s| try arena.dupe(u8, s),
            else => error.InvalidResult,
        };
    }

    pub fn getBlockHash(self: Methods, arena: std.mem.Allocator, height: u64) ![]const u8 {
        var buf: [64]u8 = undefined;
        const p = try std.fmt.bufPrint(&buf, "[{d}]", .{height});
        const v = try self.c.call(arena, "getblockhash", p);
        defer v.deinit(arena);
        return switch (v) {
            .string => |s| try arena.dupe(u8, s),
            else => error.InvalidResult,
        };
    }

    pub fn getBlockHeader(self: Methods, arena: std.mem.Allocator, hash_or_height: []const u8) !types.BlockHeader {
        const params = try fmtParamsHashOrNum(arena, hash_or_height);
        defer arena.free(params);
        const v = try self.c.call(arena, "getblockheader", params);
        defer v.deinit(arena);
        return try types.BlockHeader.fromJson(arena, v);
    }

    pub fn getBlock(self: Methods, arena: std.mem.Allocator, hash_or_height: []const u8) !types.Block {
        const params = try fmtParamsBlock(arena, hash_or_height);
        defer arena.free(params);
        const v = try self.c.call(arena, "getblock", params);
        defer v.deinit(arena);
        return try types.Block.fromJson(arena, v);
    }

    pub fn getChainTips(self: Methods, arena: std.mem.Allocator) ![]json.Value {
        const v = try self.c.call(arena, "getchaintips", "[]");
        defer v.deinit(arena);
        return switch (v) {
            .array => |a| blk: {
                const out = try arena.alloc(json.Value, a.len);
                for (a, 0..) |item, i| {
                    out[i] = try jsonClone(arena, item);
                }
                break :blk out;
            },
            else => error.InvalidResult,
        };
    }

    pub fn getMempoolInfo(self: Methods, arena: std.mem.Allocator) !types.MempoolInfo {
        const v = try self.c.call(arena, "getmempoolinfo", "[]");
        defer v.deinit(arena);
        return try types.MempoolInfo.fromJson(arena, v);
    }

    pub fn getRawMempool(self: Methods, arena: std.mem.Allocator) ![][]const u8 {
        const v = try self.c.call(arena, "getrawmempool", "[]");
        defer v.deinit(arena);
        const a = switch (v) {
            .array => |x| x,
            else => return error.InvalidResult,
        };
        const out = try arena.alloc([]const u8, a.len);
        for (a, 0..) |item, i| {
            out[i] = switch (item) {
                .string => |s| try arena.dupe(u8, s),
                else => return error.InvalidResult,
            };
        }
        return out;
    }

    pub fn getNetworkInfo(self: Methods, arena: std.mem.Allocator) !types.NetworkInfo {
        const v = try self.c.call(arena, "getnetworkinfo", "[]");
        defer v.deinit(arena);
        return try types.NetworkInfo.fromJson(arena, v);
    }

    pub fn getPeerInfo(self: Methods, arena: std.mem.Allocator) ![]types.PeerInfo {
        const v = try self.c.call(arena, "getpeerinfo", "[]");
        defer v.deinit(arena);
        const a = switch (v) {
            .array => |x| x,
            else => return error.InvalidResult,
        };
        const out = try arena.alloc(types.PeerInfo, a.len);
        for (a, 0..) |item, i| {
            out[i] = try types.PeerInfo.fromJson(arena, item);
        }
        return out;
    }

    pub fn getConnectionCount(self: Methods, arena: std.mem.Allocator) !u32 {
        const v = try self.c.call(arena, "getconnectioncount", "[]");
        defer v.deinit(arena);
        return switch (v) {
            .int => |n| std.math.cast(u32, n) orelse error.InvalidResult,
            else => error.InvalidResult,
        };
    }

    pub fn ping(self: Methods, arena: std.mem.Allocator) !void {
        const v = try self.c.call(arena, "ping", "[]");
        defer v.deinit(arena);
    }

    pub fn getRawTransaction(self: Methods, arena: std.mem.Allocator, txid: []const u8) ![]const u8 {
        const params = try std.fmt.allocPrint(arena, "[\"{s}\",false]", .{txid});
        defer arena.free(params);
        const v = try self.c.call(arena, "getrawtransaction", params);
        defer v.deinit(arena);
        return switch (v) {
            .string => |s| try arena.dupe(u8, s),
            else => error.InvalidResult,
        };
    }

    pub fn sendRawTransaction(self: Methods, arena: std.mem.Allocator, hex: []const u8) !types.SendRawTxResult {
        const params = try std.fmt.allocPrint(arena, "[\"{s}\"]", .{hex});
        defer arena.free(params);
        const v = try self.c.call(arena, "sendrawtransaction", params);
        defer v.deinit(arena);
        return try types.SendRawTxResult.fromJson(arena, v);
    }

    pub fn getTxOut(self: Methods, arena: std.mem.Allocator, txid: []const u8, vout: u32) !types.TxOut {
        const params = try std.fmt.allocPrint(arena, "[\"{s}\",{d}]", .{ txid, vout });
        defer arena.free(params);
        const v = try self.c.call(arena, "gettxout", params);
        defer v.deinit(arena);
        return try types.TxOut.fromJson(arena, v);
    }

    pub fn getTreeState(self: Methods, arena: std.mem.Allocator, hash_or_height: []const u8) !types.TreeState {
        const params = try fmtParamsHashOrNum(arena, hash_or_height);
        defer arena.free(params);
        const v = try self.c.call(arena, "z_gettreestate", params);
        defer v.deinit(arena);
        return try types.TreeState.fromJson(arena, v);
    }

    pub fn getNetworkSolps(self: Methods, arena: std.mem.Allocator) !u64 {
        const v = try self.c.call(arena, "getnetworksolps", "[]");
        defer v.deinit(arena);
        return switch (v) {
            .int => |n| if (n < 0) error.InvalidResult else @intCast(n),
            .float => |f| @intFromFloat(f),
            else => error.InvalidResult,
        };
    }
};

pub const MethodsError = error{InvalidResult};

fn fmtParamsHashOrNum(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.fmt.parseInt(u64, s, 10)) |h| {
        return try std.fmt.allocPrint(arena, "[\"{d}\"]", .{h});
    } else |_| {
        return try std.fmt.allocPrint(arena, "[\"{s}\"]", .{s});
    }
}

fn fmtParamsBlock(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.fmt.parseInt(u64, s, 10)) |h| {
        return try std.fmt.allocPrint(arena, "[\"{d}\",1]", .{h});
    } else |_| {
        return try std.fmt.allocPrint(arena, "[\"{s}\",1]", .{s});
    }
}

fn jsonClone(allocator: std.mem.Allocator, v: json.Value) !json.Value {
    return switch (v) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .int => |n| .{ .int = n },
        .float => |f| .{ .float = f },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |a| {
            const out = try allocator.alloc(json.Value, a.len);
            for (a, 0..) |item, i| {
                out[i] = try jsonClone(allocator, item);
            }
            return .{ .array = out };
        },
        .object => |o| {
            const out = try allocator.alloc(json.Value.Field, o.len);
            for (o, 0..) |f, i| {
                out[i] = .{
                    .key = try allocator.dupe(u8, f.key),
                    .value = try jsonClone(allocator, f.value),
                };
            }
            return .{ .object = out };
        },
    };
}

test "params hash or height string" {
    const a = std.testing.allocator;
    const p = try fmtParamsHashOrNum(a, "12345");
    defer a.free(p);
    try std.testing.expectEqualStrings("[\"12345\"]", p);
}

test "params hash string" {
    const a = std.testing.allocator;
    const p = try fmtParamsHashOrNum(a, "0000abc");
    defer a.free(p);
    try std.testing.expectEqualStrings("[\"0000abc\"]", p);
}
