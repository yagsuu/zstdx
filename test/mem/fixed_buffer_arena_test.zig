//! Fixed buffer arena contract tests. Spec: docs/specs/mem/fixed-buffer-arena.md.

const std = @import("std");

const zstdx = @import("zstdx");

const mem = zstdx.mem;

const FixedBufferArena = mem.FixedBufferArena;

const testing = std.testing;

test "unit: arena reports capacity/used/remaining and zero allocation" {
    var storage: [32]u8 = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    try testing.expectEqual(@as(usize, 32), arena.capacity());
    try testing.expectEqual(@as(usize, 0), arena.used());
    try testing.expectEqual(@as(usize, 32), arena.remaining());
    const zero = try arena.allocBytes(0);
    try testing.expectEqual(@as(usize, 0), zero.len);
    try testing.expectEqual(@as(usize, 0), arena.used());
}

test "unit: arena allocation lifecycle with mark/restore/reset" {
    var storage: [32]u8 = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    const first = try arena.allocBytes(3);
    first[0] = 9;
    const checkpoint = arena.mark();
    const aligned = try arena.allocAlignedBytes(4, 8);
    try testing.expect(mem.isAligned(usize, @intFromPtr(aligned.ptr), 8));
    arena.restore(checkpoint);
    try testing.expectEqual(checkpoint.index, arena.used());
    try testing.expectEqual(@as(u8, 9), first[0]);
    arena.reset();
    try testing.expectEqual(@as(usize, 0), arena.used());
}

test "unit: arena leaves index unchanged on every error path" {
    var storage: [32]u8 = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    _ = try arena.allocBytes(3);
    const before = arena.used();
    try testing.expectError(error.InvalidAlignment, arena.allocAlignedBytes(1, 3));
    try testing.expectError(error.InvalidAlignment, arena.allocAlignedBytes(0, 3));
    try testing.expectError(error.OutOfMemory, arena.allocBytes(100));
    try testing.expectEqual(before, arena.used());
}

test "unit: arena typed allocation respects @alignOf(T)" {
    const Extern = extern struct { a: u8, b: u32 };
    var storage: [64]u8 align(8) = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    const p = try arena.alloc(u32);
    p.* = 42;
    try testing.expect(mem.isAligned(usize, @intFromPtr(p), @alignOf(u32)));
    const ex = try arena.alloc(Extern);
    try testing.expect(mem.isAligned(usize, @intFromPtr(ex), @alignOf(Extern)));
}

test "unit: arena allocSlice detects byte-count overflow" {
    var storage: [64]u8 = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    const slice = try arena.allocSlice(u8, 4);
    slice[0] = 1;
    try testing.expectError(error.Overflow, arena.allocSlice(u64, std.math.maxInt(usize)));
}

test "unit: arena allocator view drives std.ArrayListUnmanaged until OutOfMemory" {
    var storage: [256]u8 align(8) = undefined;
    var arena = FixedBufferArena.wrap(&storage);
    var list = std.ArrayListUnmanaged(u32).empty;
    const allocator = arena.allocator();
    try list.append(allocator, 1);
    try list.append(allocator, 2);
    while (list.append(allocator, 3)) {} else |err| try testing.expectEqual(error.OutOfMemory, err);
}
