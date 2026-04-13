const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcash_addr_dep = b.dependency("zcash_addr", .{
        .target = target,
        .optimize = optimize,
    });
    const zcash_addr_mod = b.createModule(.{
        .root_source_file = zcash_addr_dep.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zebra_only: []const std.Build.Module.Import = &.{
        .{ .name = "zebra", .module = lib_mod },
    };
    const scan_imports: []const std.Build.Module.Import = &.{
        .{ .name = "zcash_addr", .module = zcash_addr_mod },
    };
    const no_imports: []const std.Build.Module.Import = &.{};

    const tools = [_]struct {
        name: []const u8,
        root: std.Build.LazyPath,
        imports: []const std.Build.Module.Import,
    }{
        .{ .name = "zebra-cli", .root = b.path("src/bin/zebra_cli.zig"), .imports = zebra_only },
        .{ .name = "zebra-watch", .root = b.path("src/bin/zebra_watch.zig"), .imports = no_imports },
        .{ .name = "zebra-rpc-diff", .root = b.path("src/bin/zebra_rpc_diff.zig"), .imports = no_imports },
        .{ .name = "zebra-scan", .root = b.path("src/bin/zebra_scan.zig"), .imports = scan_imports },
        .{ .name = "zebra-checkpoint", .root = b.path("src/bin/zebra_checkpoint.zig"), .imports = no_imports },
    };

    for (tools) |t| {
        const exe = b.addExecutable(.{
            .name = t.name,
            .root_module = b.createModule(.{
                .root_source_file = t.root,
                .target = target,
                .optimize = optimize,
                .imports = t.imports,
            }),
            .link_libc = false,
        });
        b.installArtifact(exe);
    }

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .link_libc = false,
    });
    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
