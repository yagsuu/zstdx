//! strongly typed unsigned addresses

const std = @import("std");

const layout = @import("layout");
const ranges = @import("ranges");

pub const PhysTag = opaque {};
pub const VirtTag = opaque {};
pub const DmaTag = opaque {};

pub const PhysAddr = Address(PhysTag, u64);
pub const VirtAddr = Address(VirtTag, usize);
pub const DmaAddr = Address(DmaTag, u64);

pub fn Address(comptime DomainT: type, comptime IntT: type) type {
    comptime requireUnsignedInt(IntT);

    return enum(IntT) {
        _,

        const __StdxAddress = void;

        const Self = @This();
        const Offset = @Int(.signed, @bitSizeOf(IntT));

        pub const Domain = DomainT;
        pub const Int = IntT;
        pub const Range = ranges.Range(Self);

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

        pub fn offset(self: Self, bytes: Offset) OverflowError!Self {
            const amount: Int = @abs(bytes);
            if (bytes < 0) {
                return self.sub(amount);
            }
            return self.add(amount);
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

        fn cast(value: anytype) Self {
            const Source = @TypeOf(value);

            if (comptime isAddress(Source)) {
                return Self.from(@intCast(value.raw()));
            }

            if (comptime isThinPointer(Source)) {
                return Self.from(@intCast(@intFromPtr(value)));
            }

            @compileError("addr.cast requires a pointer/address or address/address conversion");
        }
    };
}

pub fn cast(comptime T: type, value: anytype) T {
    const Source = @TypeOf(value);

    if (comptime isAddress(T)) {
        return T.cast(value);
    } else if (comptime isThinPointer(T) and isAddress(Source)) {
        return @ptrFromInt(@as(usize, @intCast(value.raw())));
    }

    @compileError("addr.cast requires a pointer/address or address/address conversion");
}

pub fn castAligned(comptime Pointer: type, address: anytype) error{Misaligned}!Pointer {
    if (comptime !isThinPointer(Pointer) or !isAddress(@TypeOf(address))) {
        @compileError("addr.castAligned requires an address-to-pointer conversion");
    }

    const value: usize = @intCast(address.raw());
    const pointer = @typeInfo(Pointer).pointer;
    const alignment = pointer.alignment orelse @alignOf(pointer.child);

    if (value % alignment != 0) {
        return error.Misaligned;
    }

    return cast(Pointer, address);
}

fn isAddress(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"enum" => @hasDecl(T, "__StdxAddress"),
        else => false,
    };
}

