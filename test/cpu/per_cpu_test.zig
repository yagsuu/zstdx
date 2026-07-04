//! PerCpu contract tests. Spec: docs/specs/cpu/per-cpu.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const PerCpu = stdx.cpu.PerCpu;
const CachePad = stdx.mem.CachePad;
const AtomicCell = stdx.sync.AtomicCell;

const cache_line = std.atomic.cache_line;
const testing = std.testing;

test "unit: comptime layout invariants on legal Static instantiations" {
    comptime {
        const Sut = PerCpu.Static(u64, 4);
        std.debug.assert(@sizeOf(Sut) == 4 * @sizeOf(Sut.Padded));
        std.debug.assert(@alignOf(Sut.Padded) == @alignOf(CachePad(u64)));
        std.debug.assert(@sizeOf(Sut.Padded) == @sizeOf(CachePad(u64)));
        std.debug.assert(@alignOf(Sut.Padded) == cache_line);
    }
}

// Compile-error cases — rejected shapes guarded by `@compileError` in
// `src/cpu/per_cpu.zig`, which Zig cannot exercise at runtime:
//   - `PerCpu.Static(u64, 0)` — "capacity N must be > 0"

test "unit: Static.init(0) yields get(i) == 0 for every slot" {
    var sut = PerCpu.Static(u64, 8).init(0);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        try testing.expectEqual(@as(u64, 0), sut.get(i));
    }
}

test "unit: Static.init(default) fills every slot with default" {
    var sut = PerCpu.Static(u32, 5).init(0xABCD_1234);
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try testing.expectEqual(@as(u32, 0xABCD_1234), sut.get(i));
    }
}

fn makeDouble(index: usize) u64 {
    return @as(u64, index) * 2;
}

test "unit: Static.initFn calls make once per slot in index order" {
    var sut = PerCpu.Static(u64, 6).initFn(makeDouble);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try testing.expectEqual(@as(u64, i) * 2, sut.get(i));
    }
}

fn fillWithIndex(index: usize, slot: *u64) void {
    slot.* = index;
}

test "unit: Static.initEach writes each slot in index order via pointer" {
    var sut = PerCpu.Static(u64, 6).initEach(fillWithIndex);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try testing.expectEqual(@as(u64, i), sut.get(i));
    }
}

// Module-scope counters observe call order for `initFn` / `initEach`.
var initfn_calls: [8]usize = @splat(0);
var initfn_next: usize = 0;

fn recordCall(index: usize) u64 {
    initfn_calls[initfn_next] = index;
    initfn_next += 1;
    return @as(u64, index) * 10;
}

test "contract: Static.initFn calls make once per slot in strict index order" {
    initfn_calls = @splat(0);
    initfn_next = 0;

    _ = PerCpu.Static(u64, 6).initFn(recordCall);
    try testing.expectEqual(@as(usize, 6), initfn_next);
    for (initfn_calls[0..6], 0..) |seen, expected| {
        try testing.expectEqual(expected, seen);
    }
}

var initeach_calls: [8]usize = @splat(0);
var initeach_next: usize = 0;

fn recordEach(index: usize, slot: *u64) void {
    initeach_calls[initeach_next] = index;
    initeach_next += 1;
    slot.* = @as(u64, index) * 100;
}

test "contract: Static.initEach calls fill once per slot in strict index order" {
    initeach_calls = @splat(0);
    initeach_next = 0;

    var sut = PerCpu.Static(u64, 6).initEach(recordEach);
    try testing.expectEqual(@as(usize, 6), initeach_next);
    for (initeach_calls[0..6], 0..) |seen, expected| {
        try testing.expectEqual(expected, seen);
    }
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try testing.expectEqual(@as(u64, i) * 100, sut.get(i));
    }
}

test "contract: Bounded.initFn / initEach call make once per slot in strict index order" {
    const B = PerCpu.Bounded(u64);
    var storage: [5]B.Padded = undefined;

    initfn_calls = @splat(0);
    initfn_next = 0;
    _ = B.initFn(&storage, recordCall);
    try testing.expectEqual(@as(usize, 5), initfn_next);
    for (initfn_calls[0..5], 0..) |seen, expected| {
        try testing.expectEqual(expected, seen);
    }

    var storage_each: [5]B.Padded = undefined;
    initeach_calls = @splat(0);
    initeach_next = 0;
    _ = B.initEach(&storage_each, recordEach);
    try testing.expectEqual(@as(usize, 5), initeach_next);
    for (initeach_calls[0..5], 0..) |seen, expected| {
        try testing.expectEqual(expected, seen);
    }
}

