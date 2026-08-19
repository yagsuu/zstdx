//! Deterministic placement selection over caller-owned free ranges.
//! Operations use only values; they do not allocate, wait, or mutate input.
//! See `docs/specs/algo/alloc/placement.md`.

const std = @import("std");

const power_of_two = @import("../../bits/power_of_two.zig");

pub const Range = @import("../../core/range.zig").Range(usize);

pub const Error = error{
    InvalidRequest,
    InvalidAlignment,
    Overflow,
};

/// Allocation request in caller-defined units. `alignment` defaults to `1`.
pub const Request = struct {
    len: usize,
    alignment: usize = 1,
};

/// Selected range and the exact partition of its source range.
pub const Selection = struct {
    index: usize,
    range: Range,
    prefix: Range,
    suffix: Range,
};

/// Selects the lowest aligned start in the lowest-index fitting range.
pub const FirstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);

        for (free_ranges, 0..) |source, index| {
            if (try candidateFor(source, index, request)) |selection| return selection;
        }

        return null;
    }
};

/// Selects the candidate with the smallest total leftover.
pub const BestFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);

        var best: ?Selection = null;
        var best_leftover: usize = 0;
        for (free_ranges, 0..) |source, index| {
            const candidate = (try candidateFor(source, index, request)) orelse continue;
            const leftover = leftoverOf(candidate);

            if (best) |current_best| {
                const strictly_smaller = leftover < best_leftover;
                const tied_and_earlier = leftover == best_leftover and isEarlier(candidate, current_best);

                if (strictly_smaller or tied_and_earlier) {
                    best = candidate;
                    best_leftover = leftover;
                }

                continue;
            }

            best = candidate;
            best_leftover = leftover;
        }

        return best;
    }
};

/// Selects the candidate with the largest total leftover.
pub const WorstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);

        var best: ?Selection = null;
        var best_leftover: usize = 0;
        for (free_ranges, 0..) |source, index| {
            const candidate = (try candidateFor(source, index, request)) orelse continue;
            const leftover = leftoverOf(candidate);

            if (best) |current_best| {
                const strictly_larger = leftover > best_leftover;
                const tied_and_earlier = leftover == best_leftover and isEarlier(candidate, current_best);

                if (strictly_larger or tied_and_earlier) {
                    best = candidate;
                    best_leftover = leftover;
                }

                continue;
            }

            best = candidate;
            best_leftover = leftover;
        }
        return best;
    }
};

fn validateRequest(request: Request) Error!void {
    if (request.len == 0) return error.InvalidRequest;
    if (request.alignment == 0 or !power_of_two.isPowerOfTwo(usize, request.alignment)) {
        return error.InvalidAlignment;
    }
}

fn candidateFor(source: Range, index: usize, request: Request) Error!?Selection {
    std.debug.assert(source.isValid());

    const mask = request.alignment - 1;
    const sum = std.math.add(usize, source.start, mask) catch return error.Overflow;
    const candidate_start = sum & ~mask;
    const candidate_end = std.math.add(usize, candidate_start, request.len) catch return error.Overflow;

    if (candidate_end > source.end) return null;

    std.debug.assert(candidate_start >= source.start);
    std.debug.assert(candidate_end <= source.end);
    std.debug.assert(candidate_end - candidate_start == request.len);

    return .{
        .index = index,
        .range = .{ .start = candidate_start, .end = candidate_end },
        .prefix = .{ .start = source.start, .end = candidate_start },
        .suffix = .{ .start = candidate_end, .end = source.end },
    };
}

fn leftoverOf(selection: Selection) usize {
    return selection.prefix.len() + selection.suffix.len();
}

fn isEarlier(a: Selection, b: Selection) bool {
    if (a.range.start != b.range.start) return a.range.start < b.range.start;
    return a.index < b.index;
}
