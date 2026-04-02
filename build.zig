const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli_exe = b.addExecutable(.{
        .name = "zebra-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bin/zebra_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zebra", .module = lib_mod },
            },
        }),
        .link_libc = false,
    });
    b.installArtifact(cli_exe);

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
