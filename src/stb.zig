const std = @import("std");

const c = @cImport({
    @cInclude("stb_image_write.h");
    @cInclude("stb_rect_pack.h");
});

/// A wrapper around stb_image_write.
pub const image_write = struct {
    /// Set compression level for PNG.
    pub const PngCompressionLevel = c.stbi_write_png_compression_level;

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
pub const rect_pack = struct {
    pub const Context = c.stbrp_context;
    pub const Node = c.stbrp_node;
    pub const Rect = c.stbrp_rect;

    /// Initializes a context.
    pub fn initTarget(
        context: *Context,
        width: u16,
        height: u16,
        nodes: []Node,
    ) void {
        c.stbrp_init_target(
            context,
            @as(c_int, @intCast(width)),
            @as(c_int, @intCast(height)),
            @ptrCast(nodes),
            @as(c_int, @intCast(nodes.len)),
        );
    }

    /// Pack rectangles into a context.
    /// Returns the number of rectangles that were packed.
    ///
    /// If the return value is less than the number of rectangles, then some rectangles
    /// were not packed.
    pub fn packRects(
        context: *Context,
        rects: []Rect,
    ) usize {
        return @as(usize, @intCast(c.stbrp_pack_rects(
            context,
            rects.ptr,
            @as(c_int, @intCast(rects.len)),
        )));
    }
};

const testing = std.testing;
// Write a PNG image.
test "image_write png" {
    const filename = "zig-out/images/test.png";
    const width = 16;
    const height = 16;
    const channels = 4;
    const data = try testing.allocator.alloc(u8, width * height * channels);
    defer testing.allocator.free(data);
    const stride_in_bytes = width * channels;

    try image_write.png(filename, width, height, channels, data, stride_in_bytes);
}