fn isThinPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.size != .slice,
        else => false,
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

    test "address ranges preserve exclusive bounds and byte offsets" {
        const range = try A.Range.fromStartLen(A.from(10), 10);
        const other = try A.Range.init(A.from(15), A.from(25));
        const overlap = range.intersection(other).?;

        try testing.expectEqual(@as(u8, 10), range.len());
        try testing.expect(range.contains(A.from(10)));
        try testing.expect(!range.contains(A.from(20)));
        try testing.expectEqual(A.from(15), overlap.start);
        try testing.expectEqual(A.from(20), overlap.end);
        try testing.expectEqual(@as(?u8, 3), range.offsetOf(A.from(13)));
        try testing.expectEqual(@as(?A, A.from(13)), range.atOffset(3));
        try testing.expectEqual(@as(?A, null), range.atOffset(10));
        try testing.expect(!range.overlaps(A.Range.empty(A.from(15))));
    }

    test "address range construction and shifts reject unrepresentable endpoints" {
        const high = try A.Range.init(A.from(250), A.max());
        const shifted = try high.shiftBackward(5);

        try testing.expectEqual(A.from(245), shifted.start);
        try testing.expectEqual(A.from(250), shifted.end);
        try testing.expectError(error.InvalidRange, A.Range.init(A.from(2), A.from(1)));
        try testing.expectError(error.Overflow, A.Range.fromStartLen(A.max(), 1));
        try testing.expectError(error.Overflow, high.shiftForward(1));
        try testing.expectError(error.Overflow, high.shiftBackward(251));
    }

    test "address casts preserve byte offsets across domains" {
        var bytes = [_]u8{ 10, 20, 30, 40 };
        const physical = cast(PhysAddr, bytes[0..].ptr);
        const virtual = cast(VirtAddr, physical);
        const pointer = cast([*]u8, try virtual.add(2));

        pointer[0] = 99;

        try testing.expectEqualSlices(u8, &.{ 10, 20, 99, 40 }, &bytes);
    }

    test "a pointer to a slice addresses its descriptor rather than its payload" {
        var bytes = [_]u8{ 10, 20, 30, 40 };
        var slice: []u8 = &bytes;
        const address = cast(VirtAddr, &slice);
        const pointer = cast(*[]u8, address);

        pointer.len = 2;

        try testing.expectEqualSlices(u8, &.{ 10, 20 }, slice);
        try testing.expectEqualSlices(u8, &.{ 10, 20, 30, 40 }, &bytes);
    }

    test "aligned casts honor natural and explicit pointer alignment" {
        var bytes: [32]u8 align(16) = @splat(0);
        const address = cast(VirtAddr, &bytes[0]);
        const aligned = try castAligned(*align(16) u8, address);
        const unaligned = try address.add(1);

        aligned.* = 99;

        try testing.expectEqual(@as(u8, 99), bytes[0]);
        try testing.expectError(error.Misaligned, castAligned(*align(16) u8, unaligned));
        try testing.expectError(error.Misaligned, castAligned(*const u64, unaligned));
    }

    test "address arithmetic detects overflow and underflow" {
        const a = A.from(10);

        try testing.expectEqual(@as(u8, 12), (try a.add(2)).raw());
        try testing.expectEqual(@as(u8, 8), (try a.sub(2)).raw());
        try testing.expectEqual(@as(u8, 2), try a.diff(A.from(8)));
        try testing.expectError(error.Overflow, A.max().add(1));
        try testing.expectError(error.Overflow, A.zero().sub(1));
        try testing.expectError(error.Overflow, A.zero().diff(A.from(1)));
    }

    test "signed offsets preserve direction and reject both address boundaries" {
        inline for (.{ u1, u8, u17, u64 }) |Int| {
            const AddressT = Address(opaque {}, Int);
            const Signed = @Int(.signed, @bitSizeOf(Int));
            const minimum = std.math.minInt(Signed);
            const magnitude: Int = @abs(minimum);

            try testing.expectEqual(AddressT.zero(), try AddressT.from(magnitude).offset(minimum));
            try testing.expectEqual(AddressT.max(), try AddressT.max().offset(0));
            try testing.expectError(error.Overflow, AddressT.zero().offset(-1));
            try testing.expectError(error.Overflow, AddressT.from(magnitude - 1).offset(minimum));
        }

        try testing.expectEqual(A.from(74), try A.from(10).offset(64));
        try testing.expectEqual(A.from(10), try A.from(74).offset(-64));
        try testing.expectEqual(A.max(), try A.from(128).offset(127));
        try testing.expectError(error.Overflow, A.from(129).offset(127));
        try testing.expectError(error.Overflow, A.max().offset(1));
    }

    test "address alignment preserves rounding and errors" {
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

    test "address arithmetic and alignment work at comptime" {
        comptime {
            const a = A.from(10);
            const rounded = try a.alignUp(8);

            try testing.expectEqual(@as(u8, 16), rounded.raw());
            try testing.expectEqual(@as(u8, 6), try rounded.diff(a));

            const forward = try a.offset(64);
            const backward = try forward.offset(-64);
            const minimum = try A.from(128).offset(std.math.minInt(i8));

            try testing.expectEqual(A.from(74), forward);
            try testing.expectEqual(a, backward);
            try testing.expectEqual(A.zero(), minimum);
        }
    }
};
