//! Allocation-placement contract tests. Spec: docs/specs/algo/allocation.md.

const std = @import("std");

const stdx = @import("stdx");

const allocation = stdx.algo.allocation;
const Range = allocation.Range;
const Request = allocation.Request;
const Selection = allocation.Selection;
const FirstFit = allocation.FirstFit;
const BestFit = allocation.BestFit;
const WorstFit = allocation.WorstFit;
const Buddy = allocation.Buddy;

const testing = std.testing;

fn r(comptime start: usize, comptime end: usize) Range {
    return Range.of(start, end);
}

fn expectPartition(source: Range, selection: Selection) !void {
    try testing.expectEqual(source.start, selection.prefix.start);
    try testing.expectEqual(selection.range.start, selection.prefix.end);
    try testing.expectEqual(selection.range.end, selection.suffix.start);
    try testing.expectEqual(source.end, selection.suffix.end);
    try testing.expect(selection.range.isValid());
    try testing.expect(selection.prefix.isValid());
    try testing.expect(selection.suffix.isValid());
}

// ---- Request validation -------------------------------------------------

test "unit: Request len == 0 returns InvalidRequest" {
    const ranges = [_]Range{r(0, 16)};
    try testing.expectError(error.InvalidRequest, FirstFit.select(&ranges, .{ .len = 0 }));
    try testing.expectError(error.InvalidRequest, BestFit.select(&ranges, .{ .len = 0 }));
    try testing.expectError(error.InvalidRequest, WorstFit.select(&ranges, .{ .len = 0 }));
}

test "unit: Request alignment == 0 returns InvalidAlignment" {
    const ranges = [_]Range{r(0, 16)};
    try testing.expectError(
        error.InvalidAlignment,
        FirstFit.select(&ranges, .{ .len = 4, .alignment = 0 }),
    );
    try testing.expectError(
        error.InvalidAlignment,
        BestFit.select(&ranges, .{ .len = 4, .alignment = 0 }),
    );
    try testing.expectError(
        error.InvalidAlignment,
        WorstFit.select(&ranges, .{ .len = 4, .alignment = 0 }),
    );
}

test "unit: non-power-of-two alignment returns InvalidAlignment" {
    const ranges = [_]Range{r(0, 16)};
    try testing.expectError(
        error.InvalidAlignment,
        FirstFit.select(&ranges, .{ .len = 4, .alignment = 3 }),
    );
    try testing.expectError(
        error.InvalidAlignment,
        FirstFit.select(&ranges, .{ .len = 4, .alignment = 6 }),
    );
    try testing.expectError(
        error.InvalidAlignment,
        FirstFit.select(&ranges, .{ .len = 4, .alignment = 10 }),
    );
}

test "unit: aligned and misaligned starts both produce candidates" {
    // Already aligned start.
    {
        const ranges = [_]Range{r(16, 32)};
        const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 8 })).?;
        try testing.expectEqual(@as(usize, 16), sel.range.start);
        try testing.expectEqual(@as(usize, 24), sel.range.end);
        try testing.expect(sel.prefix.isEmpty());
        try expectPartition(ranges[0], sel);
    }
    // Misaligned start: candidate skips to the next aligned offset.
    {
        const ranges = [_]Range{r(3, 32)};
        const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 8 })).?;
        try testing.expectEqual(@as(usize, 8), sel.range.start);
        try testing.expectEqual(@as(usize, 16), sel.range.end);
        try testing.expectEqual(@as(usize, 5), sel.prefix.len());
        try expectPartition(ranges[0], sel);
    }
}

