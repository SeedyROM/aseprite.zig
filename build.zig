const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // // Setup aseprite module
    _ = b.addModule("aseprite", .{
        .source_file = .{ .path = "src/aseprite.zig" },
    });

    // Setup a library for stb_image_write
    const stb_image_write = b.addStaticLibrary(.{
        .name = "stb_image_write",
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    stb_image_write.addCSourceFile(.{ .file = .{ .path = "extern/stb/stb_image_write.c" }, .flags = &.{"-DSTB_IMAGE_WRITE_IMPLEMENTATION"} });

    // Setup testing
    const module_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    module_tests.addIncludePath(.{ .path = "extern/stb" });
    module_tests.linkLibrary(stb_image_write);

    const run_main_tests = b.addRunArtifact(module_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
