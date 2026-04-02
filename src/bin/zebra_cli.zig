const std = @import("std");
const zebra = @import("zebra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg = zebra.config.Config.load(a) catch |err| {
        std.debug.print("config: {}\n", .{err});
        return err;
    };

    var opts = CliOptions{
        .host = try a.dupe(u8, cfg.node.host),
        .port = cfg.node.port,
        .user = try a.dupe(u8, cfg.node.username),
        .pass = try a.dupe(u8, cfg.node.password),
        .format = parseFormat(cfg.display.format) orelse .json,
        .color = cfg.display.color,
    };

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var i: usize = 1;
    var command: ?[]const u8 = null;
    var positionals = std.ArrayList([]const u8).init(alloc);
    defer positionals.deinit();

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(std.io.getStdOut().writer());
            return;
        }
        if (std.mem.eql(u8, arg, "--node")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            try parseHostPort(args[i], &opts.host, &opts.port, a);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--node=")) {
            try parseHostPort(arg[7..], &opts.host, &opts.port, a);
            continue;
        }
        if (std.mem.eql(u8, arg, "--user")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            try parseUserPass(args[i], &opts.user, &opts.pass, a);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--user=")) {
            try parseUserPass(arg[7..], &opts.user, &opts.pass, a);
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            opts.format = parseFormat(args[i]) orelse .json;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--format=")) {
            opts.format = parseFormat(arg[9..]) orelse .json;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-color")) {
            opts.color = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--color")) {
            opts.color = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("unknown option: {s}\n", .{arg});
            return error.BadArgs;
        }
        if (command == null) {
            command = arg;
        } else {
            try positionals.append(arg);
        }
    }

    const cmd = command orelse {
        try printUsage(std.io.getStdErr().writer());
        std.process.exit(1);
    };

    var client = zebra.rpc.client.Client.init(alloc, .{
        .host = opts.host,
        .port = opts.port,
        .username = opts.user,
        .password = opts.pass,
    });
    const methods = zebra.rpc.methods.Methods.init(&client);

    runCommand(a, methods, cmd, positionals.items, opts) catch |err| {
        if (err == error.UnknownCommand) {
            std.debug.print("unknown command: {s}\n", .{cmd});
            std.process.exit(1);
        }
        std.debug.print("error: {}\n", .{err});
        std.process.exit(1);
    };
}

const OutputFormat = enum { json, table, compact };

const CliOptions = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    pass: []const u8,
    format: OutputFormat,
    color: bool,
};

fn parseFormat(s: []const u8) ?OutputFormat {
    if (std.mem.eql(u8, s, "json")) return .json;
    if (std.mem.eql(u8, s, "table")) return .table;
    if (std.mem.eql(u8, s, "compact")) return .compact;
    return null;
}

fn parseHostPort(s: []const u8, host: *[]const u8, port: *u16, alloc: std.mem.Allocator) !void {
    const colon = std.mem.lastIndexOfScalar(u8, s, ':') orelse {
        host.* = try alloc.dupe(u8, s);
        return;
    };
    host.* = try alloc.dupe(u8, s[0..colon]);
    port.* = try std.fmt.parseInt(u16, s[colon + 1 ..], 10);
}

fn parseUserPass(s: []const u8, user: *[]const u8, pass: *[]const u8, alloc: std.mem.Allocator) !void {
    const colon = std.mem.indexOfScalar(u8, s, ':') orelse {
        user.* = try alloc.dupe(u8, s);
        pass.* = try alloc.dupe(u8, "");
        return;
    };
    user.* = try alloc.dupe(u8, s[0..colon]);
    pass.* = try alloc.dupe(u8, s[colon + 1 ..]);
}

fn printUsage(w: anytype) !void {
    try w.writeAll(
        \\zebra-cli [options] <command> [args...]
        \\
        \\Options:
        \\  --node <host:port>     Node RPC address (default: 127.0.0.1:8232)
        \\  --user <user:pass>     RPC authentication
        \\  --format <fmt>         json|table|compact (default: json)
        \\  --color / --no-color
        \\  -h, --help
        \\
        \\Commands:
        \\  info, chain, tip, block, tx, mempool, peers, network, treestate, ping, send
        \\
    );
}

