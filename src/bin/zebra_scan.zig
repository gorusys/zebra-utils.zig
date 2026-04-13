const std = @import("std");
const zcash_addr = @import("zcash_addr");

pub fn main() !void {
    std.debug.assert(@sizeOf(zcash_addr.Address) > 0);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try std.io.getStdOut().writer().writeAll(
                \\zebra-scan — not implemented yet (see roadmap: block-range scan).
                \\
                \\The `zcash_addr` module is linked for this binary. Planned: --address, --from, --to, …
                \\
            );
            return;
        }
    }

    try std.io.getStdErr().writer().writeAll("zebra-scan: stub only; build stage installs the binary. See README roadmap.\n");
    std.process.exit(1);
}
