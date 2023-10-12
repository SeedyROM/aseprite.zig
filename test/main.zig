const std = @import("std");

const aseprite = @import("aseprite");

const testing = std.testing;

test "sprite parsing" {
    testing.log_level = .debug;

    const allocator = testing.allocator;

    // Load the aseprite file
    const file = try std.fs.cwd().openFile(
        "./test/capy_idle.aseprite",
        .{ .mode = .read_only },
    );
    defer file.close();

    // Parse the file
    try aseprite.parse(allocator, file.reader());

    // Fail so we can see the output
    try testing.expect(false);
}
