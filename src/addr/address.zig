//! Zero-cost strong address types parameterized by an opaque tag and an
//! unsigned integer width. Tags prevent accidental mixing across domains.
//! See `docs/specs/addr/address.md`.

const std = @import("std");

const layout = @import("layout");

pub const PhysTag = opaque {};
pub const VirtTag = opaque {};
pub const DMATag = opaque {};

pub const PhysAddr = Address(PhysTag, u64);
pub const VirtAddr = Address(VirtTag, usize);
pub const DMAAddr = Address(DMATag, u64);

pub fn Address(comptime DomainT: type, comptime IntT: type) type {
    comptime requireUnsignedInt(IntT);

    return enum(IntT) {
        _,

        const Self = @This();

        pub const Domain = DomainT;
        pub const Int = IntT;

        pub const OverflowError = error{Overflow};
        pub const AlignError = error{InvalidAlignment};
        pub const Error = OverflowError || AlignError;

        pub fn from(value: Int) Self {
            return @enumFromInt(value);
        }

        pub fn raw(self: Self) Int {
            return @intFromEnum(self);
        }

        pub fn zero() Self {
            return from(0);
        }

        pub fn max() Self {
            return from(std.math.maxInt(Int));
        }

        pub fn add(self: Self, amount: Int) OverflowError!Self {
            return from(std.math.add(Int, self.raw(), amount) catch return error.Overflow);
        }

        pub fn sub(self: Self, amount: Int) OverflowError!Self {
            return from(std.math.sub(Int, self.raw(), amount) catch return error.Overflow);
        }

        pub fn diff(self: Self, base: Self) OverflowError!Int {
            return std.math.sub(Int, self.raw(), base.raw()) catch return error.Overflow;
        }

        pub fn alignUp(self: Self, alignment: Int) Error!Self {
            return from(try layout.alignUp(Int, self.raw(), alignment));
        }

        pub fn alignDown(self: Self, alignment: Int) AlignError!Self {
            return from(try layout.alignDown(Int, self.raw(), alignment));
        }

        pub fn isAligned(self: Self, alignment: Int) bool {
            return layout.isAligned(Int, self.raw(), alignment);
        }
    };
}

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Address requires an unsigned integer type");
    }
}

pub const unit = struct {
    const testing = std.testing;
    const A = Address(opaque {}, u8);
    const B = Address(opaque {}, u8);

    test "unit: address domains remain distinct" {
        try testing.expect(A != B);
        try testing.expect(PhysAddr != DMAAddr);
        try testing.expect(PhysAddr != VirtAddr);
    }

    test "unit: address arithmetic detects overflow and underflow" {
        const a = A.from(10);

        try testing.expectEqual(@as(u8, 12), (try a.add(2)).raw());
        try testing.expectEqual(@as(u8, 8), (try a.sub(2)).raw());
        try testing.expectEqual(@as(u8, 2), try a.diff(A.from(8)));
        try testing.expectError(error.Overflow, A.max().add(1));
        try testing.expectError(error.Overflow, A.zero().sub(1));
        try testing.expectError(error.Overflow, A.zero().diff(A.from(1)));
    }

    test "unit: address alignment preserves rounding and errors" {
        const a = A.from(10);
        const up = try a.alignUp(8);
        const down = try a.alignDown(8);

        try testing.expectEqual(@as(u8, 16), up.raw());
        try testing.expectEqual(@as(u8, 8), down.raw());
        try testing.expect(!a.isAligned(8));
        try testing.expect(up.isAligned(8));
        try testing.expectError(error.InvalidAlignment, a.alignUp(3));
        try testing.expectError(error.InvalidAlignment, a.alignDown(0));
        try testing.expectError(error.Overflow, A.max().alignUp(8));
    }

    test "unit: address arithmetic and alignment work at comptime" {
        comptime {
            const a = A.from(10);
            const rounded = try a.alignUp(8);

            try testing.expectEqual(@as(u8, 16), rounded.raw());
            try testing.expectEqual(@as(u8, 6), try rounded.diff(a));
        }
    }
};