test "unit: candidate end overflow returns Overflow" {
    const max = std.math.maxInt(usize);
    // alignUp overflow path: source.start + (alignment - 1) overflows.
    {
        const ranges = [_]Range{r(max, max)};
        try testing.expectError(
            error.Overflow,
            FirstFit.select(&ranges, .{ .len = 1, .alignment = 2 }),
        );
    }
    // candidate_start + len overflow path: aligned start fits but adding
    // len overflows.
    {
        const ranges = [_]Range{r(max - 3, max)};
        // alignment 1 means candidate_start == max - 3; len > 3 overflows
        // only if start + len > usize_max; len = 5 gives start+len wrap.
        try testing.expectError(
            error.Overflow,
            FirstFit.select(&ranges, .{ .len = 5, .alignment = 1 }),
        );
    }
}

// ---- Selection behavior -------------------------------------------------

test "unit: empty free_ranges returns null" {
    const ranges = [_]Range{};
    try testing.expectEqual(@as(?Selection, null), try FirstFit.select(&ranges, .{ .len = 1 }));
    try testing.expectEqual(@as(?Selection, null), try BestFit.select(&ranges, .{ .len = 1 }));
    try testing.expectEqual(@as(?Selection, null), try WorstFit.select(&ranges, .{ .len = 1 }));
}

test "unit: no fitting range returns null" {
    const ranges = [_]Range{ r(0, 2), r(10, 13), r(20, 23) };
    try testing.expectEqual(@as(?Selection, null), try FirstFit.select(&ranges, .{ .len = 4 }));
    try testing.expectEqual(@as(?Selection, null), try BestFit.select(&ranges, .{ .len = 4 }));
    try testing.expectEqual(@as(?Selection, null), try WorstFit.select(&ranges, .{ .len = 4 }));
}

test "unit: FirstFit picks the first source range that fits" {
    const ranges = [_]Range{ r(0, 2), r(10, 20), r(30, 100) };
    const sel = (try FirstFit.select(&ranges, .{ .len = 4 })).?;
    try testing.expectEqual(@as(usize, 1), sel.index);
    try testing.expectEqual(@as(usize, 10), sel.range.start);
    try testing.expectEqual(@as(usize, 14), sel.range.end);
    try expectPartition(ranges[1], sel);
}

test "unit: FirstFit respects alignment inside a source range" {
    const ranges = [_]Range{r(5, 64)};
    const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 16 })).?;
    try testing.expectEqual(@as(usize, 16), sel.range.start);
    try testing.expectEqual(@as(usize, 24), sel.range.end);
    try expectPartition(ranges[0], sel);
}

test "unit: BestFit chooses smallest leftover" {
    const ranges = [_]Range{ r(0, 20), r(30, 38), r(50, 100) };
    // Asking for 5 units: leftovers are 15, 3, 45 → choose middle.
    const sel = (try BestFit.select(&ranges, .{ .len = 5 })).?;
    try testing.expectEqual(@as(usize, 1), sel.index);
    try testing.expectEqual(@as(usize, 30), sel.range.start);
    try expectPartition(ranges[1], sel);
}

test "unit: BestFit tie-break by lowest range.start, then lowest index" {
    // Two ranges with identical leftover (len=5 each) → tie on leftover.
    // Lower range.start (and lower index) wins.
    const ranges = [_]Range{ r(0, 10), r(20, 30) };
    const sel = (try BestFit.select(&ranges, .{ .len = 5 })).?;
    try testing.expectEqual(@as(usize, 0), sel.index);
    try testing.expectEqual(@as(usize, 0), sel.range.start);
}

test "unit: WorstFit chooses largest leftover" {
    const ranges = [_]Range{ r(0, 20), r(30, 38), r(50, 100) };
    // Asking for 5: leftovers 15, 3, 45 → choose last.
    const sel = (try WorstFit.select(&ranges, .{ .len = 5 })).?;
    try testing.expectEqual(@as(usize, 2), sel.index);
    try testing.expectEqual(@as(usize, 50), sel.range.start);
    try expectPartition(ranges[2], sel);
}

