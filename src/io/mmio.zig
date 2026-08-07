//! MMIO register lanes and byte windows. See `docs/specs/io/mmio.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const endian = @import("../layout/endian.zig");

/// `MMIO` provides register lanes and byte windows.
/// Ordering: Its accesses are compiler-ordered. The caller must order them
/// against DMA payloads or other MMIO accesses with `stdx.barrier.mmio` and
/// `stdx.barrier.dma`.
pub const MMIO = struct {
    /// This is the default `min_align_bytes` for the `Window64` alias. It
    /// matches the alignment guaranteed by page-aligned or canonical NVMe
    /// register blocks.
    pub const default_align: usize = @alignOf(u64);

    /// Typed volatile storage lane for a memory-mapped device register. `T`
    /// must be `u8`, `u16`, `u32`, `u64`; `layout.Le`/`Be` over one of those
    /// widths; or a `packed struct(uN)` whose backing integer is one of
    /// those widths. Every other `T` is a compile error. The returned type
    /// is an `extern struct` with a single field, so it composes losslessly
    /// inside overlay `extern struct`s that model fixed device register
    /// blocks. `@sizeOf == @sizeOf(T)` and `@alignOf == @alignOf(T)`.
    pub fn Register(comptime T: type) type {
        comptime requireRegisterType(T);

        return extern struct {
            value: T align(@alignOf(T)),

            const Self = @This();

            pub const Native = T;

            pub const width_bytes: comptime_int = @sizeOf(T);

            /// Loads `T` with one volatile access at the lane's natural width
            /// and alignment on targets whose native access widths match
            /// `@sizeOf(T)`.
            /// Ordering: Compiler-ordered against other volatile accesses. It
            /// emits no ISA fence or cross-CPU or cross-DMA synchronization.
            pub fn load(self: *const volatile Self) T {
                return self.value;
            }

            /// Stores `T` with one volatile access at the lane's natural width
            /// and alignment.
            /// Ordering: Compiler-ordered against other volatile accesses. It
            /// emits no ISA fence or cross-CPU or cross-DMA synchronization.
            pub fn store(self: *volatile Self, value: T) void {
                self.value = value;
            }
        };
    }

    /// Byte-window value factory over a caller-owned MMIO byte range.
    /// `min_align_bytes` is the guaranteed alignment of the wrapped byte
    /// range; it must be a power of two and at least 1. Values other than
    /// powers of two are compile errors. The returned type owns nothing; it
    /// borrows the caller's mapping for its lifetime.
    ///
    /// `Register(T)` used through the returned window's `register` /
    /// `registerUnchecked` requires `@alignOf(T) <= min_align_bytes`.
    /// Attempts to instantiate an over-aligned lane are rejected at compile
    /// time.
    pub fn Window(comptime min_align_bytes: usize) type {
        comptime requireWindowAlign(min_align_bytes);

        return struct {
            base: [*]align(min_align_bytes) volatile u8,
            len: usize,

            const Self = @This();

            /// Minimum required alignment of the wrapped byte range.
            pub const min_align: usize = min_align_bytes;

            /// `OutOfBounds`: `offset + @sizeOf(T)` exceeds `self.len` or
            /// would overflow `usize`.
            /// `Misaligned`: `(base + offset)` is not aligned to `@alignOf(T)`.
            pub const Error = error{ OutOfBounds, Misaligned };

            /// Wraps a caller-owned MMIO byte range. The `align` annotation on
            /// the parameter makes lesser-aligned inputs a compile error
            /// rather than a runtime one.
            pub fn wrap(bytes: []align(min_align_bytes) volatile u8) Self {
                return .{ .base = bytes.ptr, .len = bytes.len };
            }

            pub fn byteLen(self: Self) usize {
                return self.len;
            }

            /// Typed pointer into the window at `offset`. Returns
            /// `error.OutOfBounds` when the register would extend past the
            /// window (including on `usize`-overflowing `offset`), and
            /// `error.Misaligned` when `(base + offset)` is not aligned to
            /// `@alignOf(T)`. The returned pointer aliases `self.base +
            /// offset` and is valid for the lifetime of the underlying MMIO
            /// mapping.
            pub fn register(
                self: Self,
                comptime T: type,
                offset: usize,
            ) Error!*volatile Register(T) {
                comptime requireRegisterType(T);
                comptime std.debug.assert(@alignOf(T) <= min_align_bytes);
                const width = @sizeOf(T);
                if (width > self.len) return error.OutOfBounds;
                if (offset > self.len - width) return error.OutOfBounds;
                const addr = @intFromPtr(self.base) + offset;
                if (addr % @alignOf(T) != 0) return error.Misaligned;
                return @ptrFromInt(addr);
            }

            /// Typed pointer to `Layout`'s named field, treating `Layout` as
            /// an overlay anchored at the start of the window. `Layout` and
            /// `field_name` are validated at compile time; runtime bounds
            /// and alignment checks are delegated to `register`.
            pub fn field(
                self: Self,
                comptime Layout: type,
                comptime field_name: []const u8,
            ) Error!*volatile Register(@FieldType(Layout, field_name)) {
                comptime {
                    if (!@hasField(Layout, field_name)) {
                        @compileError(
                            "MMIO.Window.field: layout '" ++ @typeName(Layout) ++
                                "' has no field '" ++ field_name ++ "'",
                        );
                    }
                    const FieldT = @FieldType(Layout, field_name);
                    const field_end = @offsetOf(Layout, field_name) + @sizeOf(FieldT);
                    if (field_end > @sizeOf(Layout)) {
                        @compileError(
                            "MMIO.Window.field: field '" ++ field_name ++
                                "' extends past @sizeOf(" ++ @typeName(Layout) ++ ")",
                        );
                    }
                }

                const FieldT = @FieldType(Layout, field_name);
                return self.register(FieldT, @offsetOf(Layout, field_name));
            }

            /// Typed pointer into the window at `offset` without runtime
            /// checks. The caller must have proven bounds and alignment
            /// through another mechanism such as a comptime-known offset or
            /// prior validated computation. Under
            /// `core.debug.checksEnabled(.build_mode)` the same conditions
            /// `register` returns as errors are asserted; in release builds
            /// this is one pointer-arithmetic step.
            pub fn registerUnchecked(
                self: Self,
                comptime T: type,
                offset: usize,
            ) *volatile Register(T) {
                comptime requireRegisterType(T);
                comptime std.debug.assert(@alignOf(T) <= min_align_bytes);

                if (debug.checksEnabled(.build_mode)) {
                    const width = @sizeOf(T);
                    std.debug.assert(width <= self.len);
                    std.debug.assert(offset <= self.len - width);
                    std.debug.assert((@intFromPtr(self.base) + offset) % @alignOf(T) == 0);
                }

                const addr = @intFromPtr(self.base) + offset;
                return @ptrFromInt(addr);
            }
        };
    }

    /// Pre-instantiated window alias for MMIO regions guaranteed
    /// 8-byte-aligned (page-aligned BARs, canonical NVMe register blocks).
    pub const Window64 = Window(@alignOf(u64));

    /// Pre-instantiated window alias for MMIO regions advertised with only
    /// 4-byte alignment (some legacy PCI BARs).
    pub const Window32 = Window(@alignOf(u32));
};

