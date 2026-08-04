//! Arena contract tests. See `docs/specs/mem/arena/bounded.md` and
//! `docs/specs/mem/arena/static.md`.

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

test "unit: Arena.Bounded.wrap(&.{}) is a valid zero-capacity arena" {
    var arena = Arena.Bounded.wrap(&.{});
    try testing.expectEqual(@as(usize, 0), arena.capacity());
    try testing.expectEqual(@as(usize, 0), arena.used());
    try testing.expectEqual(@as(usize, 0), arena.remaining());
    try testing.expectEqual(@as(usize, 0), (try arena.allocBytes(0)).len);
    try testing.expectError(error.OutOfMemory, arena.allocBytes(1));
}

test "unit: Arena.Bounded.remainingBytes spans full buffer at init and shrinks with use" {
    var storage: [16]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    try testing.expectEqual(@as(usize, 16), arena.remainingBytes().len);
    const taken = try arena.allocBytes(5);
    try testing.expectEqual(@as(usize, 11), arena.remainingBytes().len);
    try testing.expectEqual(arena.buffer[arena.used()..].ptr, arena.remainingBytes().ptr);
    _ = taken;
}

test "unit: Arena.Bounded.allocSlice returns contiguous len elements" {
    var storage: [64]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    const items = try arena.allocSlice(u32, 4);
    try testing.expectEqual(@as(usize, 4), items.len);
    items[0] = 0xaa;
    items[3] = 0xbb;
    try testing.expectEqual(@as(usize, @sizeOf(u32) * 3), @intFromPtr(&items[3]) - @intFromPtr(&items[0]));
}

test "unit: Arena.Bounded.alloc satisfies @alignOf(T) over an unaligned subslice" {
    var storage: [128]u8 = undefined;
    // Carve an intentionally byte-aligned subslice that starts at an odd
    // address relative to storage.ptr.
    var arena = Arena.Bounded.wrap(storage[1..]);
    const p = try arena.alloc(u64);
    try testing.expect(mem.isAligned(usize, @intFromPtr(p), @alignOf(u64)));
}

test "unit: Arena.Bounded.allocAlignedBytes(_, 1) is a byte-aligned no-op" {
    var storage: [16]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    const before = arena.used();
    const taken = try arena.allocAlignedBytes(3, 1);
    try testing.expectEqual(@as(usize, 3), taken.len);
    try testing.expectEqual(before + 3, arena.used());
}

test "unit: Arena.Bounded.assertValid catches a corrupted index" {
    var storage: [8]u8 = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    try testing.expect(arena.isValid());
    arena.index = arena.buffer.len + 1; // simulate corruption
    try testing.expect(!arena.isValid());
}

test "unit: Arena.Bounded.allocator failure leaves index unchanged" {
    var storage: [16]u8 align(8) = undefined;
    var arena = Arena.Bounded.wrap(&storage);
    _ = try arena.allocBytes(4);
    const before = arena.used();
    var list = std.ArrayListUnmanaged(u64).empty;
    const allocator = arena.allocator();
    // First append succeeds; subsequent ones must hit OutOfMemory before
    // mutating arena.index inconsistently.
    while (list.append(allocator, 1)) {} else |err| try testing.expectEqual(error.OutOfMemory, err);
    try testing.expect(arena.used() >= before);
    // After OOM, used() must not exceed capacity.
    try testing.expect(arena.used() <= arena.capacity());
}

test "unit: Arena.Static.remainingBytes spans the full inline buffer at init" {
    var arena = Arena.Static(32).init();
    try testing.expectEqual(@as(usize, 32), arena.remainingBytes().len);
    _ = try arena.allocBytes(5);
    try testing.expectEqual(@as(usize, 27), arena.remainingBytes().len);
}

test "unit: Arena.Static.allocSlice returns contiguous len elements" {
    var arena = Arena.Static(64).init();
    const items = try arena.allocSlice(u32, 4);
    try testing.expectEqual(@as(usize, 4), items.len);
    items[0] = 1;
    items[3] = 4;
    try testing.expectEqual(@as(usize, @sizeOf(u32) * 3), @intFromPtr(&items[3]) - @intFromPtr(&items[0]));
}

test "unit: Arena.Static.assertValid catches a corrupted index" {
    var arena = Arena.Static(16).init();
    try testing.expect(arena.isValid());
    arena.index = 17;
    try testing.expect(!arena.isValid());
}
