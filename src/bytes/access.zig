//! Bounds-checked random byte access. See `docs/specs/bytes/access.md`.

const std = @import("std");

const unaligned = @import("unaligned.zig");

pub const Error = error{EndOfStream};

fn checkedEnd(bytes_len: usize, offset: usize, len: usize) Error!usize {
    if (offset > bytes_len) return error.EndOfStream;
    if (len > bytes_len - offset) return error.EndOfStream;

    return offset + len;
}

pub fn load(comptime T: type, bytes: []const u8, offset: usize) Error!T {
    const end = try checkedEnd(bytes.len, offset, @sizeOf(T));
    const window = bytes[offset..end][0..@sizeOf(T)];
    return unaligned.loadUnaligned(T, window);
}

pub fn store(comptime T: type, bytes: []u8, offset: usize, value: T) Error!void {
    const end = try checkedEnd(bytes.len, offset, @sizeOf(T));
    const window = bytes[offset..end][0..@sizeOf(T)];
    unaligned.storeUnaligned(T, window, value);
}

pub fn loadSlice(bytes: []const u8, offset: usize, len: usize) Error![]const u8 {
    const end = try checkedEnd(bytes.len, offset, len);
    return bytes[offset..end];
}

pub fn storeSlice(bytes: []u8, offset: usize, src: []const u8) Error!void {
    const end = try checkedEnd(bytes.len, offset, src.len);
    const dest = bytes[offset..end];
    if (@intFromPtr(dest.ptr) <= @intFromPtr(src.ptr)) {
        std.mem.copyForwards(u8, dest, src);
    } else {
        std.mem.copyBackwards(u8, dest, src);
    }
}

pub fn loadTail(bytes: []const u8, offset: usize) Error![]const u8 {
    _ = try checkedEnd(bytes.len, offset, 0);
    return bytes[offset..];
}
