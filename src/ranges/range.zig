//! half-open ranges over unsigned integers or typed addresses; inclusive ranges over unsigned integers.

const std = @import("std");

pub fn Range(comptime T: type) type {
    const Value = RangeEndpoint(T);
    return struct {
        start: T,
        end: T,

        const Self = @This();
        pub const Int = Value.Int;

        pub const InvalidRangeError = error{InvalidRange};
        pub const OverflowError = error{Overflow};
        pub const OutOfBoundsError = error{OutOfBounds};
        pub const Error = InvalidRangeError || OverflowError || OutOfBoundsError;

        pub fn init(start: T, end: T) InvalidRangeError!Self {
            if (Value.raw(end) < Value.raw(start)) {
                return error.InvalidRange;
            }
            return .{ .start = start, .end = end };
        }

        pub fn of(comptime start: T, comptime end: T) Self {
            if (comptime Value.raw(end) < Value.raw(start)) {
                @compileError("Range.of requires start <= end");
            }
            return .{ .start = start, .end = end };
        }

        pub fn fromStartLen(start: T, length: Int) OverflowError!Self {
            const end = std.math.add(Int, Value.raw(start), length) catch return error.Overflow;
            return .{ .start = start, .end = Value.from(end) };
        }

        pub fn empty(at: T) Self {
            return .{ .start = at, .end = at };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert(self.isValid());
        }

        pub fn isValid(self: Self) bool {
            return Value.raw(self.start) <= Value.raw(self.end);
        }

        pub fn len(self: Self) Int {
            self.assertValid();
            return Value.raw(self.end) - Value.raw(self.start);
        }

        pub fn isEmpty(self: Self) bool {
            self.assertValid();
            return self.start == self.end;
        }

        pub fn contains(self: Self, value: T) bool {
            self.assertValid();
            return Value.raw(value) >= Value.raw(self.start) and Value.raw(value) < Value.raw(self.end);
        }

        pub fn containsRange(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return Value.raw(other.start) >= Value.raw(self.start) and Value.raw(other.end) <= Value.raw(self.end);
        }

        pub fn overlaps(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return @max(Value.raw(self.start), Value.raw(other.start)) < @min(Value.raw(self.end), Value.raw(other.end));
        }

        pub fn isAdjacent(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return self.end == other.start or other.end == self.start;
        }

        pub fn intersection(self: Self, other: Self) ?Self {
            self.assertValid();
            other.assertValid();

            const start = @max(Value.raw(self.start), Value.raw(other.start));
            const end = @min(Value.raw(self.end), Value.raw(other.end));

            if (end <= start) {
                return null;
            }

            return .{ .start = Value.from(start), .end = Value.from(end) };
        }

        pub fn span(self: Self, other: Self) Self {
            self.assertValid();
            other.assertValid();
            return .{
                .start = Value.from(@min(Value.raw(self.start), Value.raw(other.start))),
                .end = Value.from(@max(Value.raw(self.end), Value.raw(other.end))),
            };
        }

        pub fn prefix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (Value.raw(point) < Value.raw(self.start) or Value.raw(point) > Value.raw(self.end)) {
                return error.OutOfBounds;
            }
            return .{ .start = self.start, .end = point };
        }

        pub fn suffix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (Value.raw(point) < Value.raw(self.start) or Value.raw(point) > Value.raw(self.end)) {
                return error.OutOfBounds;
            }
            return .{ .start = point, .end = self.end };
        }

        pub fn offsetOf(self: Self, value: T) ?Int {
            if (!self.contains(value)) {
                return null;
            }
            return Value.raw(value) - Value.raw(self.start);
        }

        pub fn atOffset(self: Self, offset: Int) ?T {
            if (offset >= self.len()) {
                return null;
            }
            return Value.from(Value.raw(self.start) + offset);
        }

        pub fn shiftForward(self: Self, amount: Int) OverflowError!Self {
            self.assertValid();

            const start = std.math.add(Int, Value.raw(self.start), amount) catch return error.Overflow;
            const end = std.math.add(Int, Value.raw(self.end), amount) catch return error.Overflow;
            return .{ .start = Value.from(start), .end = Value.from(end) };
        }

        pub fn shiftBackward(self: Self, amount: Int) OverflowError!Self {
            self.assertValid();
            if (amount > Value.raw(self.start)) {
                return error.Overflow;
            }
            return .{
                .start = Value.from(Value.raw(self.start) - amount),
                .end = Value.from(Value.raw(self.end) - amount),
            };
        }
    };
}