test "unit: Static.initUndefined has capacity()/len() equal to N" {
    var sut = PerCpu.Static(u64, 8).initUndefined();
    try testing.expectEqual(@as(usize, 8), sut.capacity());
    try testing.expectEqual(@as(usize, 8), sut.len());
    // Payload is undefined; write each slot before reading.
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        sut.getPtr(i).* = i + 1;
    }
    i = 0;
    while (i < 8) : (i += 1) {
        try testing.expectEqual(@as(u64, i + 1), sut.get(i));
    }
}

test "unit: Static.getPtr(i).* = v is observable via Static.get(i)" {
    var sut = PerCpu.Static(u64, 8).init(0);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        sut.getPtr(i).* = i;
    }
    i = 0;
    while (i < 8) : (i += 1) {
        try testing.expectEqual(@as(u64, i), sut.get(i));
    }
}

test "unit: Static.at rejects OOB and returns stored value for last index" {
    var sut = PerCpu.Static(u64, 4).init(0);
    sut.getPtr(3).* = 0xFACE;
    try testing.expectEqual(@as(u64, 0xFACE), try sut.at(3));
    try testing.expectError(error.OutOfBounds, sut.at(4));
    try testing.expectError(error.OutOfBounds, sut.at(1000));
}

test "unit: Static.atPtr rejects OOB and returns a mutable pointer otherwise" {
    var sut = PerCpu.Static(u64, 4).init(0);
    const p = try sut.atPtr(3);
    p.* = 0xC0FFEE;
    try testing.expectEqual(@as(u64, 0xC0FFEE), sut.get(3));
    try testing.expectError(error.OutOfBounds, sut.atPtr(4));
}

test "unit: Static.capacity and len both return N" {
    var sut = PerCpu.Static(u32, 12).init(0);
    try testing.expectEqual(@as(usize, 12), sut.capacity());
    try testing.expectEqual(@as(usize, 12), sut.len());
}

test "unit: Static.slots yields exactly capacity() elements; slots[i].value == get(i)" {
    var sut = PerCpu.Static(u64, 6).initFn(makeDouble);
    const view = sut.slots();
    try testing.expectEqual(@as(usize, 6), view.len);
    for (view, 0..) |slot, i| {
        try testing.expectEqual(sut.get(i), slot.value);
    }
}

test "unit: Static.slotsConst returns a []const Padded of capacity()" {
    var sut = PerCpu.Static(u64, 6).initFn(makeDouble);
    const view = sut.slotsConst();
    try testing.expectEqual(@as(usize, 6), view.len);
    var sum: u64 = 0;
    for (view) |slot| sum += slot.value;
    try testing.expectEqual(@as(u64, 0 + 2 + 4 + 6 + 8 + 10), sum);
}

test "contract: adjacent Static slots sit exactly one padded stride apart" {
    var sut = PerCpu.Static(u64, 8).init(0);
    const stride_expected = @sizeOf(PerCpu.Static(u64, 8).Padded);
    var i: usize = 0;
    while (i + 1 < 8) : (i += 1) {
        const lo = @intFromPtr(sut.getPtr(i));
        const hi = @intFromPtr(sut.getPtr(i + 1));
        const stride = hi - lo;
        try testing.expectEqual(stride_expected, stride);
        try testing.expectEqual(@as(usize, 0), stride % cache_line);
    }
}

test "contract: assertValid succeeds on a fresh Static value" {
    var sut = PerCpu.Static(u64, 8).init(0);
    sut.assertValid();
}

test "contract: assertValid succeeds after Static mutations" {
    var sut = PerCpu.Static(u64, 4).init(0);
    sut.assertValid();
    sut.getPtr(2).* = 42;
    sut.assertValid();
    _ = try sut.atPtr(0);
    sut.assertValid();
}

