//! AtomicCell contract tests. Spec: docs/specs/sync/atomic-cell.md.

const std = @import("std");

const stdx = @import("stdx");

const AtomicCell = stdx.sync.AtomicCell;
const testing = std.testing;

const EnumU8 = enum(u8) { a = 1, b = 2, c = 3 };
const EnumU32 = enum(u32) { a = 0xAAAA_5555, b = 0x5555_AAAA, _ };
const PackedU32 = packed struct(u32) { a: u16, b: u16 };

// Compile-only pins: every supported category instantiates.
comptime {
    _ = AtomicCell(u8);
    _ = AtomicCell(i8);
    _ = AtomicCell(u16);
    _ = AtomicCell(i16);
    _ = AtomicCell(u32);
    _ = AtomicCell(i32);
    _ = AtomicCell(u64);
    _ = AtomicCell(i64);
    _ = AtomicCell(usize);
    _ = AtomicCell(isize);
    _ = AtomicCell(bool);
    _ = AtomicCell(EnumU8);
    _ = AtomicCell(EnumU32);
    _ = AtomicCell(*u32);
    _ = AtomicCell(*const u32);
    _ = AtomicCell(?*u32);
    _ = AtomicCell(PackedU32);
}

// Compile-only layout pins (spec Required tests: size/align equivalence).
comptime {
    std.debug.assert(@sizeOf(AtomicCell(u32)) == @sizeOf(std.atomic.Value(u32)));
    std.debug.assert(@sizeOf(AtomicCell(u64)) == @sizeOf(std.atomic.Value(u64)));
    std.debug.assert(@sizeOf(AtomicCell(bool)) == @sizeOf(std.atomic.Value(bool)));
    std.debug.assert(@alignOf(AtomicCell(u64)) == @alignOf(std.atomic.Value(u64)));
    std.debug.assert(@alignOf(AtomicCell(u32)) == @alignOf(std.atomic.Value(u32)));
}

// Compile-only pins: arithmetic present on integer T, absent on non-integer T.
comptime {
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchAddAcqRel"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchAddAcquire"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchAddRelease"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchAddMonotonic"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchSubAcqRel"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchAndMonotonic"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchOrRelease"));
    std.debug.assert(@hasDecl(AtomicCell(u32), "fetchXorAcquire"));
}

// The arithmetic decls exist by name on non-integer T (they are `pub fn`s
// defined on the returned struct); their bodies compile only when
// referenced against an integer T. Referencing e.g. `AtomicCell(bool)
// .fetchAddMonotonic(&cell, true)` fires the guard in `requireInt` at
// src/sync/atomic_cell.zig, which is documented as compile-only-rejected
// below.

// Rejected shapes covered by @compileError in src/sync/atomic_cell.zig:
//   AtomicCell(f32)                                    -> "unsupported type category"
//   AtomicCell(f64)                                    -> "unsupported type category"
//   AtomicCell(u24)                                    -> "integer: width must be 8, 16, 32, or 64 bits"
//   AtomicCell(u128)                                   -> "integer: width must be 8, 16, 32, or 64 bits"
//   AtomicCell(struct { a: u32, b: u32 })              -> "non-packed struct is not a supported type category"
//   AtomicCell(packed struct(u24) { a: u12, b: u12 })  -> "packed struct backing integer: width must be 8, 16, 32, or 64 bits"
//   AtomicCell(union { a: u32, b: u32 })               -> "unsupported type category"
//   AtomicCell(?u32)                                   -> "optional T is only supported when it wraps a pointer"
//   AtomicCell(bool).fetchAddMonotonic(&c, true)       -> "arithmetic operations require an integer T"
// Zig has no runtime probe for @compileError; these are pinned by
// enumeration here.

