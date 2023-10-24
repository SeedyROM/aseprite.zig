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

    // Setup a library for stb_image_rect_pack
    const stb_rect_pack = b.addStaticLibrary(.{
        .name = "stb_rect_pack",
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    stb_rect_pack.addCSourceFile(.{ .file = .{ .path = "extern/stb/stb_rect_pack.c" }, .flags = &.{"-DSTB_RECT_PACK_IMPLEMENTATION"} });

    // Create a step to make the image output directory
    const make_image_output_dir = MakeDirStep.create(b, "zig-out/images");

    // Setup testing
    const tests_filter = b.option([]const u8, "filter", "Filter for tests to run");
    const module_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
        .filter = tests_filter,
    });
    module_tests.addIncludePath(.{ .path = "extern/stb" });
    module_tests.linkLibrary(stb_image_write);
    module_tests.linkLibrary(stb_rect_pack);

    const run_main_tests = b.addRunArtifact(module_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&make_image_output_dir.step);
}

/// A step that creates a directory
const MakeDirStep = struct {
    step: std.build.Step,
    path: []const u8,

    pub fn create(owner: *std.Build, path: []const u8) *MakeDirStep {
        const self = owner.allocator.create(MakeDirStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "MakeDir",
                .owner = owner,
                .makeFn = make,
            }),
            .path = path,
        };
        return self;
    }

    fn make(step: *std.build.Step, _: *std.Progress.Node) !void {
        const self = @fieldParentPtr(MakeDirStep, "step", step);

        try std.fs.cwd().makePath(self.path);
    }
};
