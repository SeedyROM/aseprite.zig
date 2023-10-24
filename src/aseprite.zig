const std = @import("std");
const fs = std.fs;
const io = std.io;

pub const raw = @import("raw.zig");
const stb = @import("stb.zig");

/// Kind of texture data.
const TextureDataType = raw.ColorDepth;

/// A texture in an Aseprite file.
pub const Texture = struct {
    data_type: TextureDataType,
    width: u16,
    height: u16,
    data: []const u8,

    pub fn deinit(self: Texture, allocator: std.mem.Allocator) void {
        std.log.debug("Deinitializing texture.", .{});
        std.log.debug("Texture data type: {}", .{self.data_type});
        std.log.debug("Texture width: {}", .{self.width});
        std.log.debug("Texture height: {}", .{self.height});
        std.log.debug("Texture data: {any}", .{self.data});

        allocator.free(self.data);
    }
};

/// An animation cel in an Aseprite file.
pub const Cel = struct {
    duration: u16,
    x_position: i16,
    y_position: i16,
    opacity_level: u8,
    texture: Texture,

    pub fn deinit(self: Cel, allocator: std.mem.Allocator) void {
        std.log.debug("Deinitializing cel.", .{});
        std.log.debug("Cel duration: {}", .{self.duration});
        std.log.debug("Cel x position: {}", .{self.x_position});
        std.log.debug("Cel y position: {}", .{self.y_position});
        std.log.debug("Cel opacity level: {}", .{self.opacity_level});
        self.texture.deinit(allocator);
    }
};

/// A frame in an Aseprite file.
pub const Frame = struct {
    cel: Cel,

    pub inline fn getTexture(self: *const Frame) Texture {
        return self.cel.texture;
    }

    pub fn deinit(self: Frame, allocator: std.mem.Allocator) void {
        std.log.debug("Deinitializing frame.", .{});
        self.cel.deinit(allocator);
    }
};

/// A layer in an Aseprite file.
pub const Layer = struct {
    name: []const u8,
    frames: []Frame,

    pub fn deinit(self: Layer, allocator: std.mem.Allocator) void {
        std.log.debug("Deinitializing layer.", .{});
        std.log.debug("Layer name: {s}", .{self.name});
        for (self.frames) |frame| {
            frame.deinit(allocator);
        }
        allocator.free(self.name);
        allocator.free(self.frames);
    }
};

