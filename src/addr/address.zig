//! Zero-cost strong address types parameterized by an opaque tag and an
//! unsigned integer width. Tags prevent accidental mixing across domains.
//! See docs/specs/addr/address.md.

const std = @import("std");

const bits = @import("../bits.zig");

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Address requires an unsigned integer type");
    }
}

/// Strong address type identified by `Tag` and backed by unsigned integer
/// `Int`. Two `Address(Tag, Int)` instantiations with different tags are
/// distinct Zig types even when `Int` matches.
pub fn Address(comptime Tag: type, comptime Int: type) type {
    comptime requireUnsignedInt(Int);
    return enum(Int) {
        _,

        const Self = @This();

        /// Tag type used to distinguish address domains.
        pub const TagType = Tag;

        /// Underlying unsigned integer representation.
        pub const Raw = Int;

        /// `Overflow`: arithmetic on `add`, `sub`, `diff`, or `alignUp` would
        /// exceed the `Int` range.
        pub const OverflowError = error{Overflow};

        /// `InvalidAlignment`: `alignment` is zero or not a power of two.
        pub const AlignError = error{InvalidAlignment};

        /// Union of `OverflowError` and `AlignError`. Use this when a method's
        /// signature may produce either variant.
        pub const Error = OverflowError || AlignError;

        pub fn fromInt(value: Int) Self {
            return @enumFromInt(value);
        }

        pub fn raw(self: Self) Int {
            return @intFromEnum(self);
        }

        pub fn zero() Self {
            return fromInt(0);
        }

        pub fn max() Self {
            return fromInt(std.math.maxInt(Int));
        }

        pub fn add(self: Self, amount: Int) OverflowError!Self {
            return fromInt(std.math.add(Int, self.raw(), amount) catch return error.Overflow);
        }

        pub fn sub(self: Self, amount: Int) OverflowError!Self {
            return fromInt(std.math.sub(Int, self.raw(), amount) catch return error.Overflow);
        }

        /// `self - base` as a raw `Int`. Returns `error.Overflow` when
        /// `self < base`.
        pub fn diff(self: Self, base: Self) OverflowError!Int {
            return std.math.sub(Int, self.raw(), base.raw()) catch return error.Overflow;
        }

        fn validateAlignment(alignment: Int) AlignError!void {
            if (alignment == 0 or !bits.isPowerOfTwo(Int, alignment)) return error.InvalidAlignment;
        }

        /// Round the address up to a multiple of `alignment`.
        pub fn alignUp(self: Self, alignment: Int) Error!Self {
            try validateAlignment(alignment);

            const mask = alignment - 1;
            const added = std.math.add(Int, self.raw(), mask) catch return error.Overflow;
            return fromInt(added & ~mask);
        }

        /// Round the address down to a multiple of `alignment`. Never overflows.
        pub fn alignDown(self: Self, alignment: Int) AlignError!Self {
            try validateAlignment(alignment);
            return fromInt(self.raw() & ~(alignment - 1));
        }

        pub fn isAligned(self: Self, alignment: Int) bool {
            std.debug.assert(alignment != 0);
            std.debug.assert(bits.isPowerOfTwo(Int, alignment));
            return (self.raw() & (alignment - 1)) == 0;
        }
    };
}

/// Tag identifying physical address domains.
pub const PhysTag = opaque {};

/// Tag identifying virtual address domains.
pub const VirtTag = opaque {};

/// Default physical address: `Address(PhysTag, u64)`.
pub const PhysAddr = Address(PhysTag, u64);

/// Default virtual address: `Address(VirtTag, usize)`.
pub const VirtAddr = Address(VirtTag, usize);
