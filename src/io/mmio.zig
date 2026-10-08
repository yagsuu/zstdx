//! MMIO register lanes and byte windows. See `docs/specs/io/mmio.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const endian = @import("../layout/endian.zig");

/// Ordering: Volatile accesses are compiler-ordered only. Use
/// `stdx.barrier.mmio` or `stdx.barrier.dma` to order them with other MMIO
/// accesses or DMA payloads.
pub const MMIO = struct {
    pub const default_align: usize = @alignOf(u64);

    /// Requirements: `T` must be `u8`, `u16`, `u32`, or `u64`; `layout.Le` or
    /// `layout.Be` over one of those types; or a `packed struct(uN)` backed by
    /// one of those types. Other types are compile errors.
    /// Representation: The returned `extern struct` has one `T` field, with
    /// the same size and alignment as `T`, so it composes in register overlays.
    pub fn Register(comptime T: type) type {
        comptime requireRegisterType(T);

        return extern struct {
            value: T align(@alignOf(T)),

            const Self = @This();

            pub const Native = T;

            pub const width_bytes: comptime_int = @sizeOf(T);

            /// Loads `T` through one volatile access at the lane's natural width and
            /// alignment when the target supports that width.
            /// Ordering: The access is compiler-ordered only. It emits no ISA fence
            /// and does not synchronize CPUs, DMA, or devices.
            pub fn load(self: *const volatile Self) T {
                return self.value;
            }

            /// Stores `value` through one volatile access at the lane's natural width
            /// and alignment.
            /// Ordering: The access is compiler-ordered only. It emits no ISA fence
            /// and does not synchronize CPUs, DMA, or devices.
            pub fn store(self: *volatile Self, value: T) void {
                self.value = value;
            }
        };
    }

    /// Returns a non-owning window over a caller-owned MMIO byte range.
    /// Requirements: `min_align_bytes` is a non-zero power of two; other values
    /// are compile errors. `register` and `registerUnchecked` require
    /// `@alignOf(T) <= min_align_bytes`; over-aligned lanes are compile errors.
    pub fn Window(comptime min_align_bytes: usize) type {
        comptime requireWindowAlign(min_align_bytes);

        return struct {
            base: [*]align(min_align_bytes) volatile u8,
            len: usize,

            const Self = @This();

            /// Minimum required alignment of the wrapped byte range.
            pub const min_align: usize = min_align_bytes;

            pub const Error = error{ OutOfBounds, Misaligned };

            /// Borrows `bytes` without allocation, copying, validation, or device access.
            /// The declared slice alignment enforces `min_align` at compile time.
            pub fn wrap(bytes: []align(min_align_bytes) volatile u8) Self {
                return .{ .base = bytes.ptr, .len = bytes.len };
            }

            /// Returns the borrowed byte range length.
            pub fn byteLen(self: Self) usize {
                return self.len;
            }

            /// Returns a `Register(T)` pointer at `offset`.
            /// Faults: `OutOfBounds` when the lane does not fit and `Misaligned` when
            /// its address is not aligned for `T`.
            /// Ownership: The pointer borrows the underlying MMIO mapping.
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

            /// Returns a pointer to `field_name` in a `Layout` overlay at the window base.
            /// Requirements: `Layout` contains `field_name`, whose type is accepted by
            /// `Register`.
            /// Effects: Delegates runtime bounds and alignment checks to `register`.
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

            /// Returns a `Register(T)` pointer at `offset`.
            /// Requirements: The caller establishes the accepted type, bounds, and address
            /// alignment. Checked builds assert those conditions.
            pub fn registerUnchecked(
                self: Self,
                comptime T: type,
                offset: usize,
            ) *volatile Register(T) {
                comptime requireRegisterType(T);
                comptime std.debug.assert(@alignOf(T) <= min_align_bytes);

                if (debug.checksEnabled()) {
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

    /// Use for MMIO regions guaranteed 8-byte alignment, such as page-aligned BARs.
    pub const Window64 = Window(@alignOf(u64));

    /// Use for MMIO regions with only 4-byte alignment, such as legacy PCI BARs.
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
