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

/// Returns a half-open unsigned-integer range type parameterized by `T`.
/// The returned type is a plain value (`{ start, end }`) so copying is
/// checkpointing; no allocation, no waiting.
pub fn Range(comptime T: type) type {
    comptime requireUnsignedInt(T);
    return struct {
        start: T,
        end: T,

        const Self = @This();

        /// `InvalidRange`: caller passed `end < start`.
        /// `Overflow`: arithmetic on `start`, `end`, or `len` exceeded `T`.
        /// `OutOfBounds`: point lies outside `[start, end]`.
        pub const Error = error{ InvalidRange, Overflow, OutOfBounds };

        /// Constructs `[start, end)`. Returns `error.InvalidRange` when
        /// `end < start`.
        pub fn fromBounds(start: T, end: T) Error!Self {
            if (end < start) return error.InvalidRange;
            return .{ .start = start, .end = end };
        }

        /// Constructs `[start, end)` at compile time. Invalid bounds are a
        /// compile error.
        pub fn of(comptime start: T, comptime end: T) Self {
            if (end < start) @compileError("Range.of requires start <= end");
            return .{ .start = start, .end = end };
        }

        /// Constructs `[start, start + length)`. Returns `error.Overflow` when
        /// `start + length` exceeds `T`.
        pub fn fromStartLen(start: T, length: T) Error!Self {
            const end = std.math.add(T, start, length) catch return error.Overflow;
            return fromBounds(start, end);
        }

        /// Returns an empty range positioned at `at`.
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

        /// Returns `true` only when the intersection is non-empty; empty ranges
        /// never overlap.
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

        /// Returns the non-empty intersection of `self` and `other`, or `null`.
        pub fn intersection(self: Self, other: Self) ?Self {
            self.assertValid();
            other.assertValid();

            const start = @max(self.start, other.start);
            const end = @min(self.end, other.end);

            if (end <= start) return null;
            return .{ .start = start, .end = end };
        }

        /// Returns the smallest range covering both inputs, including any gap.
        pub fn span(self: Self, other: Self) Self {
            self.assertValid();
            other.assertValid();
            return .{
                .start = @min(self.start, other.start),
                .end = @max(self.end, other.end),
            };
        }

        /// Returns the prefix of `self` ending at `point`. `point` must lie in
        /// `[start, end]`; otherwise returns `error.OutOfBounds`.
        pub fn prefix(self: Self, point: T) Error!Self {
            self.assertValid();
            if (point < self.start or point > self.end) return error.OutOfBounds;
            return .{ .start = self.start, .end = point };
        }

        /// Returns the suffix of `self` starting at `point`. `point` must lie in
        /// `[start, end]`; otherwise returns `error.OutOfBounds`.
        pub fn suffix(self: Self, point: T) Error!Self {
            self.assertValid();
            if (point < self.start or point > self.end) return error.OutOfBounds;
            return .{ .start = point, .end = self.end };
        }

        /// Returns `value - start` when `value` is contained, else `null`.
        pub fn offsetOf(self: Self, value: T) ?T {
            self.assertValid();
            if (!self.contains(value)) return null;
            return value - self.start;
        }

        /// Returns `start + offset` when `offset < len()`, else `null`.
        /// Symmetry with `offsetOf` preserves containment on round trip.
        pub fn atOffset(self: Self, offset: T) ?T {
            self.assertValid();
            if (offset >= self.len()) return null;
            return self.start + offset;
        }

        /// Shifts both endpoints forward by `amount`; returns `error.Overflow`
        /// when either endpoint would exceed `T`.
        pub fn shiftForward(self: Self, amount: T) Error!Self {
            self.assertValid();

            const start = std.math.add(T, self.start, amount) catch return error.Overflow;
            const end = std.math.add(T, self.end, amount) catch return error.Overflow;
            return .{ .start = start, .end = end };
        }

        /// Shifts both endpoints backward by `amount`; returns `error.Overflow`
        /// when subtraction would underflow `T`.
        pub fn shiftBackward(self: Self, amount: T) Error!Self {
            self.assertValid();
            if (amount > self.start) return error.Overflow;
            return .{ .start = self.start - amount, .end = self.end - amount };
        }
    };
}