/// A sprite from an Aseprite file.
pub const Sprite = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    color_depth: raw.ColorDepth,
    num_frames: u16,
    width: u16,
    height: u16,
    layers: std.ArrayList(Layer),

    /// Load a sprite from an open file.
    pub fn fromFile(allocator: std.mem.Allocator, file: std.fs.File) !Self {
        var layers = try std.ArrayList(Layer).initCapacity(allocator, 16);

        const raw_file = try raw.parseRaw(allocator, file.reader());
        defer raw_file.deinit();

        var sprite = Self{
            .allocator = allocator,
            .color_depth = raw_file.header.color_depth,
            .num_frames = raw_file.header.num_frames,
            .width = raw_file.header.width_in_pixels,
            .height = raw_file.header.height_in_pixels,
            .layers = layers,
        };

        try sprite.loadInternalData(raw_file);

        return sprite;
    }

    /// Get a layer by name.
    pub fn getLayerByName(self: *const Self, name: []const u8) ?Layer {
        for (self.layers.items) |layer| {
            if (std.mem.eql(u8, layer.name, name)) {
                return layer;
            }
        }

        return null;
    }

    /// Get a layer by index.
    pub fn getLayerByIndex(self: *const Self, index: u16) ?Layer {
        if (index >= self.layers.len) {
            return null;
        }

        return self.layers.items[index];
    }

    /// Get a frame by index.
    /// Deinitialize the sprite.
    pub fn deinit(self: Self) void {
        for (self.layers.items) |layer| {
            layer.deinit(self.allocator);
        }
        self.layers.deinit();
    }

    fn loadInternalData(self: *Self, raw_file: raw.File) !void {
        // The first frame has a set of layer chunks that define the layers in the file.
        const first_frame = raw_file.frames[0];

        // For each chunk in the first frame.
        for (first_frame.chunks.items) |chunk| {
            // If the chunk is not a layer chunk, skip it.
            switch (chunk.data) {
                // If the chunk is a layer chunk, add it to the list of layers.
                .layer => |layer| {
                    std.log.debug("Found layer: {s}", .{layer.name});

                    var frames = try self.allocator.alloc(Frame, raw_file.header.num_frames);

                    const name = try self.allocator.alloc(u8, layer.name.len);
                    @memcpy(name, layer.name);

                    try self.layers.append(Layer{
                        .name = name,
                        .frames = frames,
                    });
                },
                else => {},
            }
        }

        // For each frame in the file.
        for (raw_file.frames, 0..) |frame, frame_index| {
            for (frame.chunks.items) |chunk| {
                switch (chunk.data) {
                    .cel => |cel| {
                        self.layers.items[cel.layer_index].frames[frame_index] = .{
                            .cel = .{
                                .duration = frame.header.duration,
                                .x_position = cel.x_position,
                                .y_position = cel.y_position,
                                .opacity_level = cel.opacity_level,
                                .texture = try self.decodeTextureFromCelData(cel),
                            },
                        };
                    },
                    else => {},
                }
            }
        }
    }

    fn decodeTextureFromCelData(self: *Self, cel: raw.CelChunk) !Texture {
        switch (cel.data) {
            .raw => |_raw| {
                var data = try self.allocator.alloc(u8, _raw.width * _raw.height);

                // Copy the data into the new buffer.
                std.mem.copy(u8, data, _raw.data);

                return .{
                    .data_type = self.color_depth,
                    .width = _raw.width,
                    .height = _raw.height,
                    .data = _raw.data,
                };
            },
            .compressed_image => |compressed_image| {
                // Create a stream from the compressed data.
                var compressed_data_stream = std.io.FixedBufferStream([]u8){
                    .pos = 0,
                    .buffer = compressed_image.data,
                };

                // Create a stream to decompress the data.
                var decompress_stream = try std.compress.zlib.decompressStream(
                    self.allocator,
                    compressed_data_stream.reader(),
                );
                defer decompress_stream.deinit();

                // Calculate the size of the decompressed data.
                const pixel_size: u16 = switch (self.color_depth) {
                    .indexed => 1,
                    .grayscale => 2,
                    .rgba => 4,
                };
                const decompressed_width = compressed_image.width;
                const decompressed_height = compressed_image.height;
                const decompressed_size = decompressed_width * decompressed_height * pixel_size;

                // Allocate space for the decompressed data.
                var decompressed_data = try self.allocator.alloc(u8, decompressed_size);

                // Decompress the data.
                var bytes_read = try decompress_stream.read(decompressed_data);
                if (bytes_read != decompressed_size) {
                    return error.InvalidTexture;
                }

                return .{
                    .data_type = self.color_depth,
                    .width = decompressed_width,
                    .height = decompressed_height,
                    .data = decompressed_data,
                };
            },
            else => {
                return error.UnsupportedCelType;
            },
        }
    }
};

