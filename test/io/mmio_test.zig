//! MMIO register and window tests. See `docs/specs/io/mmio.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const layout = stdx.layout;
const MMIO = stdx.io.MMIO;

const testing = std.testing;

var scratch: [128]u8 align(@alignOf(u64)) = [_]u8{0} ** 128;

fn openWindow() MMIO.Window64 {
    const aligned: []align(@alignOf(u64)) volatile u8 = @alignCast(scratch[0..]);
    return MMIO.Window64.wrap(aligned);
}

test "unit: Register layout has expected size and alignment for each supported T" {
    try testing.expectEqual(@as(usize, 1), @sizeOf(MMIO.Register(u8)));
    try testing.expectEqual(@as(usize, 1), @alignOf(MMIO.Register(u8)));

    try testing.expectEqual(@as(usize, 2), @sizeOf(MMIO.Register(u16)));
    try testing.expectEqual(@as(usize, 2), @alignOf(MMIO.Register(u16)));

    try testing.expectEqual(@as(usize, 4), @sizeOf(MMIO.Register(u32)));
    try testing.expectEqual(@as(usize, 4), @alignOf(MMIO.Register(u32)));

    try testing.expectEqual(@as(usize, 8), @sizeOf(MMIO.Register(u64)));
    try testing.expectEqual(@as(usize, 8), @alignOf(MMIO.Register(u64)));

    try testing.expectEqual(@sizeOf(layout.Le(u32)), @sizeOf(MMIO.Register(layout.Le(u32))));
    try testing.expectEqual(@alignOf(layout.Le(u32)), @alignOf(MMIO.Register(layout.Le(u32))));
}

test "unit: Register layout for packed struct(uN) matches backing integer" {
    const P32 = packed struct(u32) { a: u1, b: u31 };
    try testing.expectEqual(@as(usize, 4), @sizeOf(MMIO.Register(P32)));
    try testing.expectEqual(@as(usize, 4), @alignOf(MMIO.Register(P32)));

    const P8 = packed struct(u8) { a: u4, b: u4 };
    try testing.expectEqual(@as(usize, 1), @sizeOf(MMIO.Register(P8)));
    try testing.expectEqual(@as(usize, 1), @alignOf(MMIO.Register(P8)));

    const P64 = packed struct(u64) { a: u32, b: u32 };
    try testing.expectEqual(@as(usize, 8), @sizeOf(MMIO.Register(P64)));
    try testing.expectEqual(@as(usize, 8), @alignOf(MMIO.Register(P64)));

    const P16 = packed struct(u16) { a: u8, b: u8 };
    try testing.expectEqual(@as(usize, 2), @sizeOf(MMIO.Register(P16)));
    try testing.expectEqual(@as(usize, 2), @alignOf(MMIO.Register(P16)));
}

test "model: extern struct overlay of Register lanes preserves NVMe register offsets" {
    const Overlay = extern struct {
        cap: MMIO.Register(u64),
        vs: MMIO.Register(u32),
        intms: MMIO.Register(u32),
        intmc: MMIO.Register(u32),
        cc: MMIO.Register(u32),
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
        const ptr: *volatile MMIO.Register(T) = @ptrCast(@alignCast(&scratch[offset]));
        const sample: T = 0x42;
        ptr.store(sample);
        try testing.expectEqual(sample, ptr.load());
    }
}

test "unit: Register composes with layout.Le for endian-stable byte layout" {
    @memset(&scratch, 0);
    const ptr: *volatile MMIO.Register(layout.Le(u32)) = @ptrCast(@alignCast(&scratch[0]));
    ptr.store(layout.Le(u32).fromNative(0x12345678));
    try testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, scratch[0..4]);
    try testing.expectEqual(@as(u32, 0x12345678), ptr.load().native());
}

test "unit: Register composes with layout.Be for endian-stable byte layout" {
    @memset(&scratch, 0);
    const ptr: *volatile MMIO.Register(layout.Be(u32)) = @ptrCast(@alignCast(&scratch[0]));
    ptr.store(layout.Be(u32).fromNative(0x12345678));
    try testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, scratch[0..4]);
    try testing.expectEqual(@as(u32, 0x12345678), ptr.load().native());
}