test "unit: Bounded.init(backing, 0) uses caller storage and fills every slot" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var sut = B.init(&storage, 0);
    try testing.expectEqual(@as(usize, 4), sut.capacity());
    try testing.expectEqual(@as(usize, 4), sut.len());
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try testing.expectEqual(@as(u64, 0), sut.get(i));
    }
}

test "unit: Bounded.initUndefined stores backing without writing" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var sut = B.initUndefined(&storage);
    try testing.expectEqual(@as(usize, 4), sut.capacity());
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        sut.getPtr(i).* = i * 10;
    }
    i = 0;
    while (i < 4) : (i += 1) {
        try testing.expectEqual(@as(u64, i * 10), sut.get(i));
    }
}

test "unit: Bounded.initFn initializes caller backing once per slot in index order" {
    const B = PerCpu.Bounded(u64);
    var storage: [6]B.Padded = undefined;
    var sut = B.initFn(&storage, makeDouble);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try testing.expectEqual(@as(u64, i) * 2, sut.get(i));
    }
}

test "unit: Bounded.initEach initializes caller backing via slot pointer" {
    const B = PerCpu.Bounded(u64);
    var storage: [6]B.Padded = undefined;
    var sut = B.initEach(&storage, fillWithIndex);
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try testing.expectEqual(@as(u64, i), sut.get(i));
    }
}

test "contract: writes through one Bounded are visible via another sharing the backing" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var writer = B.init(&storage, 0);
    var reader = B.initUndefined(&storage);

    writer.getPtr(2).* = 0xBEEF;
    try testing.expectEqual(@as(u64, 0xBEEF), reader.get(2));

    reader.getPtr(0).* = 0xF00D;
    try testing.expectEqual(@as(u64, 0xF00D), writer.get(0));
}

test "unit: Bounded.at rejects OOB and returns stored value otherwise" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var sut = B.init(&storage, 0);
    sut.getPtr(3).* = 0xFACE;
    try testing.expectEqual(@as(u64, 0xFACE), try sut.at(3));
    try testing.expectError(error.OutOfBounds, sut.at(4));
}

test "unit: Bounded.atPtr rejects OOB and returns a mutable pointer otherwise" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var sut = B.init(&storage, 0);
    const p = try sut.atPtr(1);
    p.* = 0xC0FFEE;
    try testing.expectEqual(@as(u64, 0xC0FFEE), sut.get(1));
    try testing.expectError(error.OutOfBounds, sut.atPtr(4));
}

test "unit: Bounded.slots yields exactly capacity() elements; slots[i].value == get(i)" {
    const B = PerCpu.Bounded(u64);
    var storage: [6]B.Padded = undefined;
    var sut = B.initFn(&storage, makeDouble);
    const view = sut.slots();
    try testing.expectEqual(@as(usize, 6), view.len);
    for (view, 0..) |slot, i| {
        try testing.expectEqual(sut.get(i), slot.value);
    }
}

test "contract: adjacent Bounded slots sit exactly one padded stride apart" {
    const B = PerCpu.Bounded(u64);
    var storage: [8]B.Padded = undefined;
    var sut = B.init(&storage, 0);
    const stride_expected = @sizeOf(B.Padded);
    var i: usize = 0;
    while (i + 1 < 8) : (i += 1) {
        const lo = @intFromPtr(sut.getPtr(i));
        const hi = @intFromPtr(sut.getPtr(i + 1));
        const stride = hi - lo;
        try testing.expectEqual(stride_expected, stride);
        try testing.expectEqual(@as(usize, 0), stride % cache_line);
    }
}

test "contract: assertValid succeeds on a fresh Bounded with aligned backing" {
    const B = PerCpu.Bounded(u64);
    var storage: [4]B.Padded = undefined;
    var sut = B.init(&storage, 0);
    sut.assertValid();
}

