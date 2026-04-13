const std = @import("std");
const builtin = @import("builtin");
const zebra = @import("zebra");

var g_stop: std.atomic.Value(bool) = .init(false);

fn onSigInt(_: c_int) callconv(.c) void {
    g_stop.store(true, .seq_cst);
}

const WatchOptions = struct {
    host: []const u8,
    port: u16,
    user: []const u8,
    pass: []const u8,
    interval_secs: u64,
    color: bool,
};

pub fn main() !void {
    if (builtin.os.tag != .windows) {
        const act = std.posix.Sigaction{
            .handler = .{ .handler = onSigInt },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.INT, &act, null);
    }

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

    var opts = WatchOptions{
        .host = try a.dupe(u8, cfg.node.host),
        .port = cfg.node.port,
        .user = try a.dupe(u8, cfg.node.username),
        .pass = try a.dupe(u8, cfg.node.password),
        .interval_secs = 5,
        .color = cfg.display.color,
    };

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    try parseArgs(args, &opts, a);

    var client = zebra.rpc.client.Client.init(alloc, .{
        .host = opts.host,
        .port = opts.port,
        .username = opts.user,
        .password = opts.pass,
    });
    const methods = zebra.rpc.methods.Methods.init(&client);

    const out = std.io.getStdOut().writer();
    const tty_color = opts.color and zebra.ansi.colorSupported();

    while (!g_stop.load(.seq_cst)) {
        try out.writeAll("\x1b[2J\x1b[H\x1b[?25l");
        try renderHeader(out, tty_color, opts);

        var tick = std.heap.ArenaAllocator.init(alloc);
        defer tick.deinit();
        const ta = tick.allocator();

        renderBody(ta, out, methods, tty_color) catch {
            if (tty_color) try zebra.ansi.setColor(out, .red);
            try out.writeAll("RPC unavailable. Retrying...\n");
            if (tty_color) try zebra.ansi.setColor(out, .reset);
        };

        try sleepWithSignal(opts.interval_secs);
    }

    try out.writeAll("\x1b[?25h\n");
}

fn parseArgs(args: []const []const u8, opts: *WatchOptions, alloc: std.mem.Allocator) !void {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(std.io.getStdOut().writer());
            std.process.exit(0);
        }
        if (std.mem.eql(u8, arg, "--node")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            try parseHostPort(args[i], &opts.host, &opts.port, alloc);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--node=")) {
            try parseHostPort(arg[7..], &opts.host, &opts.port, alloc);
            continue;
        }
        if (std.mem.eql(u8, arg, "--user")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            try parseUserPass(args[i], &opts.user, &opts.pass, alloc);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--user=")) {
            try parseUserPass(arg[7..], &opts.user, &opts.pass, alloc);
            continue;
        }
        if (std.mem.eql(u8, arg, "--interval")) {
            i += 1;
            if (i >= args.len) return error.BadArgs;
            opts.interval_secs = try std.fmt.parseInt(u64, args[i], 10);
            if (opts.interval_secs == 0) return error.BadArgs;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--interval=")) {
            opts.interval_secs = try std.fmt.parseInt(u64, arg[11..], 10);
            if (opts.interval_secs == 0) return error.BadArgs;
            continue;
        }
        if (std.mem.eql(u8, arg, "--color")) {
            opts.color = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-color")) {
            opts.color = false;
            continue;
        }
        std.debug.print("unknown option: {s}\n", .{arg});
        return error.BadArgs;
    }
}

fn renderHeader(out: anytype, color: bool, opts: WatchOptions) !void {
    if (color) try zebra.ansi.setColor(out, .cyan);
    try out.writeAll("zebra-watch");
    if (color) try zebra.ansi.setColor(out, .reset);
    try std.fmt.format(out, "  node {s}:{d}  interval {d}s\n\n", .{
        opts.host,
        opts.port,
        opts.interval_secs,
    });
}

