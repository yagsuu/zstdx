//! MMIO register lanes and byte windows. See docs/specs/io/mmio.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const endian = @import("../layout/endian.zig");

fn isAllowedNativeInt(comptime T: type) bool {
    return T == u8 or T == u16 or T == u32 or T == u64;
}

fn isAllowedEndianInt(comptime T: type) bool {
    if (!@hasDecl(T, "Native")) return false;
    const Native = T.Native;
    if (!isAllowedNativeInt(Native)) return false;
    return T == endian.Le(Native) or T == endian.Be(Native);
}

fn requireRegisterType(comptime T: type) void {
    if (isAllowedNativeInt(T)) return;
    if (isAllowedEndianInt(T)) return;
    @compileError("Mmio.Register requires u8, u16, u32, u64, or layout.Le/Be over those widths");
}

/// MMIO family namespace. Access provides only compiler ordering; hardware
/// ordering against DMA payloads or other MMIO accesses is the caller's job
/// via `stdx.barrier.mmio` and `stdx.barrier.dma`.
pub const Mmio = struct {
    /// Typed volatile storage lane for a memory-mapped device register. `T`
    /// must be `u8`, `u16`, `u32`, `u64`, or `layout.Le`/`Be` over one of
    /// those widths; every other `T` is a compile error. The returned type
    /// is an `extern struct` with a single field, so it composes losslessly
    /// inside overlay `extern struct`s that model fixed device register
    /// blocks. `@sizeOf == @sizeOf(T)` and `@alignOf == @alignOf(T)`.
    pub fn Register(comptime T: type) type {
        comptime requireRegisterType(T);
        return extern struct {
            value: T align(@alignOf(T)),

            const Self = @This();

            /// The native `T` the register lane carries.
            pub const Native = T;

            /// Storage width in bytes.
            pub const width_bytes: comptime_int = @sizeOf(T);

            /// Single volatile load at the natural width and alignment of
            /// `T`. Emits exactly one memory access at the ISA level on
            /// targets whose native access widths match `@sizeOf(T)`.
            /// Compiler-ordered against other volatile accesses; no ISA fence
            /// and no cross-CPU or cross-DMA synchronization.
            pub fn load(self: *const volatile Self) T {
                return self.value;
            }

            /// Single volatile store at the natural width and alignment of
            /// `T`. Same ordering semantics as `load`.
            pub fn store(self: *volatile Self, value: T) void {
                self.value = value;
            }
        };
    }

    /// Byte-window value type over a caller-owned MMIO byte range. Owns
    /// nothing; borrows the caller's mapping for its lifetime.
    pub const Window = struct {
        base: [*]align(min_align) volatile u8,
        len: usize,

        /// Minimum required alignment of the wrapped byte range;
        /// `@alignOf(u64)`.
        pub const min_align: usize = @alignOf(u64);

        /// `OutOfBounds`: `offset + @sizeOf(T)` exceeds `self.len` or would
        /// overflow `usize`.
        /// `Misaligned`: `(base + offset)` is not aligned to `@alignOf(T)`.
        pub const Error = error{ OutOfBounds, Misaligned };

        /// Wrap a caller-owned MMIO byte range. The `align` annotation on
        /// the parameter makes lesser-aligned inputs a compile error rather
        /// than a runtime one.
        pub fn wrap(bytes: []align(min_align) volatile u8) Window {
            return .{ .base = bytes.ptr, .len = bytes.len };
        }

        /// Typed pointer into the window at `offset`. Returns
        /// `error.OutOfBounds` when the register would extend past the
        /// window (including on `usize`-overflowing `offset`), and
        /// `error.Misaligned` when `(base + offset)` is not aligned to
        /// `@alignOf(T)`. The returned pointer aliases `self.base + offset`
        /// and is valid for the lifetime of the underlying MMIO mapping.
        pub fn register(
            self: Window,
            comptime T: type,
            offset: usize,
        ) Error!*volatile Register(T) {
            comptime requireRegisterType(T);
            const width = @sizeOf(T);
            const end = std.math.add(usize, offset, width) catch return error.OutOfBounds;
            if (end > self.len) return error.OutOfBounds;
            const addr = @intFromPtr(self.base) + offset;
            if (addr % @alignOf(T) != 0) return error.Misaligned;
            return @ptrFromInt(addr);
        }

        /// Typed pointer into the window at `offset` without runtime checks.
        /// The caller must have proven bounds and alignment through another
        /// mechanism such as a comptime-known offset or prior validated
        /// computation. Under `core.debug.checksEnabled(.build_mode)` the
        /// same conditions `register` returns as errors are asserted; in
        /// release builds this is one pointer-arithmetic step.
        pub fn registerUnchecked(
            self: Window,
            comptime T: type,
            offset: usize,
        ) *volatile Register(T) {
            comptime requireRegisterType(T);
            if (debug.checksEnabled(.build_mode)) {
                const width = @sizeOf(T);
                const end = std.math.add(usize, offset, width) catch unreachable;
                std.debug.assert(end <= self.len);
                std.debug.assert((@intFromPtr(self.base) + offset) % @alignOf(T) == 0);
            }
            const addr = @intFromPtr(self.base) + offset;
            return @ptrFromInt(addr);
        }
    };
};