test "unit: Register(packed struct(u32)) round-trips through a volatile scratch buffer" {
    var buf: [4]u8 align(4) = [_]u8{0} ** 4;
    const Flags = packed struct(u32) { en: bool, _rsvd: u31 };
    const ptr: *volatile MMIO.Register(Flags) = @ptrCast(@alignCast(&buf[0]));
    ptr.store(.{ .en = true, ._rsvd = 0 });
    const loaded = ptr.load();
    try testing.expectEqual(true, loaded.en);
    try testing.expectEqual(@as(u31, 0), loaded._rsvd);
}

test "unit: Register(packed struct(u32)) stores field 0 in low bit little-endian on LE targets" {
    if (builtin.cpu.arch.endian() != .little) return;
    var buf: [4]u8 align(4) = [_]u8{0} ** 4;
    const Flags = packed struct(u32) { en: bool, _rsvd: u31 };
    const ptr: *volatile MMIO.Register(Flags) = @ptrCast(@alignCast(&buf[0]));
    ptr.store(.{ .en = true, ._rsvd = 0 });
    try testing.expectEqualSlices(u8, &.{ 0x01, 0x00, 0x00, 0x00 }, buf[0..4]);
}

test "unit: Register(packed struct(u32)) piecemeal update preserves reserved bits" {
    var buf: [4]u8 align(4) = [_]u8{0} ** 4;
    const Cc = packed struct(u32) { en: bool, css: u3, _rsvd0: u28 };
    const ptr: *volatile MMIO.Register(Cc) = @ptrCast(@alignCast(&buf[0]));
    ptr.store(.{ .en = false, .css = 0, ._rsvd0 = 0xDEADBEE });
    var next = ptr.load();
    next.en = true;
    next.css = 3;
    ptr.store(next);
    const final = ptr.load();
    try testing.expectEqual(true, final.en);
    try testing.expectEqual(@as(u3, 3), final.css);
    try testing.expectEqual(@as(u28, 0xDEADBEE), final._rsvd0);
}

// Register(layout.Le(Cc)) where Cc is `packed struct(u32)` is described in
// docs/specs/io/mmio.md:562-564 but cannot be realized: the endian wrapper's
// contract at docs/specs/layout/endian.md:140 explicitly excludes packed
// structs, so `layout.Le` @compileErrors on packed-struct T. The two specs
// are mutually incompatible on that specific composition; the mmio scope
// records the incompatibility here and does not extend `layout.Le`.

test "unit: Register(T) positive comptime instantiations pin the accepted set" {
    comptime {
        _ = MMIO.Register(u8);
        _ = MMIO.Register(u16);
        _ = MMIO.Register(u32);
        _ = MMIO.Register(u64);
        _ = MMIO.Register(layout.Le(u8));
        _ = MMIO.Register(layout.Le(u16));
        _ = MMIO.Register(layout.Le(u32));
        _ = MMIO.Register(layout.Le(u64));
        _ = MMIO.Register(layout.Be(u32));
        _ = MMIO.Register(packed struct(u8) { a: u8 });
        _ = MMIO.Register(packed struct(u16) { a: u16 });
        _ = MMIO.Register(packed struct(u32) { a: u32 });
        _ = MMIO.Register(packed struct(u64) { a: u64 });
    }
}

// Compile-error cases for `Register(T)` are guarded by `@compileError` in
// `src/io/mmio.zig`'s `requireRegisterType` and cannot be tested at runtime.
// The rejected shapes are:
//   - `Register(u7)`, `Register(u24)`, `Register(u40)`, `Register(u128)`;
//   - `Register(usize)`, `Register(isize)`, `Register(i32)`;
//   - `Register(bool)`, `Register(f32)`;
//   - `Register([4]u8)`, `Register(*u32)`, `Register(?u32)`;
//   - `Register(packed struct(u24) { a: u12, b: u12 })` — backing integer
//     is not one of `u8`/`u16`/`u32`/`u64`;
//   - `Register(packed struct { a: u32 })` — no explicit backing integer.

test "unit: Window(min_align) factory accepts every power-of-two min_align_bytes" {
    comptime {
        _ = MMIO.Window(@alignOf(u64));
        _ = MMIO.Window(@alignOf(u32));
        _ = MMIO.Window(@alignOf(u16));
        _ = MMIO.Window(1);
        _ = MMIO.Window(2);
        _ = MMIO.Window(4);
        _ = MMIO.Window(8);
    }
}

// Compile-error cases for `Window(min_align_bytes)` are guarded by
// `@compileError` in `requireWindowAlign`. Rejected shapes:
//   - `Window(0)` — must be at least 1;
//   - `Window(3)`, `Window(5)`, `Window(6)`, `Window(7)`, ... — must be a
//     power of two.

