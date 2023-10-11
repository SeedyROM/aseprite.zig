const std = @import("std");
const fs = std.fs;
const io = std.io;

pub const Header = extern struct {
    size: u32,
    magic: u16,
    num_frames: u16,
    width_in_pixels: u16,
    height_in_pixels: u16,
    color_depth: enum(u8) {
        indexed = 8,
        grayscale = 16,
        rgba = 32,
    },
    flags: u32,
    _deprecated_speed: u16,
    _0: [2]u32,
    transparent_color_index: u8,
    _1: [3]u8,
    number_of_colors: u16,
    pixel_width: u8,
    pixel_height: u8,
    grid_width: u16,
    grid_height: u16,
    _2: [84]u8,
};

pub const FrameHeader = extern struct {
    size: u32,
    magic: u16,
    _old_num_chunks: u16,
    duration: u16,
    _0: [2]u8,
    num_chunks: u32,
};

pub const ChunkType = enum(u16) {
    layer = 0x2004,
    cel = 0x2005,
    cel_extra = 0x2006,
    color_profile = 0x2007,
    // TODO(SeedyROM): Support the rest of the chunk types.
};

pub const ChunkData = union(enum(ChunkType)) {
    layer: LayerChunk,
    // cel: CelChunk,
    // cel_extra: CelExtraChunk,
    // color_profile: ColorProfileChunk,
    // TODO(SeedyROM): Support the rest of the chunk types.
};

pub const LayerChunk = extern struct {
    flags: enum(u16) {
        visible = 1,
        editable = 2,
        lock_movement = 4,
        background = 8,
        prefer_linked_cels = 16,
        display_collapsed = 32,
        is_reference_layer = 64,
    },
    type: enum(u16) {
        normal,
        group,
        tilemap,
    },
    child_level: u16,
    default_width: u16,
    default_height: u16,
    blend_mode: enum(u16) {
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
    },
    opacity: u8,
    _0: [3]u8,
    name: extern struct {
        size: u16,
        data: [0]u8,
    },
    // TODO(SeedyROM): Possibly have the tilset index???
};

pub const Chunk = extern struct {
    size: u32,
    chunk_type: ChunkType,
};

fn bufferedReader(
    comptime buffer_size: comptime_int,
    stream: anytype,
) io.BufferedReader(buffer_size, @TypeOf(stream)) {
    return .{ .unbuffered_reader = stream };
}

pub fn parse(allocator: std.mem.Allocator, stream: anytype) !void {
    var buffered_reader = bufferedReader(1024, stream);
    var reader = buffered_reader.reader();

    const header = try reader.readStruct(Header);

    if (header.magic != 0xA5E0) {
        return error.InvalidHeader;
    }

    std.debug.print("Header: {}\n", .{header});

    var frames = std.ArrayList(FrameHeader).init(allocator);
    _ = frames;

    const frame_header = try reader.readStruct(FrameHeader);
    if (frame_header.magic != 0xF1FA) {
        return error.InvalidFrameHeader;
    }

    std.debug.print("FrameHeader: {}\n", .{frame_header});
}
