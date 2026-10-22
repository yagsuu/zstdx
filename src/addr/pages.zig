//! Page-sized address helpers. See `docs/specs/addr/pages.md`.

const std = @import("std");

pub const _4kib = 4 * 1024;
pub const _16kib = 16 * 1024;
pub const _64kib = 64 * 1024;
pub const _2mib = 2 * 1024 * 1024;
pub const _1gib = 1024 * 1024 * 1024;

pub fn Page(comptime Addr: type, comptime page_size: Addr.Int) type {
    comptime {
        requireAddress(Addr);

        if (page_size == 0) {
            @compileError("Page size must be non-zero");
        }

        if (!std.math.isPowerOfTwo(page_size)) {
            @compileError("Page size must be a power of two");
        }
    }

    return struct {
        pub const Address = Addr;
        pub const Int = Addr.Int;

        pub const Error = error{ Misaligned, Overflow, OutOfBounds };

        pub const size: Int = page_size;
        pub const mask: Int = size - 1;
        pub const shift: comptime_int = @ctz(size);

        pub const Count = enum(Int) {
            _,

            const Self = @This();

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

            /// Rejects byte counts that are not page multiples.
            pub fn fromBytes(value: Int) Error!Self {
                if ((value & mask) != 0) {
                    return error.Misaligned;
                }
                return from(value >> shift);
            }

            pub fn fromBytesCeil(value: Int) Error!Self {
                const rounded = std.math.add(Int, value, mask) catch return error.Overflow;
                return from(rounded >> shift);
            }

            pub fn bytes(self: Self) Error!Int {
                return std.math.mul(Int, self.raw(), size) catch return error.Overflow;
            }
        };

        pub const Base = enum(Int) {
            _,

            const Self = @This();

            pub fn from(address: Addr) Error!Self {
                if (!isAligned(address)) {
                    return error.Misaligned;
                }
                return @enumFromInt(address.raw());
            }

            pub fn fromInt(value: Int) Error!Self {
                return from(Addr.from(value));
            }

            pub fn addr(self: Self) Addr {
                return Addr.from(self.raw());
            }

            pub fn raw(self: Self) Int {
                return @intFromEnum(self);
            }

            pub fn index(self: Self) Int {
                return self.raw() >> shift;
            }

            pub fn isValid(self: Self) bool {
                return (self.raw() & mask) == 0;
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }

            pub fn isAligned(address: Addr) bool {
                return (address.raw() & mask) == 0;
            }

            pub fn alignDown(address: Addr) Error!Self {
                return @enumFromInt(address.raw() & ~mask);
            }

            pub fn alignUp(address: Addr) Error!Self {
                const added = std.math.add(Int, address.raw(), mask) catch return error.Overflow;
                return @enumFromInt(added & ~mask);
            }

            pub fn add(self: Self, count: Count) Error!Self {
                const bytes = try count.bytes();
                const value = std.math.add(Int, self.raw(), bytes) catch return error.Overflow;
                return fromInt(value);
            }

            pub fn sub(self: Self, count: Count) Error!Self {
                const bytes = try count.bytes();
                const value = std.math.sub(Int, self.raw(), bytes) catch return error.Overflow;
                return fromInt(value);
            }
        };

        pub const Range = struct {
            base: Base,
            count: Count,

            const Self = @This();

            pub fn init(base: Base, count: Count) Error!Self {
                _ = try base.add(count);
                return .{ .base = base, .count = count };
            }

            /// Requires a page-aligned base and byte length.
            pub fn fromBytes(base: Addr, len: Int) Error!Self {
                const aligned = try Base.from(base);
                const count = try Count.fromBytes(len);
                return init(aligned, count);
            }

            pub fn covering(start: Addr, len: Int) Error!Self {
                const base = try Base.alignDown(start);
                const raw_end = std.math.add(Int, start.raw(), len) catch return error.Overflow;
                const finish = try Base.alignUp(Addr.from(raw_end));
                const extent = finish.raw() - base.raw();

                return .{ .base = base, .count = Count.from(extent >> shift) };
            }

            pub fn empty(at: Base) Self {
                return .{ .base = at, .count = Count.zero() };
            }

            pub fn isValid(self: Self) bool {
                _ = self.base.add(self.count) catch return false;
                return true;
            }

            pub fn assertValid(self: Self) void {
                std.debug.assert(self.isValid());
            }

            pub fn isEmpty(self: Self) bool {
                return self.count.raw() == 0;
            }

            pub fn bytes(self: Self) Int {
                return self.end().raw() - self.base.raw();
            }

            pub fn end(self: Self) Base {
                return self.base.add(self.count) catch unreachable;
            }

            pub fn contains(self: Self, frame: Base) bool {
                const finish = self.end().raw();
                return self.base.raw() <= frame.raw() and frame.raw() < finish;
            }

            pub fn containsAddr(self: Self, addr: Addr) bool {
                const finish = self.end().raw();
                return self.base.raw() <= addr.raw() and addr.raw() < finish;
            }

            pub fn containsRange(self: Self, other: Self) bool {
                const self_start = self.base.raw();
                const self_end = self.end().raw();
                const other_start = other.base.raw();
                const other_end = other.end().raw();
                return self_start <= other_start and other_end <= self_end;
            }

            pub fn overlaps(self: Self, other: Self) bool {
                const self_start = self.base.raw();
                const self_end = self.end().raw();
                const other_start = other.base.raw();
                const other_end = other.end().raw();

                if (self.isEmpty() or other.isEmpty()) {
                    return false;
                }

                return self_start < other_end and other_start < self_end;
            }

            pub fn isAdjacent(self: Self, other: Self) bool {
                const self_start = self.base.raw();
                const self_end = self.end().raw();
                const other_start = other.base.raw();
                const other_end = other.end().raw();
                return self_end == other_start or other_end == self_start;
            }

            pub fn intersection(self: Self, other: Self) ?Self {
                const self_end = self.end().raw();
                const other_end = other.end().raw();
                const start = @max(self.base.raw(), other.base.raw());
                const finish = @min(self_end, other_end);

                if (start >= finish) {
                    return null;
                }

                return .{
                    .base = @enumFromInt(start),
                    .count = Count.from((finish - start) >> shift),
                };
            }

            pub fn span(self: Self, other: Self) Self {
                const start = @min(self.base.raw(), other.base.raw());
                const finish = @max(self.end().raw(), other.end().raw());
                return .{
                    .base = @enumFromInt(start),
                    .count = Count.from((finish - start) >> shift),
                };
            }

            pub fn splitAt(self: Self, at: Base) Error!struct { left: Self, right: Self } {
                at.assertValid();

                const start = self.base.raw();
                const finish = self.end().raw();
                const point = at.raw();

                if (point < start or point > finish) {
                    return error.OutOfBounds;
                }

                return .{
                    .left = .{ .base = self.base, .count = Count.from((point - start) >> shift) },
                    .right = .{ .base = at, .count = Count.from((finish - point) >> shift) },
                };
            }
        };
    };
}