fn isAllowedNativeInt(comptime T: type) bool {
    return switch (T) {
        u8, u16, u32, u64 => true,
        else => false,
    };
}

fn isAllowedEndianInt(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    if (!@hasDecl(T, "Native")) return false;

    const Native = T.Native;
    if (!isAllowedNativeInt(Native)) return false;
    return T == endian.Le(Native) or T == endian.Be(Native);
}

fn isAllowedPackedStruct(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    if (info.@"struct".layout != .@"packed") return false;

    const backing = info.@"struct".backing_integer orelse return false;
    return switch (backing) {
        u8, u16, u32, u64 => true,
        else => false,
    };
}

fn requireRegisterType(comptime T: type) void {
    if (isAllowedNativeInt(T)) return;
    if (isAllowedEndianInt(T)) return;
    if (isAllowedPackedStruct(T)) return;

    @compileError(
        "MMIO.Register requires u8/u16/u32/u64, layout.Le/Be over those widths, " ++
            "or packed struct(uN) with N in {8,16,32,64}",
    );
}

fn requireWindowAlign(comptime bytes: usize) void {
    if (bytes == 0) {
        @compileError("MMIO.Window min_align_bytes must be at least 1");
    }
    if (!std.math.isPowerOfTwo(bytes)) {
        @compileError("MMIO.Window min_align_bytes must be a power of two");
    }
}
