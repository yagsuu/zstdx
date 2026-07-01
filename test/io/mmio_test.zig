//! MMIO register and window tests. Spec: docs/specs/io/mmio.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const layout = stdx.layout;
const Mmio = stdx.io.Mmio;

const testing = std.testing;

var scratch: [128]u8 align(@alignOf(u64)) = [_]u8{0} ** 128;

fn openWindow() Mmio.Window {
    const aligned: []align(@alignOf(u64)) volatile u8 = @alignCast(scratch[0..]);
    return Mmio.Window.wrap(aligned);
}

test "unit: Register layout has expected size and alignment for each supported T" {
    try testing.expectEqual(@as(usize, 1), @sizeOf(Mmio.Register(u8)));
    try testing.expectEqual(@as(usize, 1), @alignOf(Mmio.Register(u8)));

    try testing.expectEqual(@as(usize, 2), @sizeOf(Mmio.Register(u16)));
    try testing.expectEqual(@as(usize, 2), @alignOf(Mmio.Register(u16)));

    try testing.expectEqual(@as(usize, 4), @sizeOf(Mmio.Register(u32)));
    try testing.expectEqual(@as(usize, 4), @alignOf(Mmio.Register(u32)));

    try testing.expectEqual(@as(usize, 8), @sizeOf(Mmio.Register(u64)));
    try testing.expectEqual(@as(usize, 8), @alignOf(Mmio.Register(u64)));

    try testing.expectEqual(@sizeOf(layout.Le(u32)), @sizeOf(Mmio.Register(layout.Le(u32))));
    try testing.expectEqual(@alignOf(layout.Le(u32)), @alignOf(Mmio.Register(layout.Le(u32))));
}

test "model: extern struct overlay of Register lanes preserves NVMe register offsets" {
    const Overlay = extern struct {
        cap: Mmio.Register(u64),
        vs: Mmio.Register(u32),
        intms: Mmio.Register(u32),
        intmc: Mmio.Register(u32),
        cc: Mmio.Register(u32),
    };

    try testing.expectEqual(@as(usize, 0), @offsetOf(Overlay, "cap"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(Overlay, "vs"));
    try testing.expectEqual(@as(usize, 12), @offsetOf(Overlay, "intms"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(Overlay, "intmc"));
    try testing.expectEqual(@as(usize, 20), @offsetOf(Overlay, "cc"));
}

test "unit: Register.load and store round-trip through a volatile scratch buffer" {
    @memset(&scratch, 0);
    inline for (.{ u8, u16, u32, u64 }, .{ 0, 8, 16, 24 }) |T, offset| {
        const ptr: *volatile Mmio.Register(T) = @ptrCast(@alignCast(&scratch[offset]));
        const sample: T = 0x42;
        ptr.store(sample);
        try testing.expectEqual(sample, ptr.load());
    }
}

test "unit: Register composes with layout.Le for endian-stable byte layout" {
    @memset(&scratch, 0);
    const ptr: *volatile Mmio.Register(layout.Le(u32)) = @ptrCast(@alignCast(&scratch[0]));
    ptr.store(layout.Le(u32).fromNative(0x12345678));
    try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, scratch[0..4]);
}

test "unit: Register composes with layout.Be for endian-stable byte layout" {
    @memset(&scratch, 0);
    const ptr: *volatile Mmio.Register(layout.Be(u32)) = @ptrCast(@alignCast(&scratch[0]));
    ptr.store(layout.Be(u32).fromNative(0x12345678));
    try testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, scratch[0..4]);
}

test "unit: Window.wrap returns a window with matching length" {
    @memset(&scratch, 0);
    const window = openWindow();
    try testing.expectEqual(scratch.len, window.len);
}

test "unit: Window.register succeeds at the first, middle, and last aligned offset" {
    @memset(&scratch, 0);
    const window = openWindow();
    _ = try window.register(u32, 0);
    _ = try window.register(u32, 60);
    _ = try window.register(u32, scratch.len - 4);
}

test "unit: Window.register returns OutOfBounds when width extends past len" {
    @memset(&scratch, 0);
    const window = openWindow();
    try testing.expectError(error.OutOfBounds, window.register(u32, scratch.len - 3));
}

test "unit: Window.register returns Misaligned when offset breaks @alignOf(T)" {
    @memset(&scratch, 0);
    const window = openWindow();
    try testing.expectError(error.Misaligned, window.register(u32, 3));
}

test "unit: Window.register returns OutOfBounds instead of overflowing usize" {
    @memset(&scratch, 0);
    const window = openWindow();
    try testing.expectError(error.OutOfBounds, window.register(u32, std.math.maxInt(usize)));
}

test "unit: Window.registerUnchecked returns aliased pointer for a validated offset" {
    @memset(&scratch, 0);
    const window = openWindow();
    const reg = window.registerUnchecked(u32, 0);
    reg.store(0xDEADBEEF);
    const observed = std.mem.readInt(u32, scratch[0..4], builtin.cpu.arch.endian());
    try testing.expectEqual(@as(u32, 0xDEADBEEF), observed);
}
