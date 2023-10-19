const std = @import("std");

const c = @cImport({
    @cInclude("stb_image_write.h");
    @cInclude("stb_rect_pack.h");
});

/// A wrapper around stb_image_write.
pub const image_write = struct {
    /// Writes a PNG file.
    pub fn png(
        filename: []const u8,
        width: u32,
        height: u32,
        channels: u32,
        data: []const u8,
        stride_in_bytes: u32,
    ) !void {
        if (c.stbi_write_png(
            filename.ptr,
            @as(c_int, @intCast(width)),
            @as(c_int, @intCast(height)),
            @as(c_int, @intCast(channels)),
            @ptrCast(data),
            @as(c_int, @intCast(stride_in_bytes)),
        ) != 1) {
            return error.StbImageWriteFailed;
        }
    }
};

/// A wrapper around stb_rect_pack.
pub const rect_pack = struct {};

/// Create a directory for writing images in zig-out.
fn create_image_write_path() !void {
    const path = "zig-out/images";
    std.fs.cwd().makeDir(path) catch |err| {
        if (err == error.PathAlreadyExists) {}
    };
}

// Call this before any tests that write images.
test {
    try create_image_write_path();
}

const testing = std.testing;
// Write a PNG image.
test "image_write png" {
    const filename = "zig-out/images/tesxt.png";
    const width = 16;
    const height = 16;
    const channels = 4;
    const data = try testing.allocator.alloc(u8, width * height * channels);
    defer testing.allocator.free(data);
    const stride_in_bytes = width * channels;

    try image_write.png(filename, width, height, channels, data, stride_in_bytes);
}
