//! Buddy block and order arithmetic.
//! Operations use only values; they do not allocate, wait, or own free-list state.
//! See `docs/specs/algo/alloc/buddy.md`.

const std = @import("std");

pub const Error = error{
    InvalidRequest,
    Overflow,
};

pub const Block = struct {
    start: usize,
    order: u8,
};

/// Returns `1 << order` in caller-defined units.
pub fn blockSize(order: u8) Error!usize {
    if (order >= @bitSizeOf(usize)) return error.Overflow;
    return @as(usize, 1) << @intCast(order);
}

/// Returns the smallest order whose block size can contain `len`.
pub fn orderForLen(len: usize) Error!u8 {
    if (len == 0) return error.InvalidRequest;
    if (len == 1) return 0;
    const bits = @bitSizeOf(usize);
    const raw = bits - @clz(len - 1);
    if (raw >= bits) return error.Overflow;
    return @intCast(raw);
}

/// Returns whether `index` is in the half-open block extent.
pub fn contains(block: Block, index: usize) Error!bool {
    const size = try blockSize(block.order);
    const end = std.math.add(usize, block.start, size) catch return error.Overflow;
    return index >= block.start and index < end;
}

/// Returns the adjacent same-order block that shares the parent.
pub fn buddyOf(block: Block) Error!Block {
    const size = try blockSize(block.order);
    return .{ .start = block.start ^ size, .order = block.order };
}

/// Returns the containing block at `block.order + 1`.
pub fn parentOf(block: Block) Error!Block {
    if (block.order == std.math.maxInt(u8)) return error.Overflow;
    const parent_order: u8 = block.order + 1;
    const parent_size = try blockSize(parent_order);
    const parent_start = block.start & ~(parent_size - 1);
    _ = std.math.add(usize, parent_start, parent_size) catch return error.Overflow;
    return .{ .start = parent_start, .order = parent_order };
}

/// Returns the two children at `block.order - 1`.
pub fn split(block: Block) Error![2]Block {
    if (block.order == 0) return error.InvalidRequest;
    const child_order: u8 = block.order - 1;
    const child_size = try blockSize(child_order);
    const right_start = std.math.add(usize, block.start, child_size) catch return error.Overflow;
    return .{
        .{ .start = block.start, .order = child_order },
        .{ .start = right_start, .order = child_order },
    };
}

/// Returns whether two blocks have the same order and share a parent.
pub fn canCoalesce(left: Block, right: Block) bool {
    if (left.order != right.order) return false;
    const size = blockSize(left.order) catch return false;
    return (left.start ^ size) == right.start;
}