pub const TextureAtlas = struct {
    const Self = @This();
    const Rect = stb.rect_pack.Rect;

    const AtlasRect = struct {
        was_packed: bool,
        id: usize,
        x: usize,
        y: usize,
        w: usize,
        h: usize,

        pub fn fromTextureRect(rect: Rect) AtlasRect {
            return .{
                .was_packed = rect.was_packed != 1,
                .id = @as(usize, @intCast(rect.id)),
                .x = @as(usize, @intCast(rect.x)),
                .y = @as(usize, @intCast(rect.y)),
                .w = @as(usize, @intCast(rect.w)),
                .h = @as(usize, @intCast(rect.h)),
            };
        }
    };

    allocator: std.mem.Allocator,
    expected_width: u16,
    expected_height: u16,
    actual_width: u16 = 0,
    actual_height: u16 = 0,
    textures: std.ArrayList(Texture),
    rects: std.ArrayList(Rect),
    texture: ?Texture = null,

    /// Initialize the atlas.
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) Self {
        return Self{
            .allocator = allocator,
            .expected_width = width,
            .expected_height = height,
            .textures = std.ArrayList(Texture).init(allocator),
            .rects = std.ArrayList(Rect).init(allocator),
        };
    }

    /// Deinitialize the atlas.
    pub fn deinit(self: *Self) void {
        self.textures.deinit();
        self.rects.deinit();

        if (self.texture) |texture| {
            texture.deinit(self.allocator);
        }
    }

    /// Add a sprite to the atlas.
    pub inline fn addSprite(self: *Self, sprite: Sprite) !void {
        // TODO(SeedyROM): These layers need to be flattened and blended...
        for (sprite.layers.items) |layer| {
            for (layer.frames) |frame| {
                // NOTE(SeedyROM): Is the id being sequential a bad idea?
                try self.addTexture(self.textures.items.len, frame.getTexture());
            }
        }
    }

    /// Add a list of sprites to the atlas.
    pub fn addSprites(self: *Self, sprites: []Sprite) !void {
        for (sprites) |sprite| {
            try self.addSprite(sprite);
        }
    }

    /// Add a texture to the atlas.
    pub fn addTexture(self: *Self, id: usize, texture: Texture) !void {
        var rect = Rect{
            .id = @as(c_int, @intCast(id)),
            .x = 0,
            .y = 0,
            .w = texture.width,
            .h = texture.height,
            .was_packed = @intFromBool(false),
        };

        try self.textures.append(texture);
        try self.rects.append(rect);
    }

    /// Pack the textures atthe
    pub fn packTextures(self: *Self) !u16 {
        // Create a context for the packer.
        var context: stb.rect_pack.Context = undefined;

        // Allocate space for the nodes.
        var nodes = try self.allocator.alloc(stb.rect_pack.Node, self.rects.items.len);
        defer self.allocator.free(nodes);

        // Initialize the packer.
        stb.rect_pack.initTarget(&context, self.expected_width, self.expected_height, nodes);

        // Pack the textures.
        const result = stb.rect_pack.packRects(&context, self.rects.items);
        if (result == 0) {
            return error.TexturePackFailed;
        }

        var rects_packed: u16 = 0;
        // Get the width and height of the packed texture.
        for (self.rects.items) |rect| {
            std.log.debug("Packed texture: {}", .{rect});

            if (rect.was_packed == 1) {
                rects_packed += 1;
            }

            if (rect.x + rect.w > self.actual_width) {
                self.actual_width = @as(u16, @intCast(rect.x + rect.w));
            }
            if (rect.y + rect.h > self.actual_height) {
                self.actual_height = @as(u16, @intCast(rect.y + rect.h));
            }
        }

        std.log.debug("Packed textures: {}", .{rects_packed});
        std.log.debug("Packed texture width: {}", .{self.actual_width});
        std.log.debug("Packed texture height: {}", .{self.actual_height});

        return rects_packed;
    }

    /// Get the packed texture data.
    pub fn createTexture(self: *Self) !Texture {
        // Get the size of the texture data.
        const texture_size = @as(usize, @intCast(self.actual_width * self.actual_height)) * 4;

        // Allocate and initialize the texture data.
        var raw_data = try self.allocator.alloc(
            u8,
            texture_size,
        );
        @memset(raw_data, 0);

        // Get a ptr to the slice as u32s.
        var data = std.mem.bytesAsSlice(u32, raw_data);

        // Write the texture data as u32s.
        for (self.rects.items) |_rect| {
            const rect = AtlasRect.fromTextureRect(_rect);
            if (rect.was_packed) {
                const texture = std.mem.bytesAsSlice(u32, self.textures.items[rect.id].data);

                for (0..rect.h) |y| {
                    for (0..rect.w) |x| {
                        const atlas_index = (rect.y + y) * self.actual_width + (rect.x + x);
                        const texture_index = y * rect.w + x;

                        data[atlas_index] = texture[texture_index];
                    }
                }
            }
        }

        return Texture{
            .data_type = TextureDataType.rgba,
            .width = self.actual_width,
            .height = self.actual_height,
            .data = raw_data,
        };
    }

    /// Write the packed texture data to a file.
    pub fn writeTextureToFile(self: *Self, path: []const u8) !void {
        // TODO(SeedyROM): Add check for file extension and write the correct format.
        // Defaults to PNG always for now.

        // Create the texture.
        self.texture = try self.createTexture();

        // Write the texture data to a file.
        try stb.image_write.png(
            path,
            self.texture.?.width,
            self.texture.?.height,
            4,
            self.texture.?.data,
            self.texture.?.width * 4,
        );
    }
};

