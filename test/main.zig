const std = @import("std");

const aseprite = @import("aseprite");

const testing = std.testing;
const allocator = testing.allocator;

// The path to our test sprite.
const test_file_path = "test/capy_idle.aseprite";

test "raw sprite file parsing" {
    // Read the real size of the file from the OS
    var test_file_size: u32 = undefined;
    {
        const file = try std.fs.cwd().openFile(
            test_file_path,
            .{ .mode = .read_only },
        );
        defer file.close();

        const stat = try file.stat();
        test_file_size = @as(u32, @intCast(stat.size));
    }

    // Open the aseprite file
    const file = try std.fs.cwd().openFile(
        test_file_path,
        .{ .mode = .read_only },
    );
    defer file.close();

    // Parse the file from the reader
    var aseprite_file = try aseprite.parseRaw(allocator, file.reader());
    defer aseprite_file.deinit();

    // Check the header from expected known values...
    const header = aseprite_file.header;
    try testing.expectEqual(header.size, test_file_size);
    try testing.expectEqual(header.num_frames, 8);
    try testing.expectEqual(header.width_in_pixels, 16);
    try testing.expectEqual(header.height_in_pixels, 16);
    try testing.expectEqual(header.color_depth, .rgba);
    try testing.expectEqual(header.transparent_color_index, 0);
    try testing.expectEqual(header.num_colors, 32);
    try testing.expectEqual(header.pixel_width, 1);
    try testing.expectEqual(header.pixel_height, 1);
    try testing.expectEqual(header.grid_position_x, 0);
    try testing.expectEqual(header.grid_position_y, 0);
    try testing.expectEqual(header.grid_width, 16);
    try testing.expectEqual(header.grid_height, 16);

    // TODO(SeedyROM): Add more tests...
}

test "sprite api" {
    testing.log_level = .info;

    const file = try std.fs.cwd().openFile(
        test_file_path,
        .{ .mode = .read_only },
    );
    defer file.close();

    var sprite = try aseprite.fromFile(allocator, file);
    defer sprite.deinit();

    // Check that the sprite has 1 layer
    try testing.expectEqual(sprite.layers.items.len, 1);
}