fn runCommand(
    arena: std.mem.Allocator,
    m: zebra.rpc.methods.Methods,
    cmd: []const u8,
    args: []const []const u8,
    opts: CliOptions,
) !void {
    _ = opts.color;
    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, cmd, "info")) {
        const info = try m.getInfo(arena);
        defer freeGetInfo(arena, info);
        switch (opts.format) {
            .json => try std.fmt.format(out, "{{\"build\":\"{s}\",\"subversion\":\"{s}\"}}\n", .{ info.build, info.subversion }),
            .table => try std.fmt.format(out, "build:      {s}\nsubversion: {s}\n", .{ info.build, info.subversion }),
            .compact => try std.fmt.format(out, "{s} {s}\n", .{ info.build, info.subversion }),
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "chain")) {
        const c = try m.getBlockchainInfo(arena);
        defer freeBlockchain(arena, c);
        switch (opts.format) {
            .json => {},
            .table, .compact => {},
        }
        try std.fmt.format(out, "chain: {s} blocks: {d} headers: {d}\nbest: {s}\n", .{ c.chain, c.blocks, c.headers, c.best_block_hash });
        return;
    }
    if (std.mem.eql(u8, cmd, "tip")) {
        const height = try m.getBlockCount(arena);
        const hash = try m.getBestBlockHash(arena);
        defer arena.free(hash);
        switch (opts.format) {
            .compact => {
                var hb: [32]u8 = undefined;
                var hb2: [48]u8 = undefined;
                const hs = try zebra.fmt.fmtHeight(height, &hb);
                const hx = try zebra.fmt.truncHash(hash, &hb2);
                try std.fmt.format(out, "Height: {s}\nHash:   {s}\n", .{ hs, hx });
            },
            else => try std.fmt.format(out, "height: {d}\nhash: {s}\n", .{ height, hash }),
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "block")) {
        if (args.len == 0) return error.BadArgs;
        const id = args[0];
        const b = try m.getBlock(arena, id);
        defer freeBlock(arena, b);
        try std.fmt.format(out, "hash: {s} height: {d} txs: {d}\n", .{ b.header.hash, b.header.height, b.tx.len });
        return;
    }
    if (std.mem.eql(u8, cmd, "tx")) {
        if (args.len == 0) return error.BadArgs;
        const txid = args[0];
        const hex = try m.getRawTransaction(arena, txid);
        defer arena.free(hex);
        try out.writeAll(hex);
        try out.writeByte('\n');
        return;
    }
    if (std.mem.eql(u8, cmd, "mempool")) {
        const mp = try m.getMempoolInfo(arena);
        var hb: [32]u8 = undefined;
        var hb2: [32]u8 = undefined;
        const sz = try zebra.fmt.fmtHeight(mp.size, &hb);
        const by = try zebra.fmt.fmtHeight(mp.bytes, &hb2);
        try std.fmt.format(out, "Size:  {s} transactions\nBytes: {s}\n", .{ sz, by });
        return;
    }
    if (std.mem.eql(u8, cmd, "peers")) {
        const peers = try m.getPeerInfo(arena);
        defer freePeers(arena, peers);
        if (opts.format == .table) {
            var table = zebra.ansi.Table.init(arena, &.{ "ID", "ADDR", "DIR", "PING", "VERSION" });
            defer table.deinit();
            for (peers) |p| {
                var ping_buf: [32]u8 = undefined;
                const ping_s = if (p.ping_time) |t|
                    try std.fmt.bufPrint(&ping_buf, "{d:.0}ms", .{t * 1000})
                else
                    "n/a";
                const dir: []const u8 = if (p.inbound) "inbound" else "outbound";
                try table.addRow(&.{
                    try std.fmt.allocPrint(arena, "{d}", .{p.id}),
                    p.addr,
                    dir,
                    ping_s,
                    p.subver,
                });
            }
            try table.render(out, 48);
        } else {
            for (peers) |p| {
                try std.fmt.format(out, "{d} {s} inbound={any}\n", .{ p.id, p.addr, p.inbound });
            }
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "network")) {
        const n = try m.getNetworkInfo(arena);
        defer freeNet(arena, n);
        try std.fmt.format(out, "version {d} proto {d} peers {d} relay {d}\n", .{ n.version, n.protocol_version, n.connections, n.relay_fee });
        return;
    }
    if (std.mem.eql(u8, cmd, "treestate")) {
        if (args.len == 0) return error.BadArgs;
        const id = args[0];
        const t = try m.getTreeState(arena, id);
        defer freeTree(arena, t);
        try std.fmt.format(out, "height: {d} hash: {s}\n", .{ t.height, t.hash });
        return;
    }
    if (std.mem.eql(u8, cmd, "ping")) {
        try m.ping(arena);
        try out.writeAll("pong\n");
        return;
    }
    if (std.mem.eql(u8, cmd, "send")) {
        if (args.len == 0) return error.BadArgs;
        const hex = args[0];
        const r = try m.sendRawTransaction(arena, hex);
        defer arena.free(r.txid);
        try std.fmt.format(out, "{s}\n", .{r.txid});
        return;
    }
    return error.UnknownCommand;
}