fn renderBody(
    allocator: std.mem.Allocator,
    out: anytype,
    methods: zebra.rpc.methods.Methods,
    color: bool,
) !void {
    const chain = try methods.getBlockchainInfo(allocator);
    defer freeBlockchain(allocator, chain);
    const mempool = try methods.getMempoolInfo(allocator);
    const net = try methods.getNetworkInfo(allocator);
    defer freeNet(allocator, net);
    const peers = try methods.getPeerInfo(allocator);
    defer freePeers(allocator, peers);

    var h_buf: [32]u8 = undefined;
    var hash_buf: [48]u8 = undefined;
    var tx_buf: [32]u8 = undefined;
    var bytes_buf: [32]u8 = undefined;

    const h_s = try zebra.fmt.fmtHeight(chain.blocks, &h_buf);
    const best = try zebra.fmt.truncHash(chain.best_block_hash, &hash_buf);
    const mempool_txs = try zebra.fmt.fmtHeight(mempool.size, &tx_buf);
    const mempool_bytes = try zebra.fmt.fmtHeight(mempool.bytes, &bytes_buf);
    const sync_pct = chain.verification_progress * 100.0;

    if (color) try zebra.ansi.setColor(out, .bold);
    try out.writeAll("Chain\n");
    if (color) try zebra.ansi.setColor(out, .reset);
    try std.fmt.format(out, "  network      {s}\n", .{chain.chain});
    try std.fmt.format(out, "  height       {s}\n", .{h_s});
    try std.fmt.format(out, "  headers      {d}\n", .{chain.headers});
    try std.fmt.format(out, "  sync         {d:.2}%\n", .{sync_pct});
    try std.fmt.format(out, "  best hash    {s}\n", .{best});

    if (color) try zebra.ansi.setColor(out, .bold);
    try out.writeAll("\nMempool\n");
    if (color) try zebra.ansi.setColor(out, .reset);
    try std.fmt.format(out, "  transactions {s}\n", .{mempool_txs});
    try std.fmt.format(out, "  bytes        {s}\n", .{mempool_bytes});

    if (color) try zebra.ansi.setColor(out, .bold);
    try out.writeAll("\nPeers\n");
    if (color) try zebra.ansi.setColor(out, .reset);
    try std.fmt.format(out, "  getpeerinfo  {d}\n", .{peers.len});
    try std.fmt.format(out, "  connections  {d}\n", .{net.connections});
    try std.fmt.format(out, "  subversion   {s}\n", .{net.subversion});
}

fn sleepWithSignal(interval_secs: u64) !void {
    const ns_total = interval_secs * std.time.ns_per_s;
    const ns_step = 200 * std.time.ns_per_ms;
    var elapsed: u64 = 0;
    while (elapsed < ns_total and !g_stop.load(.seq_cst)) {
        const remaining = ns_total - elapsed;
        const this_step = if (remaining < ns_step) remaining else ns_step;
        std.Thread.sleep(this_step);
        elapsed += this_step;
    }
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
        \\zebra-watch [options]
        \\
        \\Live dashboard for a Zebra RPC endpoint. Refreshes periodically until Ctrl+C.
        \\
        \\Options:
        \\  --node <host:port>   RPC address (default from config or 127.0.0.1:8232)
        \\  --user <user:pass>   RPC authentication
        \\  --interval <secs>    Refresh interval in seconds (default: 5)
        \\  --color / --no-color
        \\  -h, --help
        \\
    );
}

fn freeBlockchain(a: std.mem.Allocator, c: zebra.rpc.types.BlockchainInfo) void {
    a.free(@constCast(c.chain));
    a.free(@constCast(c.best_block_hash));
    a.free(@constCast(c.chain_work));
    a.free(@constCast(c.consensus.chain_tip));
    a.free(@constCast(c.consensus.next_block));
}

fn freeNet(a: std.mem.Allocator, n: zebra.rpc.types.NetworkInfo) void {
    a.free(@constCast(n.subversion));
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