test "unit: WorstFit tie-break by lowest range.start, then lowest index" {
    const ranges = [_]Range{ r(0, 10), r(20, 30) };
    const sel = (try WorstFit.select(&ranges, .{ .len = 5 })).?;
    try testing.expectEqual(@as(usize, 0), sel.index);
    try testing.expectEqual(@as(usize, 0), sel.range.start);
}

test "unit: Selection.index identifies the source slice index" {
    const ranges = [_]Range{ r(0, 1), r(10, 11), r(20, 30) };
    const sel = (try FirstFit.select(&ranges, .{ .len = 4 })).?;
    try testing.expectEqual(@as(usize, 2), sel.index);
}

test "unit: prefix, range, suffix exactly partition source" {
    const ranges = [_]Range{r(7, 40)};
    const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 8 })).?;
    try expectPartition(ranges[0], sel);
    // Concretely: prefix [7,8), range [8,16), suffix [16,40).
    try testing.expectEqual(@as(usize, 7), sel.prefix.start);
    try testing.expectEqual(@as(usize, 8), sel.prefix.end);
    try testing.expectEqual(@as(usize, 8), sel.range.start);
    try testing.expectEqual(@as(usize, 16), sel.range.end);
    try testing.expectEqual(@as(usize, 16), sel.suffix.start);
    try testing.expectEqual(@as(usize, 40), sel.suffix.end);
}

test "unit: empty prefix and empty suffix cases" {
    // Empty prefix: aligned start equals source.start.
    {
        const ranges = [_]Range{r(16, 32)};
        const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 8 })).?;
        try testing.expect(sel.prefix.isEmpty());
    }
    // Empty suffix: candidate_end == source.end.
    {
        const ranges = [_]Range{r(0, 8)};
        const sel = (try FirstFit.select(&ranges, .{ .len = 8 })).?;
        try testing.expect(sel.suffix.isEmpty());
    }
    // Both empty: exact fit.
    {
        const ranges = [_]Range{r(0, 8)};
        const sel = (try FirstFit.select(&ranges, .{ .len = 8, .alignment = 8 })).?;
        try testing.expect(sel.prefix.isEmpty());
        try testing.expect(sel.suffix.isEmpty());
    }
}

test "unit: selection does not mutate input free ranges" {
    var ranges = [_]Range{ r(0, 4), r(10, 20), r(30, 100) };
    const snapshot = ranges;
    _ = try FirstFit.select(&ranges, .{ .len = 8 });
    _ = try BestFit.select(&ranges, .{ .len = 8 });
    _ = try WorstFit.select(&ranges, .{ .len = 8 });
    for (ranges, snapshot) |a, b| {
        try testing.expectEqual(b.start, a.start);
        try testing.expectEqual(b.end, a.end);
    }
}

// ---- Buddy behavior -----------------------------------------------------

test "unit: Buddy.blockSize(0) == 1 and grows by powers of two" {
    try testing.expectEqual(@as(usize, 1), try Buddy.blockSize(0));
    try testing.expectEqual(@as(usize, 2), try Buddy.blockSize(1));
    try testing.expectEqual(@as(usize, 4), try Buddy.blockSize(2));
    try testing.expectEqual(@as(usize, 1024), try Buddy.blockSize(10));
}

test "unit: Buddy.blockSize overflow for unrepresentable orders" {
    const bits = @bitSizeOf(usize);
    try testing.expectError(error.Overflow, Buddy.blockSize(@intCast(bits)));
    try testing.expectError(error.Overflow, Buddy.blockSize(@intCast(bits + 1)));
}

test "unit: Buddy.orderForLen exact for powers of two, rounds up otherwise" {
    try testing.expectEqual(@as(u8, 0), try Buddy.orderForLen(1));
    try testing.expectEqual(@as(u8, 1), try Buddy.orderForLen(2));
    try testing.expectEqual(@as(u8, 2), try Buddy.orderForLen(3));
    try testing.expectEqual(@as(u8, 2), try Buddy.orderForLen(4));
    try testing.expectEqual(@as(u8, 3), try Buddy.orderForLen(5));
    try testing.expectEqual(@as(u8, 3), try Buddy.orderForLen(8));
    try testing.expectEqual(@as(u8, 10), try Buddy.orderForLen(1024));
    try testing.expectEqual(@as(u8, 11), try Buddy.orderForLen(1025));
}

