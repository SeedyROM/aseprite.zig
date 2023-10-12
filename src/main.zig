const std = @import("std");
const fs = std.fs;
const io = std.io;

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
    number_of_colors: u16,
    pixel_width: u8,
    pixel_height: u8,
    grid_posiiton_x: i16,
    grid_position_y: i16,
    grid_width: u16,
    grid_height: u16,
};

/// The header of a frame.
pub const FrameHeader = struct {
    size: u32,
    magic: u16,
    _old_num_chunks: u16,
    duration: u16,
    num_chunks: u32,
};

/// The chunk types in an Aseprite file.
pub const ChunkType = enum(u16) {
    layer = 0x2004,
    cel = 0x2005,
    cel_extra = 0x2006,
    color_profile = 0x2007,
    // TODO(SeedyROM): Support the rest of the chunk types.
};

/// The data in a chunk.
pub const ChunkData = union(enum) {
    layer: LayerChunk,
    // cel: CelChunk,
    // cel_extra: CelExtraChunk,
    // color_profile: ColorProfileChunk,
    // TODO(SeedyROM): Support the rest of the chunk types.
};

/// The flags in a layer.
pub const LayerFlags = enum(u16) {
    visible = 1,
    editable = 2,
    lock_movement = 4,
    background = 8,
    prefer_linked_cels = 16,
    display_collapsed = 32,
    is_reference_layer = 64,
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

/// The chunk types in an Aseprite file.
pub const Chunk = struct {
    size: u32,
    chunk_type: ChunkType,
    data: ChunkData,
};

/// A frame in an Aseprite file.
pub const Frame = struct {
    header: FrameHeader,
    chunks: []Chunk,
};

fn bufferedReader(
    comptime buffer_size: comptime_int,
    stream: anytype,
) io.BufferedReader(buffer_size, @TypeOf(stream)) {
    return .{ .unbuffered_reader = stream };
}

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

    const number_of_colors = try reader.readInt(u16, .Little);
    const pixel_width = try reader.readInt(u8, .Little);
    const pixel_height = try reader.readInt(u8, .Little);
    const grid_posiiton_x = try reader.readInt(i16, .Little);
    const grid_position_y = try reader.readInt(i16, .Little);
    const grid_width = try reader.readInt(u16, .Little);
    const grid_height = try reader.readInt(u16, .Little);

    // Skip 84 bytes of reserved data.
    _ = try reader.skipBytes(84, .{});

    // Check the magic number.
    if (magic != 0xA5E0) {
        return error.InvalidHeader;
    }

    return Header{
        .size = size,
        .magic = magic,
        .num_frames = num_frames,
        .width_in_pixels = width_in_pixels,
        .height_in_pixels = height_in_pixels,
        .color_depth = color_depth,
        .flags = flags,
        ._deprecated_speed = _deprecated_speed,
        .transparent_color_index = transparent_color_index,
        .number_of_colors = number_of_colors,
        .pixel_width = pixel_width,
        .pixel_height = pixel_height,
        .grid_posiiton_x = grid_posiiton_x,
        .grid_position_y = grid_position_y,
        .grid_width = grid_width,
        .grid_height = grid_height,
    };
}

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

    return FrameHeader{
        .size = size,
        .magic = magic,
        ._old_num_chunks = _old_num_chunks,
        .duration = duration,
        .num_chunks = num_chunks,
    };
}

fn parseLayerChunk(allocator: std.mem.Allocator, reader: anytype) !ChunkData {
    const flags = try reader.readEnum(LayerFlags, .Little);
    const _type = try reader.readEnum(LayerType, .Little);
    const child_level = try reader.readInt(u16, .Little);
    const default_width = try reader.readInt(u16, .Little);
    const default_height = try reader.readInt(u16, .Little);
    const blend_mode = try reader.readEnum(LayerBlendMode, .Little);
    const opacity = try reader.readInt(u8, .Little);
    const name_size = try reader.readInt(u16, .Little);

    // Allocate the name buffer.
    const name = try allocator.alloc(u8, name_size);
    _ = try reader.read(name);

    return ChunkData{
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

fn parseChunk(allocator: std.mem.Allocator, reader: anytype) !?Chunk {
    // Get the chunk size.
    const size = try reader.readInt(u32, .Little);
    std.log.debug("Next chunk size: {any}", .{size});

    // Check if the chunk is too small to be valid.
    if (size < 6) {
        return error.InvalidChunkSize;
    }

    // Get the chunk type.
    const chunk_type = try reader.readEnum(ChunkType, .Little);
    std.log.debug("Next chunk type: {any}", .{chunk_type});

    var data: ChunkData = undefined;
    switch (chunk_type) {
        .layer => {
            data = try parseLayerChunk(allocator, reader);
        },
        else => {
            std.log.debug("Skipping chunk of type {any}", .{chunk_type});

            // Skip the rest of the chunk.
            _ = try reader.skipBytes(size - 6, .{});
            return null;
        },
    }

    return Chunk{
        .size = size,
        .chunk_type = chunk_type,
        .data = data,
    };
}

fn parseFrame(allocator: std.mem.Allocator, reader: anytype) !Frame {
    const header = try parseFrameHeader(reader);
    std.log.debug("FrameHeader: {any}", .{header});

    var chunks = try allocator.alloc(Chunk, header.num_chunks);

    for (0..header.num_chunks) |i| {
        const chunk = try parseChunk(allocator, reader);
        if (chunk == null) {
            continue;
        }

        std.log.debug("Chunk: {any}", .{chunk.?});
        chunks[i] = chunk.?;
    }

    return Frame{
        .header = header,
        .chunks = chunks,
    };
}

/// Parse an Aseprite file from a stream.
pub fn parse(allocator: std.mem.Allocator, stream: anytype) !void {
    var buffered_reader = bufferedReader(1024, stream);
    var reader = buffered_reader.reader();

    const header = try parseHeader(reader);
    std.log.debug("Header: {any}", .{header});

    var frames = try allocator.alloc(Frame, header.num_frames);
    for (0..header.num_frames) |i| {
        const frame = try parseFrame(allocator, reader);
        frames[i] = frame;
    }
}
