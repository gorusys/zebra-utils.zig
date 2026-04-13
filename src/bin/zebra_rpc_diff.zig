const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try std.io.getStdOut().writer().writeAll(
                \\zebra-rpc-diff — not implemented yet (see roadmap: two-node JSON diff).
                \\
                \\Planned: --node-a, --node-b, <method> [params-json]
                \\
            );
            return;
        }
    }

    try std.io.getStdErr().writer().writeAll("zebra-rpc-diff: stub only; build stage installs the binary. See README roadmap.\n");
    std.process.exit(1);
}
