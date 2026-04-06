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

fn strOrIntAsDecStr(allocator: std.mem.Allocator, v: json.Value, key: []const u8) TypesError![]const u8 {
    const f = v.get(key) orelse return error.MissingField;
    return switch (f) {
        .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
        .int => |n| if (n < 0) error.WrongType else std.fmt.allocPrint(allocator, "{d}", .{n}) catch return error.OutOfMemory,
        else => error.WrongType,
    };
}

fn u32fOpt(v: json.Value, key: []const u8) ?u32 {
    const f = v.get(key) orelse return null;
    return switch (f) {
        .int => |n| std.math.cast(u32, n),
        else => null,
    };
}

fn i64FromFirstIntField(v: json.Value, keys: []const []const u8) i64 {
    for (keys) |key| {
        const f = v.get(key) orelse continue;
        switch (f) {
            .int => |n| return n,
            else => {},
        }
    }
    return 0;
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
            .chain_work = try strOrIntAsDecStr(allocator, v, "chainwork"),
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
        const serv: []const u8 = if (v.get("services")) |services_v| switch (services_v) {
            .string => |s| allocator.dupe(u8, s) catch return error.OutOfMemory,
            .int => |n| std.fmt.allocPrint(allocator, "{d}", .{n}) catch return error.OutOfMemory,
            else => return error.WrongType,
        } else try allocator.dupe(u8, "");
        const ping = v.get("pingtime");
        const ping_time: ?f64 = if (ping) |p| switch (p) {
            .float => |x| x,
            .int => |n| @floatFromInt(n),
            else => null,
        } else null;
        const addr_local = (try strOpt(allocator, v, "addrlocal")) orelse
            (try strOpt(allocator, v, "addr_local")) orelse
            try allocator.dupe(u8, "");
        const subver = (try strOpt(allocator, v, "subver")) orelse try allocator.dupe(u8, "");
        return .{
            .id = u32fOpt(v, "id") orelse 0,
            .addr = try str(allocator, v, "addr"),
            .addr_local = addr_local,
            .services = serv,
            .version = u32fOpt(v, "version") orelse 0,
            .subver = subver,
            .inbound = try boolf(v, "inbound"),
            .connection_time = i64FromFirstIntField(v, &.{ "connectiontime", "connection_time" }),
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
        const sap_fs = (try strOpt(allocator, sap_c, "finalState")) orelse
            (try strOpt(allocator, sap_c, "final_state")) orelse
            try allocator.dupe(u8, "");
        const orch_fs = (try strOpt(allocator, orch_c, "finalState")) orelse
            (try strOpt(allocator, orch_c, "final_state")) orelse
            try allocator.dupe(u8, "");
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

test "BlockchainInfo chainwork as integer (Zebra)" {
    const a = std.testing.allocator;
    var v = try json.parse(a,
        \\{"chain":"main","blocks":1,"headers":1,"bestblockhash":"abc","difficulty":1.0,"verificationprogress":0.1,"chainwork":0,"pruned":false,"consensus":{"chaintip":"t1","nextblock":"n1"}}
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
    try std.testing.expectEqualStrings("0", b.chain_work);
}

test "TreeState empty commitments (Zebra z_gettreestate)" {
    const a = std.testing.allocator;
    var v = try json.parse(a,
        \\{"hash":"0000ab","height":1,"time":1,"sapling":{"commitments":{}},"orchard":{"commitments":{}}}
    );
    defer v.deinit(a);
    const t = try TreeState.fromJson(a, v);
    defer {
        a.free(@constCast(t.hash));
        a.free(@constCast(t.sapling.commitments.final_state));
        a.free(@constCast(t.orchard.commitments.final_state));
    }
    try std.testing.expectEqualStrings("0000ab", t.hash);
    try std.testing.expectEqualStrings("", t.sapling.commitments.final_state);
    try std.testing.expectEqualStrings("", t.orchard.commitments.final_state);
}

test "PeerInfo minimal (Zebra getpeerinfo)" {
    const a = std.testing.allocator;
    var v = try json.parse(a,
        \\{"addr":"1.2.3.4:8233","inbound":false,"pingtime":0.1}
    );
    defer v.deinit(a);
    const p = try PeerInfo.fromJson(a, v);
    defer {
        a.free(@constCast(p.addr));
        a.free(@constCast(p.addr_local));
        a.free(@constCast(p.services));
        a.free(@constCast(p.subver));
    }
    try std.testing.expectEqual(@as(u32, 0), p.id);
    try std.testing.expectEqualStrings("1.2.3.4:8233", p.addr);
    try std.testing.expectEqual(false, p.inbound);
    try std.testing.expect(p.ping_time != null);
}

test "wrong type" {
    const a = std.testing.allocator;
    var v = try json.parse(a, "{\"build\":1}");
    defer v.deinit(a);
    try std.testing.expectError(error.WrongType, GetInfo.fromJson(a, v));
}
