//! placement over caller-owned free ranges

const std = @import("std");

pub const Range = @import("core").Range(usize);
pub const Error = Impl.Error;

pub const Request = struct {
    len: usize,
    alignment: usize = 1,

    fn validate(self: Request) Error!void {
        if (self.len == 0) {
            return error.InvalidRequest;
        }

        if (self.alignment == 0 or !std.math.isPowerOfTwo(self.alignment)) {
            return error.InvalidAlignment;
        }
    }
};

pub const Selection = struct {
    index: usize,
    range: Range,
    prefix: Range,
    suffix: Range,

    fn leftover(self: Selection) usize {
        return self.prefix.len() + self.suffix.len();
    }

    fn precedes(self: Selection, other: Selection) bool {
        if (self.range.start != other.range.start) {
            return self.range.start < other.range.start;
        }
        return self.index < other.index;
    }
};

/// input order takes precedence over address order
pub const FirstFit = struct {
    pub fn select(ranges: []const Range, request: Request) Error!?Selection {
        return Impl.select(.first, ranges, request);
    }
};

/// minimizes total leftover, including alignment padding
pub const BestFit = struct {
    pub fn select(ranges: []const Range, request: Request) Error!?Selection {
        return Impl.select(.best, ranges, request);
    }
};

/// maximizes total leftover, including alignment padding
pub const WorstFit = struct {
    pub fn select(ranges: []const Range, request: Request) Error!?Selection {
        return Impl.select(.worst, ranges, request);
    }
};

