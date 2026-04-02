pub const rpc = struct {
    pub const json = @import("rpc/json.zig");
    pub const client = @import("rpc/client.zig");
    pub const types = @import("rpc/types.zig");
    pub const methods = @import("rpc/methods.zig");
};
pub const config = @import("config.zig");
pub const ansi = @import("ansi.zig");
pub const fmt = @import("fmt.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("rpc/json.zig");
    _ = @import("rpc/client.zig");
    _ = @import("rpc/types.zig");
    _ = @import("rpc/methods.zig");
    _ = @import("config.zig");
    _ = @import("ansi.zig");
    _ = @import("fmt.zig");
}

const std = @import("std");