/// Load a sprite from an open file.
pub fn fromFile(allocator: std.mem.Allocator, file: std.fs.File) !Sprite {
    return try Sprite.fromFile(allocator, file);
}

const testing = std.testing;

test "simple sprite api" {
    const file = try std.fs.cwd().openFile(
        "./sprites/simple/capy_idle.aseprite",
        .{ .mode = .read_only },
    );
    defer file.close();

    var sprite = try fromFile(testing.allocator, file);
    defer sprite.deinit();

    // Check that the sprite has 1 layer
    try testing.expectEqual(sprite.layers.items.len, 1);

    // Check that the sprite has 8 frames
    try testing.expectEqual(sprite.num_frames, 8);
}

test "complex sprite api" {
    testing.log_level = .debug;

    const file = try std.fs.cwd().openFile(
        "./sprites/complex/gumdrop.aseprite",
        .{ .mode = .read_only },
    );
    defer file.close();

    var sprite = try fromFile(testing.allocator, file);
    defer sprite.deinit();
}

test "simple texture atlas api" {
    // TODO(SeedyROM): Get a heuristic for the size of the atlas.
    // My current idea is to create a set of the widths, get the median, and use that.
    // The height would be the sum of the heights???

    // NOTE(SeedyROM): In this test we're using 13 (the main sprite width) and 4 of it as the span.

    // Create a texture atlas.
    var atlas = TextureAtlas.init(testing.allocator, 13 * 4, std.math.maxInt(u16));
    defer atlas.deinit();

    // Load each sprite from the sprites directory.
    var test_sprites = std.ArrayList(Sprite).init(testing.allocator);
    defer test_sprites.deinit();
    var sprites_dir = try std.fs.cwd().openIterableDir("./sprites/simple", .{});
    defer sprites_dir.close();

    // Iterate each file and open a file and load the sprite.
    var it = sprites_dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                std.log.debug("Found sprite file: {s}", .{entry.name});

                var file = try sprites_dir.dir.openFile(
                    entry.name,
                    .{ .mode = .read_only },
                );
                defer file.close();

                var sprite = try fromFile(testing.allocator, file);

                try test_sprites.append(sprite);
            },
            else => {},
        }
    }

    // Free each loaded sprite.
    defer {
        for (test_sprites.items) |sprite| {
            sprite.deinit();
        }
    }

    // Add sprites to the atlas.
    try atlas.addSprites(test_sprites.items);

    // Pack the textures.
    const packed_textures = try atlas.packTextures();

    // Check that the atlas packed all the textures.
    var test_packed_textures: u16 = 0;
    for (atlas.rects.items) |rect| {
        if (rect.was_packed == 1) {
            test_packed_textures += 1;
        }
    }
    try testing.expectEqual(packed_textures, test_packed_textures);

    // Write the packed texture to a file.
    try atlas.writeTextureToFile("zig-out/images/test-atlas.png");

    // Write the packed texture and atlas data to a file.
    // TODO(SeedyROM): Add support for writing atlas data.
    // try atlas.writeAtlasDataToFile("zig-out/images/test-atlas.png", "zig-out/images/test-atlas.json");
}
