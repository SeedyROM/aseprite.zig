const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //  // Setup aseprite module
    // const aseprite_module = b.addModule("aseprite", .{
    //     .source_file = .{ .path = "src/aseprite.zig" },
    // });
    // _ = aseprite_module;

    // Setup testing
    const module_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/aseprite.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(module_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
