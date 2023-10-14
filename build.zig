const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("aseprite", .{
        .source_file = .{ .path = "src/aseprite.zig" },
    });

    const module_tests = b.addTest(.{
        .root_source_file = .{ .path = "test/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    module_tests.addModule("aseprite", module);

    const run_main_tests = b.addRunArtifact(module_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // TODO(SeedyROM): From !no ones uncle
    // for build.zig i think all you need is to add
    // const install_test = b.addInstallArtifact(unit_tests, .{}); and
    // test_step.dependOn(&install_test.step);
}
