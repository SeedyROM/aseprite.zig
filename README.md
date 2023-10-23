# aseprite.zig

[![Build Status](https://travis-ci.org/SeedyROM/aseprite.zig.svg?branch=main)](https://travis-ci.org/SeedyROM/aseprite.zig)

This is a [Zig](https://ziglang.org/) library to read (possibly write) and work with [Aseprite](https://www.aseprite.org/) files.

## Examples:

For now please read the tests in `src/aseprite.zig` for example usage.

## Goals:

- [x] Support a large subset of the Aseprite file format
    - [x] Load images from .aseprite files
      - [x] Handle zlib-compressed chunks and raw chunks
      - [x] Handle all color modes
    - [ ] Load tilemaps from .aseprite files 
- [x] Create a simple but powerful API to work with Aseprite files
  - [x] Create some more simple wrappers around STB to pack images into texture atlases/spritesheets
  - [x] Create texture atlases from Aseprite files
- [ ] Make this a zig module that can be used with the native package manager
  - [ ] Handle dependencies from local c libraries

## Non-goals (initially):

- [ ] Support the entire Aseprite file format
- [ ] Write .aseprite files