test "unit: Buddy.orderForLen(0) returns InvalidRequest" {
    try testing.expectError(error.InvalidRequest, Buddy.orderForLen(0));
}

test "unit: Buddy.orderForLen overflow for unrepresentable len" {
    const bits = @bitSizeOf(usize);
    // 1 << (bits - 1) maps to order bits-1.
    const highest_pow2: usize = @as(usize, 1) << @intCast(bits - 1);
    try testing.expectEqual(@as(u8, @intCast(bits - 1)), try Buddy.orderForLen(highest_pow2));
    // Anything bigger requires order >= bits → Overflow.
    try testing.expectError(error.Overflow, Buddy.orderForLen(highest_pow2 + 1));
    try testing.expectError(error.Overflow, Buddy.orderForLen(std.math.maxInt(usize)));
}

test "unit: Buddy.contains includes start, excludes end" {
    const block = Buddy.Block{ .start = 16, .order = 3 }; // size = 8 → [16, 24)
    try testing.expect(try Buddy.contains(block, 16));
    try testing.expect(try Buddy.contains(block, 20));
    try testing.expect(try Buddy.contains(block, 23));
    try testing.expect(!(try Buddy.contains(block, 24)));
    try testing.expect(!(try Buddy.contains(block, 15)));
}

test "unit: Buddy.buddyOf returns adjacent same-order block" {
    // order 3 → size 8. start 16 buddy = 16 XOR 8 = 24.
    const a = Buddy.Block{ .start = 16, .order = 3 };
    const b = try Buddy.buddyOf(a);
    try testing.expectEqual(@as(usize, 24), b.start);
    try testing.expectEqual(@as(u8, 3), b.order);
    // Buddy of buddy is original.
    const back = try Buddy.buddyOf(b);
    try testing.expectEqual(a.start, back.start);
    // Adjacent in the other direction.
    const c = Buddy.Block{ .start = 24, .order = 3 };
    const d = try Buddy.buddyOf(c);
    try testing.expectEqual(@as(usize, 16), d.start);
}

test "unit: Buddy.parentOf returns containing next-order block" {
    // Block [16, 24) at order 3; parent at order 4 has size 16 → [16, 32).
    const a = Buddy.Block{ .start = 16, .order = 3 };
    const p = try Buddy.parentOf(a);
    try testing.expectEqual(@as(usize, 16), p.start);
    try testing.expectEqual(@as(u8, 4), p.order);
    // Block [24, 32) at order 3; parent at order 4 has size 16 → [16, 32).
    const b = Buddy.Block{ .start = 24, .order = 3 };
    const q = try Buddy.parentOf(b);
    try testing.expectEqual(@as(usize, 16), q.start);
    try testing.expectEqual(@as(u8, 4), q.order);
}

test "unit: Buddy.parentOf overflow when parent unrepresentable" {
    const bits = @bitSizeOf(usize);
    // Order at max representable: parent's blockSize would overflow.
    const top: u8 = @intCast(bits - 1);
    const block = Buddy.Block{ .start = 0, .order = top };
    try testing.expectError(error.Overflow, Buddy.parentOf(block));
}

test "unit: Buddy.split returns left/right children with exact starts and order" {
    const block = Buddy.Block{ .start = 16, .order = 3 }; // size 8
    const kids = try Buddy.split(block);
    try testing.expectEqual(@as(usize, 16), kids[0].start);
    try testing.expectEqual(@as(u8, 2), kids[0].order);
    try testing.expectEqual(@as(usize, 20), kids[1].start);
    try testing.expectEqual(@as(u8, 2), kids[1].order);
}