fn freeGetInfo(a: std.mem.Allocator, g: zebra.rpc.types.GetInfo) void {
    a.free(@constCast(g.build));
    a.free(@constCast(g.subversion));
}

fn freeBlockchain(a: std.mem.Allocator, c: zebra.rpc.types.BlockchainInfo) void {
    a.free(@constCast(c.chain));
    a.free(@constCast(c.best_block_hash));
    a.free(@constCast(c.chain_work));
    a.free(@constCast(c.consensus.chain_tip));
    a.free(@constCast(c.consensus.next_block));
}

fn freeBlock(a: std.mem.Allocator, b: zebra.rpc.types.Block) void {
    freeHeader(a, b.header);
    for (b.tx) |t| a.free(@constCast(t));
    a.free(b.tx);
}

fn freeHeader(a: std.mem.Allocator, h: zebra.rpc.types.BlockHeader) void {
    a.free(@constCast(h.hash));
    a.free(@constCast(h.merkle_root));
    a.free(@constCast(h.nonce));
    a.free(@constCast(h.bits));
    if (h.previous_hash) |p| a.free(@constCast(p));
    if (h.next_hash) |p| a.free(@constCast(p));
}

fn freePeers(a: std.mem.Allocator, peers: []zebra.rpc.types.PeerInfo) void {
    for (peers) |p| {
        a.free(@constCast(p.addr));
        a.free(@constCast(p.addr_local));
        a.free(@constCast(p.services));
        a.free(@constCast(p.subver));
    }
    a.free(peers);
}

fn freeNet(a: std.mem.Allocator, n: zebra.rpc.types.NetworkInfo) void {
    a.free(@constCast(n.subversion));
}

fn freeTree(a: std.mem.Allocator, t: zebra.rpc.types.TreeState) void {
    a.free(@constCast(t.hash));
    a.free(@constCast(t.sapling.commitments.final_state));
    a.free(@constCast(t.orchard.commitments.final_state));
}

test "parse node" {
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 8232;
    const a = std.testing.allocator;
    try parseHostPort("127.0.0.1:9000", &host, &port, a);
    defer a.free(@constCast(host));
    try std.testing.expectEqual(@as(u16, 9000), port);
    try std.testing.expectEqualStrings("127.0.0.1", host);
}

test "parse format" {
    try std.testing.expectEqual(OutputFormat.json, parseFormat("json").?);
}

test "positional block" {
    const a = std.testing.allocator;
    var cmd: ?[]const u8 = null;
    var pos = std.ArrayList([]const u8).init(a);
    defer pos.deinit();
    const argv = [_][]const u8{ "zebra-cli", "block", "2000000" };
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        if (cmd == null) {
            cmd = argv[i];
        } else {
            try pos.append(argv[i]);
        }
    }
    try std.testing.expectEqualStrings("block", cmd.?);
    try std.testing.expectEqualStrings("2000000", pos.items[0]);
}
