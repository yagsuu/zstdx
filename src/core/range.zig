//! Half-open `[start, end)` and inclusive `[start, end]` ranges over unsigned
//! integers. Both range types are pure values. Failed operations leave inputs
//! unchanged. See `docs/specs/core/range.md`.

const std = @import("std");

pub fn Range(comptime T: type) type {
    comptime requireUnsignedInt(T);
    return struct {
        start: T,
        end: T,

        const Self = @This();

        pub const InvalidRangeError = error{InvalidRange};
        pub const OverflowError = error{Overflow};
        pub const OutOfBoundsError = error{OutOfBounds};
        pub const Error = InvalidRangeError || OverflowError || OutOfBoundsError;

        pub fn fromBounds(start: T, end: T) InvalidRangeError!Self {
            if (end < start) return error.InvalidRange;
            return .{ .start = start, .end = end };
        }

        pub fn of(comptime start: T, comptime end: T) Self {
            if (end < start) @compileError("Range.of requires start <= end");
            return .{ .start = start, .end = end };
        }

        pub fn fromStartLen(start: T, length: T) OverflowError!Self {
            const end = std.math.add(T, start, length) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        pub fn empty(at: T) Self {
            return .{ .start = at, .end = at };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert(self.isValid());
        }

        pub fn isValid(self: Self) bool {
            return self.start <= self.end;
        }

        pub fn len(self: Self) T {
            self.assertValid();
            return self.end - self.start;
        }

        pub fn isEmpty(self: Self) bool {
            self.assertValid();
            return self.start == self.end;
        }

        pub fn contains(self: Self, value: T) bool {
            self.assertValid();
            return value >= self.start and value < self.end;
        }

        pub fn containsRange(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return other.start >= self.start and other.end <= self.end;
        }

        pub fn overlaps(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return @max(self.start, other.start) < @min(self.end, other.end);
        }

        pub fn isAdjacent(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return self.end == other.start or other.end == self.start;
        }

        pub fn intersection(self: Self, other: Self) ?Self {
            self.assertValid();
            other.assertValid();

            const start = @max(self.start, other.start);
            const end = @min(self.end, other.end);

            if (end <= start) return null;
            return .{ .start = start, .end = end };
        }

        pub fn span(self: Self, other: Self) Self {
            self.assertValid();
            other.assertValid();
            return .{
                .start = @min(self.start, other.start),
                .end = @max(self.end, other.end),
            };
        }

        pub fn prefix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (point < self.start or point > self.end) return error.OutOfBounds;
            return .{ .start = self.start, .end = point };
        }

        pub fn suffix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (point < self.start or point > self.end) return error.OutOfBounds;
            return .{ .start = point, .end = self.end };
        }

        pub fn offsetOf(self: Self, value: T) ?T {
            self.assertValid();
            if (!self.contains(value)) return null;
            return value - self.start;
        }

        pub fn atOffset(self: Self, offset: T) ?T {
            self.assertValid();
            if (offset >= self.len()) return null;
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
            if (amount > self.start) return error.Overflow;
            return .{ .start = self.start - amount, .end = self.end - amount };
        }
    };
}

/// The cardinality must be representable in `T`, so `[0, maxInt(T)]` is
/// invalid.
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

        pub fn fromBounds(start: T, end: T) InvalidRangeError!Self {
            const self: Self = .{ .start = start, .end = end };
            if (!self.isValid()) return error.InvalidRange;
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
            if (length == 0) return error.InvalidRange;
            const end = std.math.add(T, start, length - 1) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        pub fn single(at: T) Self {
            return .{ .start = at, .end = at };
        }

        pub fn fromRange(range: HalfOpen) ?Self {
            range.assertValid();
            if (range.isEmpty()) return null;
            return .{ .start = range.start, .end = range.end - 1 };
        }

        pub fn toRange(self: Self) OverflowError!HalfOpen {
            self.assertValid();
            const end = std.math.add(T, self.end, 1) catch return error.Overflow;
            return .{ .start = self.start, .end = end };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert(self.isValid());
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

            if (end < start) return null;
            return .{ .start = start, .end = end };
        }

        pub fn span(self: Self, other: Self) OverflowError!Self {
            self.assertValid();
            other.assertValid();

            const start = @min(self.start, other.start);
            const end = @max(self.end, other.end);
            if (start == 0 and end == std.math.maxInt(T)) return error.Overflow;
            return .{ .start = start, .end = end };
        }

        pub fn prefix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (!self.contains(point)) return error.OutOfBounds;
            return .{ .start = self.start, .end = point };
        }

        pub fn suffix(self: Self, point: T) OutOfBoundsError!Self {
            self.assertValid();
            if (!self.contains(point)) return error.OutOfBounds;
            return .{ .start = point, .end = self.end };
        }

        pub fn offsetOf(self: Self, value: T) ?T {
            self.assertValid();
            if (!self.contains(value)) return null;
            return value - self.start;
        }

        pub fn atOffset(self: Self, offset: T) ?T {
            self.assertValid();
            if (offset > self.end - self.start) return null;
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
            if (amount > self.start) return error.Overflow;
            return .{ .start = self.start - amount, .end = self.end - amount };
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