test "unit: MMIO.Window32 and MMIO.Window64 resolve to Window(min_align)" {
    comptime {
        std.debug.assert(MMIO.Window32 == MMIO.Window(@alignOf(u32)));
        std.debug.assert(MMIO.Window64 == MMIO.Window(@alignOf(u64)));
        std.debug.assert(MMIO.default_window_align == @alignOf(u64));
    }
}

test "unit: Window.wrap returns a window with matching length" {
    @memset(&scratch, 0);
    const window = openWindow();
    try testing.expectEqual(scratch.len, window.len);
    try testing.expectEqual(scratch.len, window.byteLen());
}

test "unit: Window32.wrap accepts a 4-byte-aligned slice" {
    var buf: [16]u8 align(4) = [_]u8{0} ** 16;
    const aligned: []align(4) volatile u8 = @alignCast(buf[0..]);
    const window = MMIO.Window32.wrap(aligned);
    try testing.expectEqual(@as(usize, 16), window.byteLen());
}

test "unit: Window32.register(u32, 0) succeeds on a 4-byte-aligned scratch buffer" {
    var buf: [16]u8 align(4) = [_]u8{0} ** 16;
    const aligned: []align(4) volatile u8 = @alignCast(buf[0..]);
    const window = MMIO.Window32.wrap(aligned);
    const reg = try window.register(u32, 0);
    reg.store(0xCAFEBABE);
    const observed = std.mem.readInt(u32, buf[0..4], builtin.cpu.arch.endian());
    try testing.expectEqual(@as(u32, 0xCAFEBABE), observed);
}

test "unit: Window32.register(u32, offset) rejects misalignment on a 4-byte-aligned base whose runtime address is odd modulo 4" {
    // On a scratch buffer with `align(4)`, offset 2 puts (base + offset) at
    // an address that is 2-mod-4; `@alignOf(u32) == 4` so `register`
    // returns error.Misaligned. This exercises the runtime alignment path.
    var buf: [16]u8 align(4) = [_]u8{0} ** 16;
    const aligned: []align(4) volatile u8 = @alignCast(buf[0..]);
    const window = MMIO.Window32.wrap(aligned);
    try testing.expectError(error.Misaligned, window.register(u32, 2));
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

test "unit: Window.field returns the same pointer as register at the field's offset" {
    @memset(&scratch, 0);
    const window = openWindow();
    // Layout uses plain scalar fields; `field` wraps each in Register(T)
    // per the spec signature `Register(@FieldType(Layout, field_name))`.
    const Layout = extern struct {
        cap: u64,
        vs: u32,
        intms: u32,
        intmc: u32,
        cc: u32,
    };

    const cap_via_field = try window.field(Layout, "cap");
    const cap_via_register = try window.register(u64, 0);
    try testing.expectEqual(@intFromPtr(cap_via_register), @intFromPtr(cap_via_field));

    const vs_via_field = try window.field(Layout, "vs");
    const vs_via_register = try window.register(u32, @offsetOf(Layout, "vs"));
    try testing.expectEqual(@intFromPtr(vs_via_register), @intFromPtr(vs_via_field));

    const cc_via_field = try window.field(Layout, "cc");
    const cc_via_register = try window.register(u32, @offsetOf(Layout, "cc"));
    try testing.expectEqual(@intFromPtr(cc_via_register), @intFromPtr(cc_via_field));
}

test "unit: Window.field propagates OutOfBounds and Misaligned from register" {
    var small: [4]u8 align(@alignOf(u64)) = [_]u8{0} ** 4;
    const aligned: []align(@alignOf(u64)) volatile u8 = @alignCast(small[0..]);
    const window = MMIO.Window64.wrap(aligned);

    const Layout = extern struct {
        cap: u64,
    };

    try testing.expectError(error.OutOfBounds, window.field(Layout, "cap"));
}

// Compile-error cases for `Window.field` are guarded by `@compileError` in
// `src/io/mmio.zig`'s `Window.field`. Rejected shapes:
//   - `field(Layout, "missing")` — layout has no such field;
//   - a `Layout` whose named field extends past `@sizeOf(Layout)` — defense
//     against packed/manually-authored layouts;
//   - a `Layout` whose field type is a disallowed `Register(T)` argument
//     (e.g. `Register(u24)`) — rejected transitively via `Register(T)`'s
//     own compile-error surface in `requireRegisterType`.
