const std = @import("std");
const json = @import("json.zig");

pub const TypesError = error{
    NotAnObject,
    MissingField,
    WrongType,
    OutOfMemory,
};

fn expectObject(v: json.Value) TypesError![]const json.Value.Field {
    return switch (v) {
        .object => |o| o,
        else => error.NotAnObject,
    };
}

fn str(allocator: std.mem.Allocator, v: json.Value, key: []const u8) TypesError![]const u8 {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
        else => error.WrongType,
    };
}

fn strOpt(allocator: std.mem.Allocator, v: json.Value, key: []const u8) TypesError!?[]const u8 {
    const f = v.get(key) orelse return null;
    return switch (f) {
        .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
        else => null,
    };
}

fn u64f(v: json.Value, key: []const u8) TypesError!u64 {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .int => |n| if (n < 0) error.WrongType else @intCast(n),
        else => error.WrongType,
    };
}

fn i64f(v: json.Value, key: []const u8) TypesError!i64 {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .int => |n| n,
        else => error.WrongType,
    };
}

fn f64f(v: json.Value, key: []const u8) TypesError!f64 {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .float => |x| x,
        .int => |n| @floatFromInt(n),
        else => error.WrongType,
    };
}

fn boolf(v: json.Value, key: []const u8) TypesError!bool {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .bool => |b| b,
        else => error.WrongType,
    };
}

fn u32f(v: json.Value, key: []const u8) TypesError!u32 {
    const n = try u64f(v, key);
    return std.math.cast(u32, n) orelse error.WrongType;
}

pub const GetInfo = struct {
    build: []const u8,
    subversion: []const u8,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!GetInfo {
        return .{
            .build = try str(allocator, v, "build"),
            .subversion = try str(allocator, v, "subversion"),
        };
    }
};

pub const BlockchainInfo = struct {
    chain: []const u8,
    blocks: u64,
    headers: u64,
    best_block_hash: []const u8,
    difficulty: f64,
    verification_progress: f64,
    chain_work: []const u8,
    pruned: bool,
    consensus: struct {
        chain_tip: []const u8,
        next_block: []const u8,
    },

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!BlockchainInfo {
        const best = str(allocator, v, "bestblockhash") catch |err| switch (err) {
            error.MissingField => try str(allocator, v, "best_block_hash"),
            else => |e| return e,
        };
        const cons = v.get("consensus") orelse return error.MissingField;
        const chain_tip = try str(allocator, cons, "chaintip");
        const next_block = try str(allocator, cons, "nextblock");
        return .{
            .chain = try str(allocator, v, "chain"),
            .blocks = try u64f(v, "blocks"),
            .headers = try u64f(v, "headers"),
            .best_block_hash = best,
            .difficulty = try f64f(v, "difficulty"),
            .verification_progress = try f64f(v, "verificationprogress"),
            .chain_work = try str(allocator, v, "chainwork"),
            .pruned = try boolf(v, "pruned"),
            .consensus = .{ .chain_tip = chain_tip, .next_block = next_block },
        };
    }
};

pub const BlockHeader = struct {
    hash: []const u8,
    confirmations: i64,
    height: u64,
    version: u32,
    merkle_root: []const u8,
    time: i64,
    nonce: []const u8,
    bits: []const u8,
    difficulty: f64,
    previous_hash: ?[]const u8,
    next_hash: ?[]const u8,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!BlockHeader {
        const merkle = str(allocator, v, "merkleroot") catch |err| switch (err) {
            error.MissingField => try str(allocator, v, "merkle_root"),
            else => |e| return e,
        };
        const nonce_v = v.get("nonce") orelse return error.MissingField;
        const nonce_str: []const u8 = switch (nonce_v) {
            .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
            .int => |n| std.fmt.allocPrint(allocator, "{d}", .{n}) catch return error.OutOfMemory,
            else => return error.WrongType,
        };
        const bits_v = v.get("bits") orelse return error.MissingField;
        const bits_str: []const u8 = switch (bits_v) {
            .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
            .int => |n| std.fmt.allocPrint(allocator, "0x{x}", .{@as(u32, @intCast(n))}) catch return error.OutOfMemory,
            else => return error.WrongType,
        };
        return .{
            .hash = try str(allocator, v, "hash"),
            .confirmations = try i64f(v, "confirmations"),
            .height = try u64f(v, "height"),
            .version = try u32f(v, "version"),
            .merkle_root = merkle,
            .time = try i64f(v, "time"),
            .nonce = nonce_str,
            .bits = bits_str,
            .difficulty = try f64f(v, "difficulty"),
            .previous_hash = try strOpt(allocator, v, "previousblockhash"),
            .next_hash = try strOpt(allocator, v, "nextblockhash"),
        };
    }
};

pub const Block = struct {
    header: BlockHeader,
    tx: [][]const u8,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!Block {
        const txarr = v.get("tx") orelse return error.MissingField;
        const arr = switch (txarr) {
            .array => |a| a,
            else => return error.WrongType,
        };
        const out = try allocator.alloc([]const u8, arr.len);
        errdefer allocator.free(out);
        for (arr, 0..) |item, i| {
            out[i] = switch (item) {
                .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
                else => return error.WrongType,
            };
        }
        const header = try BlockHeader.fromJson(allocator, v);
        return .{ .header = header, .tx = out };
    }
};

pub const MempoolInfo = struct {
    size: u64,
    bytes: u64,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!MempoolInfo {
        _ = allocator;
        return .{
            .size = try u64f(v, "size"),
            .bytes = try u64f(v, "bytes"),
        };
    }
};