pub fn InclusiveRange(comptime T: type) type {
    comptime requireNonZeroUnsignedInt(T);
    return struct {
        start: T,
        end: T,

        const Self = @This();
        const HalfOpen = Range(T);

        pub const InvalidRangeError = error{InvalidRange};
        pub const OverflowError = error{Overflow};
        pub const OutOfBoundsError = error{OutOfBounds};
        pub const Error = InvalidRangeError || OverflowError || OutOfBoundsError;

        pub fn init(start: T, end: T) InvalidRangeError!Self {
            const self: Self = .{ .start = start, .end = end };
            if (!self.isValid()) {
                return error.InvalidRange;
            }
            return self;
        }

        pub fn of(comptime start: T, comptime end: T) Self {
            if (end < start) {
                @compileError("InclusiveRange.of requires start <= end");
            }

            if (start == 0 and end == std.math.maxInt(T)) {
                @compileError("InclusiveRange.of excludes [0, maxInt(T)]");
            }

            return .{ .start = start, .end = end };
        }

        pub fn fromStartLen(
            start: T,
            length: T,
        ) (InvalidRangeError || OverflowError)!Self {
            if (length == 0) {
                return error.InvalidRange;
            }

            const end = std.math.add(T, start, length - 1) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        pub fn single(at: T) Self {
            return .{ .start = at, .end = at };
        }

        pub fn fromRange(range: HalfOpen) ?Self {
            if (range.isEmpty()) {
                return null;
            }
            return .{ .start = range.start, .end = range.end - 1 };
        }

        pub fn toRange(self: Self) OverflowError!HalfOpen {
            self.assertValid();
            const end = std.math.add(T, self.end, 1) catch return error.Overflow;
            return .{ .start = self.start, .end = end };
        }

        pub fn isValid(self: Self) bool {
            return self.start <= self.end and
                !(self.start == 0 and self.end == std.math.maxInt(T));
        }

        pub fn len(self: Self) T {
            self.assertValid();
            return self.end - self.start + 1;
        }

        pub fn isSingleton(self: Self) bool {
            self.assertValid();
            return self.start == self.end;
        }

        pub fn contains(self: Self, value: T) bool {
            self.assertValid();
            return value >= self.start and value <= self.end;
        }

        pub fn containsRange(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return other.start >= self.start and other.end <= self.end;
        }

        pub fn overlaps(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return @max(self.start, other.start) <= @min(self.end, other.end);
        }

        pub fn isAdjacent(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return (self.end < other.start and other.start - self.end == 1) or
                (other.end < self.start and self.start - other.end == 1);
        }

        pub fn intersection(self: Self, other: Self) ?Self {
            self.assertValid();
            other.assertValid();

            const start = @max(self.start, other.start);
            const end = @min(self.end, other.end);

            if (end < start) {
                return null;
            }

            return .{ .start = start, .end = end };
        }

        pub fn span(self: Self, other: Self) OverflowError!Self {
            self.assertValid();
            other.assertValid();

            const start = @min(self.start, other.start);
            const end = @max(self.end, other.end);
            if (start == 0 and end == std.math.maxInt(T)) {
                return error.Overflow;
            }

            return .{ .start = start, .end = end };
        }

        pub fn prefix(self: Self, point: T) OutOfBoundsError!Self {
            if (!self.contains(point)) {
                return error.OutOfBounds;
            }
            return .{ .start = self.start, .end = point };
        }

        pub fn suffix(self: Self, point: T) OutOfBoundsError!Self {
            if (!self.contains(point)) {
                return error.OutOfBounds;
            }
            return .{ .start = point, .end = self.end };
        }

        pub fn offsetOf(self: Self, value: T) ?T {
            if (!self.contains(value)) {
                return null;
            }
            return value - self.start;
        }

        pub fn atOffset(self: Self, offset: T) ?T {
            self.assertValid();
            if (offset > self.end - self.start) {
                return null;
            }
            return self.start + offset;
        }

        pub fn shiftForward(self: Self, amount: T) OverflowError!Self {
            self.assertValid();

            const start = std.math.add(T, self.start, amount) catch return error.Overflow;
            const end = std.math.add(T, self.end, amount) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        pub fn shiftBackward(self: Self, amount: T) OverflowError!Self {
            self.assertValid();
            if (amount > self.start) {
                return error.Overflow;
            }
            return .{ .start = self.start - amount, .end = self.end - amount };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert(self.isValid());
        }
    };
}

fn RangeEndpoint(comptime T: type) type {
    const Backing = switch (@typeInfo(T)) {
        .int => T,
        .@"enum" => if (@hasDecl(T, "Int") and @hasDecl(T, "from") and @hasDecl(T, "raw"))
            T.Int
        else
            @compileError("Range requires an unsigned integer or address endpoint"),
        else => @compileError("Range requires an unsigned integer or address endpoint"),
    };
    comptime requireUnsignedInt(Backing);

    return struct {
        pub const Int = Backing;

        fn raw(value: T) Int {
            if (comptime T == Int) {
                return value;
            }
            return value.raw();
        }

        fn from(value: Int) T {
            if (comptime T == Int) {
                return value;
            }
            return T.from(value);
        }
    };
}

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Range requires an unsigned integer type");
    }
}