test "unit: Buddy.split of order 0 returns InvalidRequest" {
    const block = Buddy.Block{ .start = 0, .order = 0 };
    try testing.expectError(error.InvalidRequest, Buddy.split(block));
}

test "unit: Buddy.canCoalesce true for siblings, false otherwise" {
    // True: order 2, size 4. starts 0 and 4 share parent at 0/order 3.
    try testing.expect(Buddy.canCoalesce(
        .{ .start = 0, .order = 2 },
        .{ .start = 4, .order = 2 },
    ));
    // True: starts 8 and 12 share parent at 8/order 3.
    try testing.expect(Buddy.canCoalesce(
        .{ .start = 8, .order = 2 },
        .{ .start = 12, .order = 2 },
    ));
    // False: same order, not buddies (different parents).
    try testing.expect(!Buddy.canCoalesce(
        .{ .start = 4, .order = 2 },
        .{ .start = 8, .order = 2 },
    ));
    // False: different orders.
    try testing.expect(!Buddy.canCoalesce(
        .{ .start = 0, .order = 2 },
        .{ .start = 4, .order = 3 },
    ));
}

// ---- Model tests --------------------------------------------------------

const Strategy = enum { first, best, worst };

fn referenceSelect(
    strategy: Strategy,
    free_ranges: []const Range,
    request: Request,
) allocation.Error!?Selection {
    if (request.len == 0) return error.InvalidRequest;
    if (request.alignment == 0) return error.InvalidAlignment;
    // Power-of-two check via popcount.
    if (@popCount(request.alignment) != 1) return error.InvalidAlignment;

    var best: ?Selection = null;
    var best_leftover: usize = 0;
    for (free_ranges, 0..) |source, index| {
        // Aligned start; reject if rounding overflows.
        const mask = request.alignment - 1;
        const sum = std.math.add(usize, source.start, mask) catch return error.Overflow;
        const start = sum & ~mask;
        const end = std.math.add(usize, start, request.len) catch return error.Overflow;
        if (start > source.end or end > source.end) continue;
        const sel: Selection = .{
            .index = index,
            .range = .{ .start = start, .end = end },
            .prefix = .{ .start = source.start, .end = start },
            .suffix = .{ .start = end, .end = source.end },
        };
        if (strategy == .first) return sel;
        const leftover = sel.prefix.len() + sel.suffix.len();
        const replace = if (best) |b| blk: {
            const cmp_better = switch (strategy) {
                .best => leftover < best_leftover,
                .worst => leftover > best_leftover,
                .first => unreachable,
            };
            if (cmp_better) break :blk true;
            if (leftover != best_leftover) break :blk false;
            // Tie: lower range.start wins, then lower index.
            if (sel.range.start != b.range.start) break :blk sel.range.start < b.range.start;
            break :blk sel.index < b.index;
        } else true;
        if (replace) {
            best = sel;
            best_leftover = leftover;
        }
    }
    return best;
}

fn expectSelectionEq(a: ?Selection, b: ?Selection) !void {
    if (a == null) {
        try testing.expectEqual(@as(?Selection, null), b);
        return;
    }
    try testing.expect(b != null);
    const x = a.?;
    const y = b.?;
    try testing.expectEqual(x.index, y.index);
    try testing.expectEqual(x.range.start, y.range.start);
    try testing.expectEqual(x.range.end, y.range.end);
    try testing.expectEqual(x.prefix.start, y.prefix.start);
    try testing.expectEqual(x.prefix.end, y.prefix.end);
    try testing.expectEqual(x.suffix.start, y.suffix.start);
    try testing.expectEqual(x.suffix.end, y.suffix.end);
}