pub const PeerInfo = struct {
    id: u32,
    addr: []const u8,
    addr_local: []const u8,
    services: []const u8,
    version: u32,
    subver: []const u8,
    inbound: bool,
    connection_time: i64,
    ping_time: ?f64,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!PeerInfo {
        const services_v = v.get("services") orelse return error.MissingField;
        const serv: []const u8 = switch (services_v) {
            .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
            .int => |n| std.fmt.allocPrint(allocator, "{d}", .{n}) catch return error.OutOfMemory,
            else => return error.WrongType,
        };
        const ping = v.get("pingtime");
        const ping_time: ?f64 = if (ping) |p| switch (p) {
            .float => |x| x,
            .int => |n| @floatFromInt(n),
            else => null,
        } else null;
        return .{
            .id = try u32f(v, "id"),
            .addr = try str(allocator, v, "addr"),
            .addr_local = str(allocator, v, "addrlocal") catch |err| switch (err) {
                error.MissingField => try str(allocator, v, "addr_local"),
                else => |e| return e,
            },
            .services = serv,
            .version = try u32f(v, "version"),
            .subver = try str(allocator, v, "subver"),
            .inbound = try boolf(v, "inbound"),
            .connection_time = try i64f(v, "connectiontime"),
            .ping_time = ping_time,
        };
    }
};

pub const NetworkInfo = struct {
    version: u32,
    subversion: []const u8,
    protocol_version: u32,
    connections: u32,
    relay_fee: f64,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!NetworkInfo {
        return .{
            .version = try u32f(v, "version"),
            .subversion = try str(allocator, v, "subversion"),
            .protocol_version = try u32f(v, "protocolversion"),
            .connections = try u32f(v, "connections"),
            .relay_fee = try f64f(v, "relayfee"),
        };
    }
};

pub const TxOut = struct {
    value: f64,
    confirmations: u64,
    script_pub_key: struct {
        asm_text: []const u8,
        hex: []const u8,
        type_str: []const u8,
        addresses: [][]const u8,
    },

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!TxOut {
        const spk = v.get("scriptPubKey") orelse return error.MissingField;
        const addrs_v = spk.get("addresses") orelse return error.MissingField;
        const arr = switch (addrs_v) {
            .array => |a| a,
            else => return error.WrongType,
        };
        const addresses = try allocator.alloc([]const u8, arr.len);
        errdefer allocator.free(addresses);
        for (arr, 0..) |item, i| {
            addresses[i] = switch (item) {
                .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
                else => return error.WrongType,
            };
        }
        return .{
            .value = try f64f(v, "value"),
            .confirmations = try u64f(v, "confirmations"),
            .script_pub_key = .{
                .asm_text = try str(allocator, spk, "asm"),
                .hex = try str(allocator, spk, "hex"),
                .type_str = try str(allocator, spk, "type"),
                .addresses = addresses,
            },
        };
    }
};

pub const TreeState = struct {
    hash: []const u8,
    height: u64,
    time: u64,
    sapling: struct {
        commitments: struct {
            final_state: []const u8,
        },
    },
    orchard: struct {
        commitments: struct {
            final_state: []const u8,
        },
    },

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!TreeState {
        const sap = v.get("sapling") orelse return error.MissingField;
        const orch = v.get("orchard") orelse return error.MissingField;
        const sap_c = sap.get("commitments") orelse return error.MissingField;
        const orch_c = orch.get("commitments") orelse return error.MissingField;
        const sap_fs = str(allocator, sap_c, "finalState") catch |err| switch (err) {
            error.MissingField => try str(allocator, sap_c, "final_state"),
            else => |e| return e,
        };
        const orch_fs = str(allocator, orch_c, "finalState") catch |err| switch (err) {
            error.MissingField => try str(allocator, orch_c, "final_state"),
            else => |e| return e,
        };
        return .{
            .hash = try str(allocator, v, "hash"),
            .height = try u64f(v, "height"),
            .time = try u64f(v, "time"),
            .sapling = .{ .commitments = .{ .final_state = sap_fs } },
            .orchard = .{ .commitments = .{ .final_state = orch_fs } },
        };
    }
};

pub const SendRawTxResult = struct {
    txid: []const u8,

    pub fn fromJson(allocator: std.mem.Allocator, v: json.Value) TypesError!SendRawTxResult {
        return .{ .txid = try str(allocator, v, "txid") };
    }
};

test "GetInfo fromJson" {
    const a = std.testing.allocator;
    var v = try json.parse(a,
        \\{"build":"1.0.0","subversion":"/Zebra:1.0.0/"}
    );
    defer v.deinit(a);
    const g = try GetInfo.fromJson(a, v);
    defer {
        a.free(@constCast(g.build));
        a.free(@constCast(g.subversion));
    }
    try std.testing.expectEqualStrings("1.0.0", g.build);
}

test "BlockchainInfo fixture" {
    const a = std.testing.allocator;
    var v = try json.parse(a,
        \\{"chain":"main","blocks":1,"headers":2,"bestblockhash":"abc","difficulty":1.5,"verificationprogress":0.99,"chainwork":"00","pruned":false,"consensus":{"chaintip":"t1","nextblock":"n1"}}
    );
    defer v.deinit(a);
    const b = try BlockchainInfo.fromJson(a, v);
    defer {
        a.free(@constCast(b.chain));
        a.free(@constCast(b.best_block_hash));
        a.free(@constCast(b.chain_work));
        a.free(@constCast(b.consensus.chain_tip));
        a.free(@constCast(b.consensus.next_block));
    }
    try std.testing.expectEqualStrings("main", b.chain);
}

test "wrong type" {
    const a = std.testing.allocator;
    var v = try json.parse(a, "{\"build\":1}");
    defer v.deinit(a);
    try std.testing.expectError(error.WrongType, GetInfo.fromJson(a, v));
}
