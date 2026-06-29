//! Half-open `[start, end)` ranges over an unsigned integer. Pure value
//! type; failed operations leave inputs unchanged. See
//! docs/specs/core/range.md.

const std = @import("std");

fn requireUnsignedInt(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Range requires an unsigned integer type");
    }
}

/// Half-open unsigned-integer range parameterized by `T`. The returned type
/// is a plain value (`{ start, end }`) so copying is checkpointing; no
/// allocation, no waiting.
pub fn Range(comptime T: type) type {
    comptime requireUnsignedInt(T);
    return struct {
        start: T,
        end: T,

        const Self = @This();

        /// `InvalidRange`: caller passed `end < start`.
        /// `Overflow`: arithmetic on `start`, `end`, or `len` exceeded `T`.
        /// `OutOfRange`: value or split point lies outside `[start, end)` /
        ///   `[start, end]`.
        pub const Error = error{ InvalidRange, Overflow, OutOfRange };

        /// Result of `splitAt`. `left` is `[start, point)`, `right` is
        /// `[point, end)`; either side may be empty when `point` is a boundary.
        pub const Split = struct {
            left: Self,
            right: Self,
        };

        /// Construct `[start, end)`. Returns `error.InvalidRange` when
        /// `end < start`.
        pub fn init(start: T, end: T) Error!Self {
            if (end < start) return error.InvalidRange;
            return .{ .start = start, .end = end };
        }

        /// Construct `[start, end)` without validating the invariant. Caller
        /// upholds `start <= end`.
        pub fn initUnchecked(start: T, end: T) Self {
            return .{ .start = start, .end = end };
        }

        /// Construct `[start, start + length)`. Returns `error.Overflow` when
        /// `start + length` exceeds `T`.
        pub fn fromStartLen(start: T, length: T) Error!Self {
            const end = std.math.add(T, start, length) catch return error.Overflow;
            return init(start, end);
        }

        /// Empty range positioned at `at`.
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

        /// Empty `other` is contained when its point lies in `[start, end]`.
        pub fn containsRange(self: Self, other: Self) bool {
            self.assertValid();
            other.assertValid();
            return other.start >= self.start and other.end <= self.end;
        }

        /// True only when the intersection is non-empty; empty ranges never
        /// overlap.
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

        /// Non-empty intersection of `self` and `other`, or `null` when empty.
        pub fn intersection(self: Self, other: Self) ?Self {
            self.assertValid();
            other.assertValid();
            const start = @max(self.start, other.start);
            const end = @min(self.end, other.end);
            if (end <= start) return null;
            return .{ .start = start, .end = end };
        }

        /// Smallest range covering both inputs, including any gap.
        pub fn span(self: Self, other: Self) Self {
            self.assertValid();
            other.assertValid();
            return .{
                .start = @min(self.start, other.start),
                .end = @max(self.end, other.end),
            };
        }

        /// Split at `point` in `[start, end]`. Out-of-range points return
        /// `error.OutOfRange`; `self` is unchanged.
        pub fn splitAt(self: Self, point: T) Error!Split {
            self.assertValid();
            if (point < self.start or point > self.end) return error.OutOfRange;
            return .{
                .left = .{ .start = self.start, .end = point },
                .right = .{ .start = point, .end = self.end },
            };
        }

        /// `value - start` when `value` is contained, else `null`.
        pub fn offsetOf(self: Self, value: T) ?T {
            self.assertValid();
            if (!self.contains(value)) return null;
            return value - self.start;
        }

        /// `start + offset` when `offset < len()`, else `error.OutOfRange`.
        pub fn atOffset(self: Self, offset: T) Error!T {
            self.assertValid();
            if (offset >= self.len()) return error.OutOfRange;
            return self.start + offset;
        }

        /// Shift both endpoints forward by `amount`; `error.Overflow` when
        /// either endpoint would exceed `T`.
        pub fn shiftForward(self: Self, amount: T) Error!Self {
            self.assertValid();
            const start = std.math.add(T, self.start, amount) catch return error.Overflow;
            const end = std.math.add(T, self.end, amount) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        /// Shift both endpoints backward by `amount`; `error.Overflow` when
        /// subtraction would underflow `T`.
        pub fn shiftBackward(self: Self, amount: T) Error!Self {
            self.assertValid();
            if (amount > self.start) return error.Overflow;
            return .{ .start = self.start - amount, .end = self.end - amount };
        }
    };
}