fn requireAddress(comptime Addr: type) void {
    if (!@hasDecl(Addr, "Int")) {
        @compileError("Page requires an Address-compatible type with Int");
    }

    if (!@hasDecl(Addr, "from")) {
        @compileError("Page requires an Address-compatible type with from");
    }

    if (!@hasDecl(Addr, "raw")) {
        @compileError("Page requires an Address-compatible type with raw");
    }

    const info = @typeInfo(Addr.Int);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Page requires Address.Int to be an unsigned integer type");
    }

    const zero: Addr = Addr.from(0);
    const raw_value: Addr.Int = zero.raw();
    _ = raw_value;
}

pub const unit = struct {
    const testing = std.testing;
    const address = @import("address.zig");

    const A = address.Address(opaque {}, u8);
    const P = Page(A, 4);

    test "unit: page families distinguish address domains and page sizes" {
        const Phys4K = Page(address.PhysAddr, _4kib);
        const Virt4K = Page(address.VirtAddr, _4kib);
        const Phys2M = Page(address.PhysAddr, _2mib);

        try testing.expect(Phys4K.Base != Virt4K.Base);
        try testing.expect(Phys4K.Base != Phys2M.Base);
    }

    test "unit: page counts preserve checked byte rounding" {
        try testing.expectEqual(@as(u8, 2), (try P.Count.fromBytes(8)).raw());
        try testing.expectError(error.Misaligned, P.Count.fromBytes(5));
        try testing.expectEqual(@as(u8, 0), (try P.Count.fromBytesCeil(0)).raw());
        try testing.expectEqual(@as(u8, 1), (try P.Count.fromBytesCeil(1)).raw());
        try testing.expectEqual(@as(u8, 1), (try P.Count.fromBytesCeil(4)).raw());
        try testing.expectEqual(@as(u8, 2), (try P.Count.fromBytesCeil(5)).raw());
        try testing.expectError(error.Overflow, P.Count.fromBytesCeil(254));
        try testing.expectEqual(@as(u8, 12), try P.Count.from(3).bytes());
        try testing.expectError(error.Overflow, P.Count.max().bytes());
    }

    test "unit: page bases validate alignment and checked page arithmetic" {
        const frame = try P.Base.fromInt(8);
        const next = try frame.add(P.Count.from(2));
        const previous = try frame.sub(P.Count.from(1));

        frame.assertValid();
        try testing.expectEqual(@as(u8, 2), frame.index());
        try testing.expectEqual(@as(u8, 16), next.raw());
        try testing.expectEqual(@as(u8, 4), previous.raw());
        try testing.expectError(error.Misaligned, P.Base.fromInt(1));
        try testing.expectEqual(@as(u8, 8), (try P.Base.alignDown(A.from(11))).raw());
        try testing.expectEqual(@as(u8, 12), (try P.Base.alignUp(A.from(9))).raw());
        try testing.expectEqual(@as(u8, 252), (try P.Base.alignUp(A.from(252))).raw());
        try testing.expectError(error.Overflow, P.Base.alignUp(A.from(254)));
        try testing.expectError(error.Overflow, (try P.Base.fromInt(252)).add(P.Count.from(1)));
        try testing.expectError(error.Overflow, frame.sub(P.Count.from(3)));
        try testing.expectError(error.Misaligned, @as(P.Base, @enumFromInt(1)).add(P.Count.zero()));
    }

    test "unit: page range construction checks alignment and endpoints" {
        const base = try P.Base.fromInt(8);
        const range = try P.Range.init(base, P.Count.from(3));
        const from_bytes = try P.Range.fromBytes(A.from(8), 8);
        const span = try P.Range.covering(A.from(9), 4);
        const aligned_empty = try P.Range.covering(A.from(8), 0);
        const unaligned_empty = try P.Range.covering(A.from(9), 0);
        const invalid = P.Range.empty(@enumFromInt(1));

        range.assertValid();
        try testing.expectEqual(@as(u8, 12), range.bytes());
        try testing.expectEqual(@as(u8, 20), range.end().raw());
        try testing.expectEqual(@as(u8, 2), from_bytes.count.raw());
        try testing.expectEqual(@as(u8, 8), span.base.raw());
        try testing.expectEqual(@as(u8, 2), span.count.raw());
        try testing.expect(aligned_empty.isEmpty());
        try testing.expectEqual(@as(u8, 1), unaligned_empty.count.raw());
        try testing.expectError(error.Misaligned, P.Range.fromBytes(A.from(9), 4));
        try testing.expectError(error.Misaligned, P.Range.fromBytes(A.from(8), 5));
        try testing.expectError(error.Overflow, P.Range.init(
            try P.Base.fromInt(252),
            P.Count.from(1),
        ));
        try testing.expectError(error.Overflow, P.Range.covering(A.from(254), 2));
        try testing.expectError(error.Overflow, P.Range.covering(A.from(254), 0));
        try testing.expect(!invalid.isValid());
    }

    test "unit: half-open range operations preserve empty boundaries" {
        const left = try P.Range.fromBytes(A.from(8), 12);
        const right = try P.Range.fromBytes(A.from(20), 8);
        const middle = try P.Range.fromBytes(A.from(12), 8);
        const empty = P.Range.empty(try P.Base.fromInt(20));
        const joined = left.span(right);

        try testing.expect(left.contains(left.base));
        try testing.expect(!left.contains(left.end()));
        try testing.expect(left.containsAddr(A.from(19)));
        try testing.expect(!left.containsAddr(A.from(20)));
        try testing.expect(left.containsRange(middle));
        try testing.expect(left.containsRange(empty));
        try testing.expect(!left.overlaps(right));
        try testing.expect(left.isAdjacent(right));
        try testing.expect(!left.overlaps(empty));
        try testing.expect(empty.isAdjacent(right));
        try testing.expectEqual(@as(?P.Range, null), left.intersection(right));
        try testing.expectEqual(@as(?P.Range, null), left.intersection(empty));
        try testing.expectEqual(middle, left.intersection(middle).?);
        try testing.expectEqual(@as(u8, 8), joined.base.raw());
        try testing.expectEqual(@as(u8, 5), joined.count.raw());
        try testing.expectEqual(empty, empty.span(empty));
    }

    test "unit: range splitting accepts endpoints and rejects outside boundaries" {
        const range = try P.Range.fromBytes(A.from(8), 12);
        const split = try range.splitAt(try P.Base.fromInt(12));
        const at_start = try range.splitAt(range.base);
        const at_end = try range.splitAt(range.end());
        const empty = P.Range.empty(range.base);
        const split_empty = try empty.splitAt(range.base);

        try testing.expectEqual(@as(u8, 1), split.left.count.raw());
        try testing.expectEqual(@as(u8, 2), split.right.count.raw());
        try testing.expectEqual(split.left.end(), split.right.base);
        try testing.expect(at_start.left.isEmpty());
        try testing.expectEqual(range, at_start.right);
        try testing.expect(at_end.right.isEmpty());
        try testing.expectEqual(range, at_end.left);
        try testing.expectEqual(empty, split_empty.left);
        try testing.expectEqual(empty, split_empty.right);
        try testing.expectError(error.OutOfBounds, range.splitAt(try P.Base.fromInt(4)));
        try testing.expectError(error.OutOfBounds, range.splitAt(try P.Base.fromInt(24)));
    }

    test "unit: page arithmetic and range endpoints work at comptime" {
        comptime {
            const count = try P.Count.fromBytesCeil(7);
            const frame = try P.Base.fromInt(8);
            const range = try P.Range.init(frame, count);
            const split = try range.splitAt(try frame.add(P.Count.from(1)));

            try testing.expectEqual(@as(u8, 2), count.raw());
            try testing.expectEqual(@as(u8, 16), range.end().raw());
            try testing.expectEqual(@as(u8, 1), split.right.count.raw());
        }
    }
};