test "contract: hand-crafted mis-aligned Bounded backing violates the assertValid precondition" {
    // Zig's own `@ptrFromInt` runtime safety check traps before `assertValid`
    // can run when the address is under-aligned; disable it locally so that
    // the mis-aligned handle reaches `assertValid`, which is the check under
    // test. `assertValid` still fires a `std.debug.assert` trap, which would
    // kill the process — instead we verify the precondition the assert
    // examines is violated and stop short of invoking it. This documents the
    // trap without invoking it.
    @setRuntimeSafety(false);

    const B = PerCpu.Bounded(u64);
    const Padded = B.Padded;
    const stride = @sizeOf(Padded);

    var raw: [3 * stride]u8 align(cache_line) = undefined;
    const base = @intFromPtr(&raw[0]);
    const misaligned_addr = base + @sizeOf(u64);
    try testing.expect(misaligned_addr % @alignOf(Padded) != 0);

    const misaligned_ptr: [*]Padded = @ptrFromInt(misaligned_addr);
    const misaligned_slice: []Padded = misaligned_ptr[0..2];
    const sut = B.initUndefined(misaligned_slice);

    try testing.expect(@intFromPtr(sut.slotsConst().ptr) % @alignOf(Padded) != 0);
}

const NonAtomicCtx = struct {
    perc: *PerCpu.Static(u64, thread_count),
    id: usize,
    iterations: u64,

    const thread_count = 4;

    fn run(self: NonAtomicCtx) void {
        var i: u64 = 0;
        while (i < self.iterations) : (i += 1) {
            self.perc.getPtr(self.id).* += 1;
        }
    }
};

test "model: N threads incrementing distinct slots sum to N * iterations" {
    const thread_count = NonAtomicCtx.thread_count;
    const iterations: u64 = 5000;

    // Pointer-stride math must confirm every slot occupies a distinct cache
    // line; that structural guarantee is what removes false sharing here,
    // not wall-clock timing.
    var perc = PerCpu.Static(u64, thread_count).init(0);
    const stride = @intFromPtr(perc.getPtr(1)) - @intFromPtr(perc.getPtr(0));
    try testing.expect(stride % cache_line == 0);
    try testing.expect(stride >= cache_line);

    var threads: [thread_count]std.Thread = undefined;
    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, NonAtomicCtx.run, .{NonAtomicCtx{
            .perc = &perc,
            .id = idx,
            .iterations = iterations,
        }});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }

    var sum: u64 = 0;
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        sum += perc.get(idx);
    }
    try testing.expectEqual(@as(u64, thread_count) * iterations, sum);
}

const AtomicU64 = AtomicCell(u64);
const AtomicBool = AtomicCell(bool);

const AtomicProducerCtx = struct {
    perc: *PerCpu.Static(AtomicU64, thread_count),
    id: usize,
    iterations: u64,

    const thread_count = 4;

    fn run(self: AtomicProducerCtx) void {
        var i: u64 = 0;
        while (i < self.iterations) : (i += 1) {
            _ = self.perc.getPtr(self.id).fetchAddMonotonic(1);
        }
    }
};

fn initAtomicCounter(_: usize) AtomicU64 {
    return AtomicU64.init(0);
}

test "model: N producers on per-CPU AtomicCell slots, reader sees final total" {
    const thread_count = AtomicProducerCtx.thread_count;
    const iterations: u64 = 5000;

    var perc = PerCpu.Static(AtomicU64, thread_count).initFn(initAtomicCounter);
    var done = AtomicBool.init(false);

    var threads: [thread_count]std.Thread = undefined;
    var idx: usize = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx] = try std.Thread.spawn(.{}, AtomicProducerCtx.run, .{AtomicProducerCtx{
            .perc = &perc,
            .id = idx,
            .iterations = iterations,
        }});
    }
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        threads[idx].join();
    }
    done.storeRelease(true);

    // Reader observes completion via the release/acquire flag before summing.
    try testing.expect(done.loadAcquire());
    var sum: u64 = 0;
    idx = 0;
    while (idx < thread_count) : (idx += 1) {
        sum += perc.getPtr(idx).loadAcquire();
    }
    try testing.expectEqual(@as(u64, thread_count) * iterations, sum);
}

test "unit: module compiles regardless of host arch" {
    // Instantiate a few shapes at comptime to force codegen paths without
    // relying on any x86-specific behavior.
    comptime {
        _ = PerCpu.Static(u8, 1);
        _ = PerCpu.Static(u64, 8);
        _ = PerCpu.Static(usize, 16);
        _ = PerCpu.Bounded(u64);
    }
}
