//! Allocation-placement algorithms over free ranges and buddy block arithmetic.
//! Operations use only values; they do not allocate, wait, or mutate input.
//! See `docs/specs/algo/allocation.md`.

const std = @import("std");

const power_of_two = @import("../bits/power_of_two.zig");

/// Half-open `[start, end)` extent in caller-defined units.
pub const Range = @import("../core/range.zig").Range(usize);

/// `InvalidRequest` occurs for a zero-length request or an otherwise meaningless operation.
/// `InvalidAlignment` occurs when alignment is zero or not a power of two.
/// `Overflow` occurs when checked candidate arithmetic or block arithmetic overflows `usize`.
pub const Error = error{
    InvalidRequest,
    InvalidAlignment,
    Overflow,
};

/// Allocation request in caller-defined units. `alignment` defaults to `1`, which
/// imposes no alignment constraint.
pub const Request = struct {
    len: usize,
    alignment: usize = 1,
};

/// Result of a selection. `prefix`, `range`, and `suffix` exactly
/// partition the source free range identified by `index`.
pub const Selection = struct {
    /// Index of the source free range in the input slice.
    index: usize,
    range: Range,
    prefix: Range,
    suffix: Range,
};

/// First-fit placement: lowest-index source range, then lowest aligned
/// start within it.
pub const FirstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);
        for (free_ranges, 0..) |source, index| {
            if (try candidateFor(source, index, request)) |selection| {
                return selection;
            }
        }
        return null;
    }
};

/// Best-fit placement: smallest total leftover. Tie-breaks: lowest
/// `range.start`, then lowest `index`.
pub const BestFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);
        var best: ?Selection = null;
        var best_leftover: usize = 0;
        for (free_ranges, 0..) |source, index| {
            const maybe = try candidateFor(source, index, request);
            const candidate = maybe orelse continue;
            const leftover = leftoverOf(candidate);

            if (best) |current_best| {
                const strictly_smaller = leftover < best_leftover;
                const tied_and_earlier = leftover == best_leftover and isEarlier(candidate, current_best);

                if (strictly_smaller or tied_and_earlier) {
                    best = candidate;
                    best_leftover = leftover;
                }
            } else {
                best = candidate;
                best_leftover = leftover;
            }
        }
        return best;
    }
};

/// Worst-fit placement: largest total leftover. Tie-breaks: lowest
/// `range.start`, then lowest `index`.
pub const WorstFit = struct {
    pub fn select(free_ranges: []const Range, request: Request) Error!?Selection {
        try validateRequest(request);
        var best: ?Selection = null;
        var best_leftover: usize = 0;
        for (free_ranges, 0..) |source, index| {
            const maybe = try candidateFor(source, index, request);
            const candidate = maybe orelse continue;
            const leftover = leftoverOf(candidate);

            if (best) |current_best| {
                const strictly_larger = leftover > best_leftover;
                const tied_and_earlier = leftover == best_leftover and isEarlier(candidate, current_best);

                if (strictly_larger or tied_and_earlier) {
                    best = candidate;
                    best_leftover = leftover;
                }
            } else {
                best = candidate;
                best_leftover = leftover;
            }
        }
        return best;
    }
};

/// Performs value-only block/order arithmetic for buddy-style allocators. It owns no
/// free-list state.
pub const Buddy = struct {
    pub const Block = struct {
        start: usize,
        order: u8,
    };

    /// `1 << order` in units. Returns `error.Overflow` when the shift is
    /// not representable in `usize`.
    pub fn blockSize(order: u8) Error!usize {
        if (order >= @bitSizeOf(usize)) return error.Overflow;
        return @as(usize, 1) << @intCast(order);
    }

    /// Smallest order whose block size can contain `len`. Returns
    /// `error.InvalidRequest` for `len == 0` and `error.Overflow` when no
    /// representable order suffices.
    pub fn orderForLen(len: usize) Error!u8 {
        if (len == 0) return error.InvalidRequest;
        if (len == 1) return 0;
        const bits = @bitSizeOf(usize);
        const raw = bits - @clz(len - 1);
        if (raw >= bits) return error.Overflow;
        return @intCast(raw);
    }

    /// Whether `index` lies in `[block.start, block.start + size)`.
    /// Returns `error.Overflow` when the block's end is not representable.
    pub fn contains(block: Block, index: usize) Error!bool {
        const size = try blockSize(block.order);
        const end = std.math.add(usize, block.start, size) catch return error.Overflow;
        return index >= block.start and index < end;
    }

    /// Adjacent same-order block sharing a parent: `start XOR size`.
    pub fn buddyOf(block: Block) Error!Block {
        const size = try blockSize(block.order);
        return .{ .start = block.start ^ size, .order = block.order };
    }

    /// Containing block of order `block.order + 1`. Returns
    /// `error.Overflow` when the parent order or size is not
    /// representable.
    pub fn parentOf(block: Block) Error!Block {
        if (block.order == std.math.maxInt(u8)) return error.Overflow;
        const parent_order: u8 = block.order + 1;
        const parent_size = try blockSize(parent_order);
        const parent_start = block.start & ~(parent_size - 1);
        _ = std.math.add(usize, parent_start, parent_size) catch return error.Overflow;
        return .{ .start = parent_start, .order = parent_order };
    }

    /// Two children of order `block.order - 1`. Returns
    /// `error.InvalidRequest` when `block.order == 0`.
    pub fn split(block: Block) Error![2]Block {
        if (block.order == 0) return error.InvalidRequest;
        const child_order: u8 = block.order - 1;
        const child_size = try blockSize(child_order);
        const right_start = std.math.add(usize, block.start, child_size) catch return error.Overflow;
        return .{
            .{ .start = block.start, .order = child_order },
            .{ .start = right_start, .order = child_order },
        };
    }

    /// Whether `left` and `right` are buddy siblings: same order and
    /// adjacent under the same parent. Invalid or unrepresentable blocks
    /// are programmer errors.
    pub fn canCoalesce(left: Block, right: Block) bool {
        if (left.order != right.order) return false;
        const size = blockSize(left.order) catch return false;
        return (left.start ^ size) == right.start;
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