fn checkAgainstReference(
    free_ranges: []const Range,
    request: Request,
) !void {
    try expectSelectionEq(
        try referenceSelect(.first, free_ranges, request),
        try FirstFit.select(free_ranges, request),
    );
    try expectSelectionEq(
        try referenceSelect(.best, free_ranges, request),
        try BestFit.select(free_ranges, request),
    );
    try expectSelectionEq(
        try referenceSelect(.worst, free_ranges, request),
        try WorstFit.select(free_ranges, request),
    );
}

test "model: FirstFit/BestFit/WorstFit match reference on multi-range scans" {
    // Multiple free ranges, various sizes.
    const cases = [_]struct { ranges: []const Range, req: Request }{
        // Multiple free ranges, plain alignment 1.
        .{ .ranges = &.{ r(0, 2), r(5, 12), r(20, 21), r(30, 100) }, .req = .{ .len = 4 } },
        // Alignment-induced prefix.
        .{ .ranges = &.{ r(3, 30), r(40, 64), r(70, 96) }, .req = .{ .len = 8, .alignment = 8 } },
        // Empty prefix and suffix opportunities.
        .{ .ranges = &.{ r(0, 8), r(16, 32), r(48, 50) }, .req = .{ .len = 8, .alignment = 8 } },
        // Fragmented no-fit.
        .{ .ranges = &.{ r(0, 3), r(8, 11), r(16, 19) }, .req = .{ .len = 4 } },
        // Worst-fit obvious winner.
        .{ .ranges = &.{ r(0, 8), r(10, 60), r(70, 78) }, .req = .{ .len = 4 } },
        // BestFit obvious winner.
        .{ .ranges = &.{ r(0, 100), r(110, 116), r(200, 300) }, .req = .{ .len = 5 } },
    };
    for (cases) |c| try checkAgainstReference(c.ranges, c.req);
}

test "model: tie-break by lowest range.start when leftovers tie" {
    // Two ranges of equal length and identical alignment outcome → tie on
    // leftover. BestFit and WorstFit both pick the lower-start one.
    const ranges = [_]Range{ r(0, 10), r(20, 30), r(40, 50) };
    try checkAgainstReference(&ranges, .{ .len = 4 });
    try checkAgainstReference(&ranges, .{ .len = 10 });
}

test "model: tie-break by lowest index when range.start ties (post-alignment)" {
    // Construct two source ranges whose aligned starts and lengths give
    // identical leftover AND identical candidate range.start cannot
    // happen across distinct sources (starts are strictly ascending and
    // non-overlapping). The lowest-index tie-break is exercised only via
    // the (impossible-in-valid-input) path; reference and impl agree on
    // all legal inputs.
    const ranges = [_]Range{ r(0, 8), r(8, 16), r(16, 24), r(24, 32) };
    try checkAgainstReference(&ranges, .{ .len = 8, .alignment = 8 });
    try checkAgainstReference(&ranges, .{ .len = 4, .alignment = 4 });
}

test "model: alignment-induced prefixes across the slice" {
    const ranges = [_]Range{ r(1, 9), r(9, 17), r(17, 41) };
    try checkAgainstReference(&ranges, .{ .len = 4, .alignment = 8 });
    try checkAgainstReference(&ranges, .{ .len = 8, .alignment = 8 });
    try checkAgainstReference(&ranges, .{ .len = 16, .alignment = 16 });
}

test "model: fragmented no-fit returns null across all strategies" {
    const ranges = [_]Range{ r(0, 3), r(10, 13), r(20, 23), r(30, 33) };
    try checkAgainstReference(&ranges, .{ .len = 4 });
    try checkAgainstReference(&ranges, .{ .len = 100 });
}

test "compile: public surface exposes spec namespace" {
    _ = allocation.Range;
    _ = allocation.Error;
    _ = allocation.Request;
    _ = allocation.Selection;
    _ = allocation.FirstFit;
    _ = allocation.BestFit;
    _ = allocation.WorstFit;
    _ = allocation.Buddy;
    _ = allocation.Buddy.Block;
}