const Impl = struct {
    const Error = error{
        InvalidRequest,
        InvalidAlignment,
        Overflow,
    };

    const Policy = enum { first, best, worst };

    fn select(comptime policy: Policy, ranges: []const Range, request: Request) Impl.Error!?Selection {
        try request.validate();

        var selected: ?Selection = null;
        var selected_leftover: usize = 0;
        for (ranges, 0..) |source, index| {
            const current = (try candidate(source, index, request)) orelse continue;
            if (policy == .first) {
                return current;
            }

            const leftover = current.leftover();
            if (selected) |previous| {
                const better = switch (policy) {
                    .first => unreachable,
                    .best => leftover < selected_leftover,
                    .worst => leftover > selected_leftover,
                };

                if (!better and (leftover != selected_leftover or !current.precedes(previous))) {
                    continue;
                }
            }

            selected = current;
            selected_leftover = leftover;
        }

        return selected;
    }

    fn candidate(source: Range, index: usize, request: Request) Impl.Error!?Selection {
        std.debug.assert(source.isValid());

        const mask = request.alignment - 1;
        if (std.math.maxInt(usize) - source.start < mask) {
            return error.Overflow;
        }

        const start = (source.start + mask) & ~mask;
        if (std.math.maxInt(usize) - start < request.len) {
            return error.Overflow;
        }

        const end = start + request.len;
        if (end > source.end) {
            return null;
        }

        return .{
            .index = index,
            .range = .{ .start = start, .end = end },
            .prefix = .{ .start = source.start, .end = start },
            .suffix = .{ .start = end, .end = source.end },
        };
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "aligned candidates partition their source including exact fits" {
        const cases = [_]struct {
            source: Range,
            expected: ?Selection,
        }{
            .{
                .source = .{ .start = 3, .end = 32 },
                .expected = .{
                    .index = 7,
                    .range = .{ .start = 8, .end = 16 },
                    .prefix = .{ .start = 3, .end = 8 },
                    .suffix = .{ .start = 16, .end = 32 },
                },
            },
            .{
                .source = .{ .start = 16, .end = 32 },
                .expected = .{
                    .index = 7,
                    .range = .{ .start = 16, .end = 24 },
                    .prefix = Range.empty(16),
                    .suffix = .{ .start = 24, .end = 32 },
                },
            },
            .{
                .source = .{ .start = 16, .end = 24 },
                .expected = .{
                    .index = 7,
                    .range = .{ .start = 16, .end = 24 },
                    .prefix = Range.empty(16),
                    .suffix = Range.empty(24),
                },
            },
            .{ .source = .{ .start = 1, .end = 8 }, .expected = null },
        };

        for (cases) |case| {
            const actual = try Impl.candidate(case.source, 7, .{ .len = 8, .alignment = 8 });
            try testing.expectEqualDeep(case.expected, actual);
        }
    }

    test "policies distinguish input order and total leftover including padding" {
        const ranges = [_]Range{
            .{ .start = 1, .end = 26 },
            .{ .start = 32, .end = 48 },
            .{ .start = 80, .end = 144 },
        };

        const request: Request = .{ .len = 8, .alignment = 16 };
        const first = (try Impl.select(.first, &ranges, request)).?;
        const best = (try Impl.select(.best, &ranges, request)).?;
        const worst = (try Impl.select(.worst, &ranges, request)).?;

        try testing.expectEqual(@as(usize, 0), first.index);
        try testing.expectEqual(Range.of(16, 24), first.range);
        try testing.expectEqual(@as(usize, 1), best.index);
        try testing.expectEqual(Range.of(32, 40), best.range);
        try testing.expectEqual(@as(usize, 2), worst.index);
        try testing.expectEqual(Range.of(80, 88), worst.range);
    }

    test "ties prefer aligned address then original index rather than source address" {
        const ranges = [_]Range{
            .{ .start = 35, .end = 51 },
            .{ .start = 33, .end = 49 },
            .{ .start = 1, .end = 17 },
        };

        const request: Request = .{ .len = 8, .alignment = 8 };
        const first = (try Impl.select(.first, &ranges, request)).?;

        try testing.expectEqual(@as(usize, 0), first.index);

        inline for (.{ Impl.Policy.best, Impl.Policy.worst }) |policy| {
            const earlier = (try Impl.select(policy, &ranges, request)).?;
            const same_address = (try Impl.select(policy, ranges[0..2], request)).?;

            try testing.expectEqual(@as(usize, 2), earlier.index);
            try testing.expectEqual(@as(usize, 8), earlier.range.start);
            try testing.expectEqual(@as(usize, 0), same_address.index);
            try testing.expectEqual(@as(usize, 40), same_address.range.start);
        }
    }

    test "validation precedes scanning even for empty inputs" {
        const ranges = [_]Range{ .{ .start = 0, .end = 2 }, .{ .start = 8, .end = 11 } };

        try testing.expectError(error.InvalidRequest, Impl.select(.best, &.{}, .{ .len = 0, .alignment = 0 }));
        try testing.expectError(error.InvalidAlignment, Impl.select(.best, &.{}, .{ .len = 1, .alignment = 0 }));
        try testing.expectError(error.InvalidAlignment, Impl.select(.best, &.{}, .{ .len = 1, .alignment = 3 }));
        try testing.expectEqual(@as(?Selection, null), try Impl.select(.best, &.{}, .{ .len = 1 }));
        try testing.expectEqual(@as(?Selection, null), try Impl.select(.best, &ranges, .{ .len = 4 }));
    }

    test "overflow is reported unless first fit already returned a selection" {
        const limit = std.math.maxInt(usize);
        const ranges = [_]Range{ .{ .start = 0, .end = 8 }, .{ .start = limit, .end = limit } };
        const request: Request = .{ .len = 1, .alignment = 2 };
        const first = (try Impl.select(.first, &ranges, request)).?;

        try testing.expectEqual(@as(usize, 0), first.index);
        try testing.expectError(error.Overflow, Impl.select(.best, &ranges, request));
        try testing.expectError(error.Overflow, Impl.select(.worst, &ranges, request));
        try testing.expectError(error.Overflow, Impl.select(.first, ranges[1..], request));
        try testing.expectError(error.Overflow, Impl.candidate(Range.of(limit - 3, limit), 0, .{ .len = 5 }));
    }
};