test "unit: init and loadAcquire round-trip across supported categories" {
    inline for (.{ u8, i8, u16, i16, u32, i32, u64, i64, usize, isize }) |Int| {
        var cell: AtomicCell(Int) = .init(0);
        try testing.expectEqual(@as(Int, 0), cell.loadAcquire());
    }

    var b: AtomicCell(bool) = .init(true);
    try testing.expect(b.loadAcquire());
    try testing.expect(b.loadMonotonic());

    var e: AtomicCell(EnumU8) = .init(.b);
    try testing.expectEqual(EnumU8.b, e.loadAcquire());

    var storage: u32 = 42;
    var p: AtomicCell(*const u32) = .init(&storage);
    try testing.expectEqual(&storage, p.loadAcquire());
    try testing.expectEqual(@as(u32, 42), p.loadMonotonic().*);

    var op: AtomicCell(?*u32) = .init(null);
    try testing.expect(op.loadAcquire() == null);

    var ps: AtomicCell(PackedU32) = .init(.{ .a = 0x1234, .b = 0x5678 });
    const observed = ps.loadAcquire();
    try testing.expectEqual(@as(u16, 0x1234), observed.a);
    try testing.expectEqual(@as(u16, 0x5678), observed.b);
}

test "unit: storeRelease and loadAcquire round-trip preserves the value" {
    var cell: AtomicCell(i64) = .init(0);
    cell.storeRelease(-1_000_000);
    try testing.expectEqual(@as(i64, -1_000_000), cell.loadAcquire());
}

test "unit: storeMonotonic and loadMonotonic round-trip preserves the value" {
    var cell: AtomicCell(u64) = .init(0);
    cell.storeMonotonic(0xDEAD_BEEF_CAFE_F00D);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), cell.loadMonotonic());
}

test "unit: swap variants return the prior value and install the new one" {
    var acq_rel: AtomicCell(u32) = .init(1);
    try testing.expectEqual(@as(u32, 1), acq_rel.swapAcqRel(2));
    try testing.expectEqual(@as(u32, 2), acq_rel.loadAcquire());

    var acq: AtomicCell(u32) = .init(3);
    try testing.expectEqual(@as(u32, 3), acq.swapAcquire(4));
    try testing.expectEqual(@as(u32, 4), acq.loadAcquire());

    var rel: AtomicCell(u32) = .init(5);
    try testing.expectEqual(@as(u32, 5), rel.swapRelease(6));
    try testing.expectEqual(@as(u32, 6), rel.loadAcquire());

    var mono: AtomicCell(u32) = .init(7);
    try testing.expectEqual(@as(u32, 7), mono.swapMonotonic(8));
    try testing.expectEqual(@as(u32, 8), mono.loadAcquire());
}

test "unit: cmpxchgStrongAcqRel success stores and returns null" {
    var cell: AtomicCell(u32) = .init(100);
    try testing.expect(cell.cmpxchgStrongAcqRel(100, 200) == null);
    try testing.expectEqual(@as(u32, 200), cell.loadAcquire());
}

test "unit: cmpxchgStrongAcqRel mismatch reports observed value and does not store" {
    var cell: AtomicCell(u32) = .init(100);
    const observed = cell.cmpxchgStrongAcqRel(999, 200);
    try testing.expectEqual(@as(?u32, 100), observed);
    try testing.expectEqual(@as(u32, 100), cell.loadAcquire());
}

test "unit: cmpxchgStrongRelease mismatch leaves the cell unchanged" {
    var cell: AtomicCell(u32) = .init(7);
    try testing.expectEqual(@as(?u32, 7), cell.cmpxchgStrongRelease(8, 9));
    try testing.expectEqual(@as(u32, 7), cell.loadAcquire());

    try testing.expect(cell.cmpxchgStrongRelease(7, 9) == null);
    try testing.expectEqual(@as(u32, 9), cell.loadAcquire());
}

test "model: cmpxchgWeakAcqRel retry-loop drives the cell to the expected value" {
    // Single-threaded retry loop: the loop exits as soon as the cell holds
    // `expected`, which under no contention happens on the first attempt.
    var cell: AtomicCell(u32) = .init(11);
    const expected: u32 = 11;
    const new: u32 = 42;

    var current = cell.loadMonotonic();
    var attempts: usize = 0;
    while (attempts < 8) : (attempts += 1) {
        if (current != expected) {
            current = cell.loadMonotonic();
            continue;
        }
        if (cell.cmpxchgWeakAcqRel(current, new)) |observed| {
            current = observed;
            continue;
        }
        break;
    }
    try testing.expectEqual(@as(u32, new), cell.loadAcquire());
}

