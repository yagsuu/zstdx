//! Bounds-checked random byte access. See `docs/specs/bytes/access.md`.

const std = @import("std");

pub const Error = error{EndOfStream};

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

fn checkedEnd(bytes_len: usize, offset: usize, len: usize) Error!usize {
    if (offset > bytes_len) return error.EndOfStream;
    if (len > bytes_len - offset) return error.EndOfStream;

    return offset + len;
}