fn requireNonZeroUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned or info.int.bits == 0) {
        @compileError("InclusiveRange requires a non-zero-width unsigned integer type");
    }
}

pub const unit = struct {
    const testing = std.testing;

    test "unit: half-open construction preserves empty bounds and detects overflow" {
        const R = Range(u64);
        const literal = comptime R.of(5, 9);
        const empty = comptime R.of(7, 7);

        try testing.expectEqual(R{ .start = 5, .end = 9 }, literal);
        try testing.expectEqual(R.empty(7), empty);
        try testing.expect(empty.isEmpty());
        try testing.expectEqual(@as(u64, 0), (try R.init(5, 5)).len());
        try testing.expectError(error.InvalidRange, R.init(2, 1));
        try testing.expectError(error.Overflow, R.fromStartLen(std.math.maxInt(u64), 1));
    }

    test "unit: half-open containment and intersection exclude the final endpoint and empty ranges" {
        const R = Range(u64);
        const range = try R.init(10, 20);
        const empty = R.empty(15);

        try testing.expect(range.contains(10));
        try testing.expect(!range.contains(20));
        try testing.expect(range.containsRange(R.of(12, 18)));
        try testing.expect(!range.containsRange(R.of(12, 21)));
        try testing.expect(range.overlaps(R.of(19, 21)));
        try testing.expect(!range.overlaps(empty));
        try testing.expect(!empty.overlaps(range));
        try testing.expectEqual(@as(?R, null), range.intersection(empty));
        try testing.expect(range.isAdjacent(R.of(20, 25)));
        try testing.expectEqual(R.of(15, 20), range.intersection(R.of(15, 25)).?);
        try testing.expectEqual(R.of(0, 20), range.span(R.of(0, 12)));
    }

    test "unit: half-open splits admit endpoints while offsets exclude the end" {
        const R = Range(u64);
        const range = R.of(10, 20);

        try testing.expectEqual(R.of(10, 14), try range.prefix(14));
        try testing.expectEqual(R.of(14, 20), try range.suffix(14));
        try testing.expectEqual(R.empty(10), try range.prefix(10));
        try testing.expectEqual(R.empty(20), try range.suffix(20));
        try testing.expectError(error.OutOfBounds, range.prefix(21));
        try testing.expectError(error.OutOfBounds, range.suffix(21));
        try testing.expectEqual(@as(?u64, 3), range.offsetOf(13));
        try testing.expectEqual(@as(?u64, null), range.offsetOf(20));
        try testing.expectEqual(@as(?u64, 13), range.atOffset(3));
        try testing.expectEqual(@as(?u64, null), range.atOffset(10));
    }

    test "unit: half-open shifts preserve length and report overflow in both directions" {
        const R = Range(u64);
        const range = R.of(10, 20);
        const high = R.of(std.math.maxInt(u64) - 1, std.math.maxInt(u64));

        try testing.expectEqual(R.of(15, 25), try range.shiftForward(5));
        try testing.expectEqual(R.of(5, 15), try range.shiftBackward(5));
        try testing.expectError(error.Overflow, range.shiftBackward(11));
        try testing.expectError(error.Overflow, high.shiftForward(2));
    }

    test "unit: inclusive construction rejects inverted bounds and unrepresentable cardinality" {
        const R = InclusiveRange(u8);
        const literal = comptime R.of(5, 9);

        try testing.expectEqual(literal, try R.init(5, 9));
        try testing.expect(R.single(7).isSingleton());
        try testing.expectError(error.InvalidRange, R.init(9, 5));
        try testing.expectError(error.InvalidRange, R.init(0, std.math.maxInt(u8)));
        try testing.expect(!(R{ .start = 0, .end = std.math.maxInt(u8) }).isValid());
        try testing.expectEqual(R.of(10, 14), try R.fromStartLen(10, 5));
        try testing.expectError(error.InvalidRange, R.fromStartLen(10, 0));
        try testing.expectError(error.Overflow, R.fromStartLen(250, 7));
    }

    test "unit: inclusive length covers singleton and maximum representable cardinalities" {
        const R = InclusiveRange(u8);
        const U16Domain = InclusiveRange(u32);
        const all_u16 = comptime U16Domain.of(0, std.math.maxInt(u16));

        try testing.expectEqual(@as(u8, 1), R.single(0).len());
        try testing.expectEqual(@as(u8, 255), R.of(0, 254).len());
        try testing.expectEqual(@as(u8, 255), R.of(1, 255).len());
        try testing.expectEqual(@as(u32, 65_536), all_u16.len());
    }

    test "unit: inclusive containment and intersection include shared endpoints" {
        const R = InclusiveRange(u8);
        const range = R.of(10, 20);

        try testing.expect(range.contains(10));
        try testing.expect(range.contains(20));
        try testing.expect(!range.contains(9));
        try testing.expect(range.containsRange(R.of(12, 18)));
        try testing.expect(!range.containsRange(R.of(12, 21)));
        try testing.expect(range.overlaps(R.of(20, 25)));
        try testing.expect(!range.overlaps(R.of(21, 25)));
        try testing.expect(range.isAdjacent(R.of(21, 25)));
        try testing.expect(R.of(21, 25).isAdjacent(range));
        try testing.expect(R.single(0).isAdjacent(R.single(1)));
        try testing.expect(R.single(255).isAdjacent(R.single(254)));
        try testing.expectEqual(R.single(20), range.intersection(R.of(20, 25)).?);
        try testing.expectEqual(@as(?R, null), range.intersection(R.of(21, 25)));
        try testing.expectEqual(R.of(10, 25), try range.span(R.of(21, 25)));
        try testing.expectError(error.Overflow, R.single(0).span(R.single(255)));
    }

    test "unit: inclusive splits share the split point and offsets include the end" {
        const R = InclusiveRange(u8);
        const range = R.of(10, 20);
        const prefix = try range.prefix(14);
        const suffix = try range.suffix(14);

        try testing.expectEqual(R.of(10, 14), prefix);
        try testing.expectEqual(R.of(14, 20), suffix);
        try testing.expectEqual(R.single(14), prefix.intersection(suffix).?);
        try testing.expectEqual(R.single(10), try range.prefix(10));
        try testing.expectEqual(R.single(20), try range.suffix(20));
        try testing.expectError(error.OutOfBounds, range.prefix(9));
        try testing.expectError(error.OutOfBounds, range.suffix(21));
        try testing.expectEqual(@as(?u8, 0), range.offsetOf(10));
        try testing.expectEqual(@as(?u8, 10), range.offsetOf(20));
        try testing.expectEqual(@as(?u8, 20), range.atOffset(10));
        try testing.expectEqual(@as(?u8, null), range.atOffset(11));
        try testing.expectEqual(@as(?u8, null), range.offsetOf(21));
    }

    test "unit: inclusive shifts preserve bounds and report overflow in both directions" {
        const R = InclusiveRange(u8);
        const range = R.of(10, 20);

        try testing.expectEqual(R.of(15, 25), try range.shiftForward(5));
        try testing.expectEqual(R.of(5, 15), try range.shiftBackward(5));
        try testing.expectError(error.Overflow, range.shiftBackward(11));
        try testing.expectError(error.Overflow, R.of(250, 255).shiftForward(1));
    }

    test "unit: range conversions preserve bounds and reject an unrepresentable exclusive end" {
        const R = Range(u8);
        const I = InclusiveRange(u8);
        const inclusive = I.fromRange(R.of(10, 20)).?;

        try testing.expectEqual(I.of(10, 19), inclusive);
        try testing.expectEqual(R.of(10, 20), try inclusive.toRange());
        try testing.expectEqual(@as(?I, null), I.fromRange(R.empty(10)));
        try testing.expectEqual(R.of(10, 11), try I.single(10).toRange());
        try testing.expectError(error.Overflow, I.of(1, std.math.maxInt(u8)).toRange());
    }
};