test "unit: every ordering variant of cmpxchgWeak and cmpxchgStrong exists and stores" {
    inline for (.{
        .{ "cmpxchgWeakAcqRel", "cmpxchgStrongAcqRel" },
        .{ "cmpxchgWeakAcquire", "cmpxchgStrongAcquire" },
        .{ "cmpxchgWeakRelease", "cmpxchgStrongRelease" },
        .{ "cmpxchgWeakMonotonic", "cmpxchgStrongMonotonic" },
    }) |pair| {
        var cell: AtomicCell(u32) = .init(0);
        // Weak may fail spuriously; loop bounded to keep the test finite.
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const observed = @field(AtomicCell(u32), pair[0])(&cell, 0, 1);
            if (observed == null) break;
        }
        try testing.expectEqual(@as(u32, 1), cell.loadAcquire());

        // Strong: single call.
        try testing.expect(@field(AtomicCell(u32), pair[1])(&cell, 1, 2) == null);
        try testing.expectEqual(@as(u32, 2), cell.loadAcquire());
    }
}

test "unit: fetchAdd variants return pre-op value and apply the delta" {
    inline for (.{ u32, u64 }) |Int| {
        var cell: AtomicCell(Int) = .init(10);
        try testing.expectEqual(@as(Int, 10), cell.fetchAddMonotonic(3));
        try testing.expectEqual(@as(Int, 13), cell.loadMonotonic());
        try testing.expectEqual(@as(Int, 13), cell.fetchAddAcqRel(4));
        try testing.expectEqual(@as(Int, 17), cell.loadMonotonic());
        try testing.expectEqual(@as(Int, 17), cell.fetchAddAcquire(1));
        try testing.expectEqual(@as(Int, 18), cell.loadMonotonic());
        try testing.expectEqual(@as(Int, 18), cell.fetchAddRelease(2));
        try testing.expectEqual(@as(Int, 20), cell.loadMonotonic());
    }
}

test "unit: fetchSub variants return pre-op value and apply the delta" {
    var cell: AtomicCell(u32) = .init(100);
    try testing.expectEqual(@as(u32, 100), cell.fetchSubMonotonic(5));
    try testing.expectEqual(@as(u32, 95), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 95), cell.fetchSubAcqRel(5));
    try testing.expectEqual(@as(u32, 90), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 90), cell.fetchSubAcquire(10));
    try testing.expectEqual(@as(u32, 80), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 80), cell.fetchSubRelease(20));
    try testing.expectEqual(@as(u32, 60), cell.loadMonotonic());
}

test "unit: fetchAnd variants return pre-op value and mask the cell" {
    var cell: AtomicCell(u32) = .init(0xFFFF_FFFF);
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), cell.fetchAndAcqRel(0xFFFF_0000));
    try testing.expectEqual(@as(u32, 0xFFFF_0000), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0xFFFF_0000), cell.fetchAndAcquire(0x00FF_0000));
    try testing.expectEqual(@as(u32, 0x00FF_0000), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x00FF_0000), cell.fetchAndRelease(0x0000_FFFF));
    try testing.expectEqual(@as(u32, 0x0000_0000), cell.loadMonotonic());

    var mono: AtomicCell(u64) = .init(0xFFFF_FFFF_FFFF_FFFF);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFF), mono.fetchAndMonotonic(0x0000_0000_FFFF_FFFF));
    try testing.expectEqual(@as(u64, 0x0000_0000_FFFF_FFFF), mono.loadMonotonic());
}

test "unit: fetchOr variants return pre-op value and set the mask" {
    var cell: AtomicCell(u32) = .init(0x0000_0001);
    try testing.expectEqual(@as(u32, 0x0000_0001), cell.fetchOrRelease(0x0000_0010));
    try testing.expectEqual(@as(u32, 0x0000_0011), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x0000_0011), cell.fetchOrMonotonic(0x0000_0100));
    try testing.expectEqual(@as(u32, 0x0000_0111), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x0000_0111), cell.fetchOrAcquire(0x0000_1000));
    try testing.expectEqual(@as(u32, 0x0000_1111), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x0000_1111), cell.fetchOrAcqRel(0x1111_0000));
    try testing.expectEqual(@as(u32, 0x1111_1111), cell.loadMonotonic());
}

