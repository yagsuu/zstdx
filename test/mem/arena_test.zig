//! Arena contract tests. Specs: docs/specs/mem/arena-bounded.md and
//! docs/specs/mem/arena-static.md.

const std = @import("std");

const stdx = @import("stdx");

const mem = stdx.mem;

const Arena = mem.Arena;

const testing = std.testing;

test "unit: Arena.Bounded reports capacity/used/remaining and zero allocation" {
    var storage: [32]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    try testing.expectEqual(@as(usize, 32), arena.capacity());
    try testing.expectEqual(@as(usize, 0), arena.used());
    try testing.expectEqual(@as(usize, 32), arena.remaining());
    const zero = try arena.allocBytes(0);
    try testing.expectEqual(@as(usize, 0), zero.len);
    try testing.expectEqual(@as(usize, 0), arena.used());
}

test "unit: Arena.Bounded allocation lifecycle with mark/restore/reset" {
    var storage: [32]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
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

test "unit: Arena.Bounded leaves index unchanged on every error path" {
    var storage: [32]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    _ = try arena.allocBytes(3);
    const before = arena.used();
    try testing.expectError(error.InvalidAlignment, arena.allocAlignedBytes(1, 3));
    try testing.expectError(error.InvalidAlignment, arena.allocAlignedBytes(0, 3));
    try testing.expectError(error.OutOfMemory, arena.allocBytes(100));
    try testing.expectEqual(before, arena.used());
}

test "unit: Arena.Bounded typed allocation respects @alignOf(T)" {
    const Extern = extern struct { a: u8, b: u32 };
    var storage: [64]u8 align(8) = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    const p = try arena.alloc(u32);
    p.* = 42;
    try testing.expect(mem.isAligned(usize, @intFromPtr(p), @alignOf(u32)));
    const ex = try arena.alloc(Extern);
    try testing.expect(mem.isAligned(usize, @intFromPtr(ex), @alignOf(Extern)));
}

test "unit: Arena.Bounded allocSlice detects byte-count overflow" {
    var storage: [64]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    const slice = try arena.allocSlice(u8, 4);
    slice[0] = 1;
    try testing.expectError(error.Overflow, arena.allocSlice(u64, std.math.maxInt(usize)));
}

test "unit: Arena.Bounded allocator view drives std.ArrayListUnmanaged until OutOfMemory" {
    var storage: [256]u8 align(8) = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    var list = std.ArrayListUnmanaged(u32).empty;
    const allocator = arena.allocator();
    try list.append(allocator, 1);
    try list.append(allocator, 2);
    while (list.append(allocator, 3)) {} else |err| try testing.expectEqual(error.OutOfMemory, err);
}

test "unit: Arena.Static init reports byte_capacity and starts empty" {
    var arena = Arena.Static(64).init();
    try testing.expectEqual(@as(usize, 64), @TypeOf(arena).byte_capacity);
    try testing.expectEqual(@as(usize, 64), arena.capacity());
    try testing.expectEqual(@as(usize, 0), arena.used());
    try testing.expectEqual(@as(usize, 64), arena.remaining());
}

test "unit: Arena.Static(0) reports OutOfMemory for any non-zero allocation" {
    var arena = Arena.Static(0).init();
    try testing.expectEqual(@as(usize, 0), arena.capacity());
    const zero = try arena.allocBytes(0);
    try testing.expectEqual(@as(usize, 0), zero.len);
    try testing.expectError(error.OutOfMemory, arena.allocBytes(1));
    try testing.expectError(error.OutOfMemory, arena.alloc(u32));
}

test "unit: Arena.Static bumps and rolls back through mark/restore/reset" {
    var arena = Arena.Static(64).init();
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

test "unit: Arena.Static leaves index unchanged on error paths" {
    var arena = Arena.Static(32).init();
    _ = try arena.allocBytes(3);
    const before = arena.used();
    try testing.expectError(error.InvalidAlignment, arena.allocAlignedBytes(1, 3));
    try testing.expectError(error.OutOfMemory, arena.allocBytes(100));
    try testing.expectError(error.Overflow, arena.allocSlice(u64, std.math.maxInt(usize)));
    try testing.expectEqual(before, arena.used());
}

test "unit: Arena.Static typed allocation respects @alignOf(T)" {
    const Extern = extern struct { a: u8, b: u32 };
    var arena = Arena.Static(128).init();
    const p = try arena.alloc(u32);
    p.* = 42;
    try testing.expect(mem.isAligned(usize, @intFromPtr(p), @alignOf(u32)));
    const ex = try arena.alloc(Extern);
    try testing.expect(mem.isAligned(usize, @intFromPtr(ex), @alignOf(Extern)));
}

test "unit: Arena.Static allocator view drives std.ArrayListUnmanaged until OutOfMemory" {
    var arena = Arena.Static(256).init();
    var list = std.ArrayListUnmanaged(u32).empty;
    const allocator = arena.allocator();
    try list.append(allocator, 1);
    try list.append(allocator, 2);
    while (list.append(allocator, 3)) {} else |err| try testing.expectEqual(error.OutOfMemory, err);
}

