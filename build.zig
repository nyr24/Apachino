const std = @import("std");
const fmt = std.fmt;

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *std.Build) void {
    const is_release = b.option(
        bool,
        "release",
        "build for end user",
    ) orelse false;

    // Release
    if (is_release) {
        const exe = b.addExecutable(.{
            .name = "apachino",
            .root_source_file = b.path("src/main.zig"),
            .target = b.host,
            .optimize = .ReleaseFast,
        });

        b.installArtifact(exe);

        const run_arti = b.addRunArtifact(exe);
        const run_step = b.step("run-release", "Run project in release");
        run_step.dependOn(&run_arti.step);
    }
    // Debug
    else {
        const exe = b.addExecutable(.{
            .name = "apachino",
            .root_source_file = b.path("src/main.zig"),
            .target = b.host,
            .optimize = .Debug,
        });

        b.installArtifact(exe);

        const run_arti = b.addRunArtifact(exe);
        const run_step = b.step("run-dbg", "Run project in debug");
        run_step.dependOn(&run_arti.step);
    }
}