test "unit: fetchXor variants return pre-op value and flip the mask" {
    var cell: AtomicCell(u32) = .init(0x00FF_00FF);
    try testing.expectEqual(@as(u32, 0x00FF_00FF), cell.fetchXorAcquire(0x00FF_FF00));
    try testing.expectEqual(@as(u32, 0x0000_FFFF), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x0000_FFFF), cell.fetchXorRelease(0xFFFF_FFFF));
    try testing.expectEqual(@as(u32, 0xFFFF_0000), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0xFFFF_0000), cell.fetchXorMonotonic(0xFFFF_0000));
    try testing.expectEqual(@as(u32, 0x0000_0000), cell.loadMonotonic());
    try testing.expectEqual(@as(u32, 0x0000_0000), cell.fetchXorAcqRel(0xAAAA_5555));
    try testing.expectEqual(@as(u32, 0xAAAA_5555), cell.loadMonotonic());
}

test "stress: fetchAddMonotonic across N threads yields exactly N*K increments" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const Ctx = struct {
        cell: *AtomicCell(u64),
        iterations: u64,

        fn run(ctx: @This()) void {
            var i: u64 = 0;
            while (i < ctx.iterations) : (i += 1) {
                _ = ctx.cell.fetchAddMonotonic(1);
            }
        }
    };

    const thread_count: u64 = 4;
    const iterations: u64 = 10_000;

    var cell: AtomicCell(u64) = .init(0);
    var threads: [4]std.Thread = undefined;

    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, Ctx.run, .{Ctx{ .cell = &cell, .iterations = iterations }});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }

    try testing.expectEqual(thread_count * iterations, cell.loadAcquire());
}

test "model: acquire/release synchronizes-with a paired payload write" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const Ctx = struct {
        payload: *u64,
        flag: *AtomicCell(bool),

        fn producer(ctx: @This()) void {
            ctx.payload.* = 0xC0FFEE;
            ctx.flag.storeRelease(true);
        }

        fn consumer(ctx: @This(), out: *u64) void {
            while (!ctx.flag.loadAcquire()) std.atomic.spinLoopHint();
            out.* = ctx.payload.*;
        }
    };

    var trials: usize = 0;
    while (trials < 64) : (trials += 1) {
        var payload: u64 = 0;
        var flag: AtomicCell(bool) = .init(false);
        var observed: u64 = 0;

        const ctx = Ctx{ .payload = &payload, .flag = &flag };
        var producer_thread = try std.Thread.spawn(.{}, Ctx.producer, .{ctx});
        var consumer_thread = try std.Thread.spawn(.{}, Ctx.consumer, .{ ctx, &observed });
        producer_thread.join();
        consumer_thread.join();

        try testing.expectEqual(@as(u64, 0xC0FFEE), observed);
    }
}

test "unit: fromStd observes stores written through the underlying std.atomic.Value" {
    var std_cell: std.atomic.Value(u32) = .init(0);
    const cell = AtomicCell(u32).fromStd(&std_cell);

    std_cell.store(7, .release);
    try testing.expectEqual(@as(u32, 7), cell.loadAcquire());

    cell.storeRelease(11);
    try testing.expectEqual(@as(u32, 11), std_cell.load(.acquire));
}

test "unit: fromStdConst observes stores written through the underlying std.atomic.Value" {
    var std_cell: std.atomic.Value(u32) = .init(0);
    const cell_const = AtomicCell(u32).fromStdConst(&std_cell);

    std_cell.store(99, .release);
    try testing.expectEqual(@as(u32, 99), cell_const.loadAcquire());
    try testing.expectEqual(@as(u32, 99), cell_const.loadMonotonic());
}

test "contract: layout matches std.atomic.Value at runtime" {
    // Compile-time pins live above; this test surfaces the invariant in the
    // runtime test list so a failure is legible in the test output.
    try testing.expectEqual(@sizeOf(std.atomic.Value(u32)), @sizeOf(AtomicCell(u32)));
    try testing.expectEqual(@sizeOf(std.atomic.Value(u64)), @sizeOf(AtomicCell(u64)));
    try testing.expectEqual(@sizeOf(std.atomic.Value(bool)), @sizeOf(AtomicCell(bool)));
    try testing.expectEqual(@alignOf(std.atomic.Value(u64)), @alignOf(AtomicCell(u64)));
}
