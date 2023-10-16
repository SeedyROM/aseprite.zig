const std = @import("std");
const fs = std.fs;
const io = std.io;

const Pixel = packed union {
    indexed: packed struct {
        index: u8,
    },
    grayscale: packed struct {
        value: u16,
    },
    // NOTE(SeedyROM): This will fail, the order of the fields is wrong.
    rgba: packed struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8,
    },
};

fn bufferedReader(
    comptime buffer_size: comptime_int,
    stream: anytype,
) io.BufferedReader(buffer_size, @TypeOf(stream)) {
    return .{ .unbuffered_reader = stream };
}

const raw = struct {
    /// Depth of color in the image.
    const ColorDepth = enum(u16) {
        indexed = 8,
        grayscale = 16,
        rgba = 32,
    };

    /// Header of the Aseprite file.
    pub const Header = struct {
        size: u32,
        magic: u16,
        num_frames: u16,
        width_in_pixels: u16,
        height_in_pixels: u16,
        color_depth: ColorDepth,
        flags: u32,
        _deprecated_speed: u16,
        transparent_color_index: u8,
        num_colors: u16,
        pixel_width: u8,
        pixel_height: u8,
        grid_position_x: i16,
        grid_position_y: i16,
        grid_width: u16,
        grid_height: u16,
    };

    fn parseHeader(reader: anytype) !Header {
        const size = try reader.readInt(u32, .Little);
        const magic = try reader.readInt(u16, .Little);
        const num_frames = try reader.readInt(u16, .Little);
        const width_in_pixels = try reader.readInt(u16, .Little);
        const height_in_pixels = try reader.readInt(u16, .Little);
        const color_depth = try reader.readEnum(ColorDepth, .Little);
        const flags = try reader.readInt(u32, .Little);
        const _deprecated_speed = try reader.readInt(u16, .Little);

        // Skip 8 bytes of reserved data.
        _ = try reader.skipBytes(8, .{});

        const transparent_color_index = try reader.readInt(u8, .Little);

        // Skip 3 bytes of reserved data.
        _ = try reader.skipBytes(3, .{});

        const num_colors = try reader.readInt(u16, .Little);
        const pixel_width = try reader.readInt(u8, .Little);
        const pixel_height = try reader.readInt(u8, .Little);
        const grid_position_x = try reader.readInt(i16, .Little);
        const grid_position_y = try reader.readInt(i16, .Little);
        const grid_width = try reader.readInt(u16, .Little);
        const grid_height = try reader.readInt(u16, .Little);

        // Skip 84 bytes of reserved data.
        _ = try reader.skipBytes(84, .{});

        // Check the magic number.
        if (magic != 0xA5E0) {
            return error.InvalidHeader;
        }

        return .{
            .size = size,
            .magic = magic,
            .num_frames = num_frames,
            .width_in_pixels = width_in_pixels,
            .height_in_pixels = height_in_pixels,
            .color_depth = color_depth,
            .flags = flags,
            ._deprecated_speed = _deprecated_speed,
            .transparent_color_index = transparent_color_index,
            .num_colors = num_colors,
            .pixel_width = pixel_width,
            .pixel_height = pixel_height,
            .grid_position_x = grid_position_x,
            .grid_position_y = grid_position_y,
            .grid_width = grid_width,
            .grid_height = grid_height,
        };
    }

    /// The header of a frame.
    pub const FrameHeader = struct {
        size: u32,
        magic: u16,
        _old_num_chunks: u16,
        duration: u16,
        num_chunks: u32,
    };

    fn parseFrameHeader(reader: anytype) !FrameHeader {
        const size = try reader.readInt(u32, .Little);
        const magic = try reader.readInt(u16, .Little);
        const _old_num_chunks = try reader.readInt(u16, .Little);
        const duration = try reader.readInt(u16, .Little);

        // Skip 2 bytes of reserved data.
        _ = try reader.skipBytes(2, .{});

        const num_chunks = try reader.readInt(u32, .Little);

        // Check the magic number.
        if (magic != 0xF1FA) {
            return error.InvalidFrameHeader;
        }

        return .{
            .size = size,
            .magic = magic,
            ._old_num_chunks = _old_num_chunks,
            .duration = duration,
            .num_chunks = num_chunks,
        };
    }

    /// The flags in a layer.
    pub const LayerFlags = packed struct(u16) {
        visible: bool,
        editable: bool,
        lock_movement: bool,
        background: bool,
        prefer_linked_cels: bool,
        display_collapsed: bool,
        reference_layer: bool,

        _padding: u9,
    };

    /// The type of a layer.
    pub const LayerType = enum(u16) {
        normal,
        group,
        tilemap,
    };

    /// The blend mode of a layer.
    pub const LayerBlendMode = enum(u16) {
        normal,
        multiply,
        screen,
        overlay,
        darken,
        lighten,
        color_dodge,
        color_burn,
        hard_light,
        soft_light,
        difference,
        exclusion,
        hue,
        saturation,
        color,
        luminosity,
        addition,
        subtract,
        divide,
    };

    /// A layer in an Aseprite file.
    pub const LayerChunk = struct {
        flags: LayerFlags,
        type: LayerType,
        child_level: u16,
        default_width: u16,
        default_height: u16,
        blend_mode: LayerBlendMode,
        opacity: u8,
        name: []u8,
    };

    fn parseLayerChunk(allocator: std.mem.Allocator, reader: anytype) !ChunkData {
        const flags = try reader.readStruct(LayerFlags);
        const _type = try reader.readEnum(LayerType, .Little);
        const child_level = try reader.readInt(u16, .Little);
        const default_width = try reader.readInt(u16, .Little);
        const default_height = try reader.readInt(u16, .Little);
        const blend_mode = try reader.readEnum(LayerBlendMode, .Little);
        const opacity = try reader.readInt(u8, .Little);

        // Skip 3 bytes of reserved data.
        _ = try reader.skipBytes(3, .{});

        const name_size = try reader.readInt(u16, .Little);

        // Allocate the name buffer.
        const name = try allocator.alloc(u8, name_size);
        var bytes_read = try reader.read(name);
        if (bytes_read != name_size) {
            return error.InvalidLayerChunk;
        }

        // Print the name.
        std.log.debug("Parsing layer (name): {s}", .{name});

        return .{
            .layer = LayerChunk{
                .flags = flags,
                .type = _type,
                .child_level = child_level,
                .default_width = default_width,
                .default_height = default_height,
                .blend_mode = blend_mode,
                .opacity = opacity,
                .name = name,
            },
        };
    }

    pub const ColorProfileType = enum(u16) {
        none,
        srgb,
        embedded_icc_profile,
    };

    pub const ColorProfileFlags = packed struct(u16) {
        use_special_gamma: bool,
        _padding: u15,
    };

    /// The color profile of an Aseprite file.
    pub const ColorProfileChunk = struct {
        type: ColorProfileType,
        flags: ColorProfileFlags,
        fixed_gamma: u32, // TODO(SeedyROM): This ain't fixed point 16.16... support this one day?
        icc_data_length: u32 = 0, // TODO(SeedyROM): This is never used, but it's in the spec.
        icc_data: ?[]u8 = null, // TODO(SeedyROM): This is never used, but it's in the spec.
    };

    fn parseColorProfileChunk(allocator: std.mem.Allocator, reader: anytype) !ChunkData {
        const _type = try reader.readEnum(ColorProfileType, .Little);
        const flags = try reader.readStruct(ColorProfileFlags);
        const fixed_gamma = try reader.readInt(u32, .Little);

        // Skip 8 bytes of reserved data.
        _ = try reader.skipBytes(8, .{});

        // Parse ICC optional ICC data.
        var icc_data_length: u32 = 0;
        var icc_data: ?[]u8 = null;
        switch (_type) {
            .embedded_icc_profile => {
                icc_data_length = try reader.readInt(u32, .Little);
                var icc_data_buf = try allocator.alloc(u8, icc_data_length);

                // Check that we read the correct number of bytes.
                var bytes_read = try reader.read(icc_data_buf);
                if (bytes_read != icc_data_length) {
                    return error.InvalidColorProfileChunk;
                }

                icc_data = icc_data_buf;
            },
            else => {},
        }

        return .{
            .color_profile = ColorProfileChunk{
                .type = _type,
                .flags = flags,
                .fixed_gamma = fixed_gamma,
                .icc_data_length = icc_data_length,
                .icc_data = icc_data,
            },
        };
    }

    pub const CelType = enum(u16) {
        raw,
        linked,
        compressed_image,
        compressed_tilemap,
    };

    pub const CelChunkData = union(enum) {
        raw: struct {
            width: u16,
            height: u16,
            data: []u8,
        },
        linked: struct {
            frame_position: u32,
        },
        compressed_image: struct {
            width: u16,
            height: u16,
            data: []u8,
        },
        // TODO(SeedyROM): Support compressed tilemaps.
        compressed_tilemap: struct {
            // width_in_tiles: u16,
            // height_in_tiles: u16,
            // bits_per_tile = 32,
            // bitmask
        },

        pub fn deinit(self: CelChunkData, allocator: std.mem.Allocator) void {
            std.log.debug("Deinitializing cel chunk data.", .{});
            std.log.debug("Cel type: {}", .{self});
            switch (self) {
                .raw => |_raw| {
                    std.log.debug("Freeing raw data: {any}", .{_raw.data});
                    allocator.free(_raw.data);
                },
                .linked => {},
                .compressed_image => |compressed_image| {
                    std.log.debug("Freeing compressed image data: {any}", .{compressed_image.data});
                    allocator.free(compressed_image.data);
                },
                .compressed_tilemap => {},
            }
        }
    };

    pub const CelChunk = struct {
        layer_index: u16,
        x_position: i16,
        y_position: i16,
        opacity_level: u8,
        cel_type: CelType,
        z_index: i16,
        data: CelChunkData,
    };

    pub fn parseCelChunk(allocator: std.mem.Allocator, reader: anytype, size: u32) !ChunkData {
        const layer_index = try reader.readInt(u16, .Little);
        const x_position = try reader.readInt(i16, .Little);
        const y_position = try reader.readInt(i16, .Little);
        const opacity_level = try reader.readInt(u8, .Little);
        const cel_type = try reader.readEnum(CelType, .Little);
        const z_index = try reader.readInt(i16, .Little);

        // Skip 5 bytes of reserved data.
        _ = try reader.skipBytes(5, .{});

        var data: CelChunkData = undefined;
        switch (cel_type) {
            // TODO(SeedyROM): Support Raw Cels.
            .raw => {
                // const width = try reader.readInt(u16, .Little);
                // const height = try reader.readInt(u16, .Little);

                // data = CelChunkData.raw{
                //     .width = width,
                //     .height = height,
                //     .data = data,
                // };

                return error.UnsupportedCelType;
            },
            .linked => {
                const frame_position = try reader.readInt(u32, .Little);

                data = CelChunkData{
                    .linked = .{
                        .frame_position = frame_position,
                    },
                };
            },
            .compressed_image => {
                const width = try reader.readInt(u16, .Little);
                const height = try reader.readInt(u16, .Little);

                // Calculate the length of the image data by subtracting the size of the header, width and height fields.
                const image_data_length = size - 26;
                const image_data = try allocator.alloc(u8, image_data_length);
                var bytes_read = try reader.read(image_data);
                if (bytes_read != image_data_length) {
                    return error.InvalidCelChunk;
                }

                data = CelChunkData{
                    .compressed_image = .{
                        .width = width,
                        .height = height,
                        .data = image_data,
                    },
                };
            },
            // TODO(SeedyROM): Support compressed tilemaps.
            .compressed_tilemap => {
                // const width_in_tiles = try reader.readInt(u16, .Little);
                // const height_in_tiles = try reader.readInt(u16, .Little);
                // const bits_per_tile = try reader.readInt(u16, .Little);
                // const bitmask = try reader.readInt(u32, .Little);

                return error.UnsupportedCelType;
            },
        }

        return .{
            .cel = CelChunk{
                .layer_index = layer_index,
                .x_position = x_position,
                .y_position = y_position,
                .opacity_level = opacity_level,
                .cel_type = cel_type,
                .z_index = z_index,
                .data = data,
            },
        };
    }

    /// The chunk types in an Aseprite file.
    pub const ChunkType = enum(u16) {
        // Older palette chunk.
        older_palette = 0x0004,
        // Old palette chunk.
        old_palette = 0x0011,
        layer = 0x2004,
        cel = 0x2005,
        cel_extra = 0x2006,
        color_profile = 0x2007,
        extern_files = 0x2008,
        /// Deprecated.
        mask = 0x2016,
        /// Never used.
        path = 0x2017,
        tags = 0x2018,
        palette = 0x2019,
        user_data = 0x2020,
        slice = 0x2022,
    };

    /// The chunk types in an Aseprite file.
    pub const Chunk = struct {
        size: u32,
        chunk_type: ChunkType,
        data: ChunkData,
    };

    /// The data in a chunk.
    pub const ChunkData = union(enum) {
        layer: LayerChunk,
        color_profile: ColorProfileChunk,
        cel: CelChunk,
        // cel_extra: CelExtraChunk,
        // TODO(SeedyROM): Support the rest of the chunk types.

        fn deinit(self: ChunkData, allocator: std.mem.Allocator) void {
            std.log.debug("Deinitializing chunk data.", .{});

            std.log.debug("Chunk type: {}", .{self});

            switch (self) {
                .layer => |layer| {
                    std.log.debug("Freeing layer name: {s}", .{layer.name});
                    allocator.free(layer.name);
                },
                .color_profile => |color_profile| {
                    if (color_profile.icc_data_length == 0) {
                        std.log.debug("No ICC data to free.", .{});
                        return;
                    }

                    std.log.debug("ICC data length: {}", .{color_profile.icc_data_length});
                    if (color_profile.icc_data) |icc_data| {
                        std.log.warn("Attempting to free ICC data: {any}", .{icc_data});
                        allocator.free(icc_data);
                    }
                },
                .cel => |cel| {
                    cel.data.deinit(allocator);
                },
            }
        }
    };

    fn parseChunk(allocator: std.mem.Allocator, reader: anytype) !?Chunk {
        // Get the chunk size.
        const size = try reader.readInt(u32, .Little);
        std.log.debug("Next chunk size: {}", .{size});

        // Check if the chunk is too small to be valid.
        if (size < 6) {
            return error.InvalidChunkSize;
        }

        // Get the chunk type.
        const chunk_type = try reader.readEnum(ChunkType, .Little);
        std.log.debug("Next chunk type: {}", .{chunk_type});

        var data: ChunkData = undefined;
        switch (chunk_type) {
            .layer => {
                data = try parseLayerChunk(allocator, reader);
            },
            .color_profile => {
                data = try parseColorProfileChunk(allocator, reader);
            },
            .cel => {
                data = try parseCelChunk(allocator, reader, size);
            },
            else => {
                std.log.debug("Skipping chunk of type {}", .{chunk_type});

                // Skip the rest of the chunk.
                _ = try reader.skipBytes(size - 6, .{});
                return null;
            },
        }

        return .{
            .size = size,
            .chunk_type = chunk_type,
            .data = data,
        };
    }

    /// A frame in an Aseprite file.
    pub const Frame = struct {
        header: FrameHeader,
        chunks: std.ArrayList(Chunk),

        fn deinit(self: Frame, allocator: std.mem.Allocator) void {
            for (self.chunks.items) |chunk| {
                chunk.data.deinit(allocator);
            }
            self.chunks.deinit();
        }
    };

    fn parseFrame(allocator: std.mem.Allocator, reader: anytype) !Frame {
        const header = try parseFrameHeader(reader);
        std.log.debug("FrameHeader: {}", .{header});

        var chunks = try std.ArrayList(Chunk).initCapacity(allocator, header.num_chunks);

        for (0..header.num_chunks) |_| {
            const chunk = try parseChunk(allocator, reader);
            if (chunk == null) {
                continue;
            }

            std.log.debug("Chunk: {}", .{chunk.?});
            try chunks.append(chunk.?);
        }

        return Frame{
            .header = header,
            .chunks = chunks,
        };
    }

    pub const File = struct {
        allocator: std.mem.Allocator,
        header: raw.Header,
        frames: []raw.Frame,

        pub fn deinit(self: File) void {
            for (self.frames) |frame| {
                frame.deinit(self.allocator);
            }
            self.allocator.free(self.frames);
        }

        pub inline fn frames(self: File) []raw.Frame {
            return self.frames;
        }

        pub inline fn header(self: File) raw.Header {
            return self.header;
        }

        pub inline fn width(self: File) u16 {
            return self.header.width_in_pixels;
        }

        pub inline fn height(self: File) u16 {
            return self.header.height_in_pixels;
        }

        pub inline fn colorDepth(self: File) raw.ColorDepth {
            return self.header.color_depth;
        }

        pub inline fn numFrames(self: File) u16 {
            return self.header.num_frames;
        }
    };
};

/// Parse an Aseprite file from a stream.
pub fn parse(allocator: std.mem.Allocator, stream: anytype) !raw.File {
    var buffered_reader = bufferedReader(1024, stream);
    var reader = buffered_reader.reader();

    const header = try raw.parseHeader(reader);
    std.log.debug("Header: {}", .{header});

    var frames = try allocator.alloc(raw.Frame, header.num_frames);
    for (0..header.num_frames) |i| {
        const frame = try raw.parseFrame(allocator, reader);
        frames[i] = frame;
    }

    return .{
        .allocator = allocator,
        .header = header,
        .frames = frames,
    };
}
