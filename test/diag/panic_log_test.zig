//! Tests for `stdx.diag.PanicLog`. See `docs/specs/diag/panic-log.md`.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const PanicLog = stdx.diag.PanicLog;
const CachePad = stdx.mem.CachePad;
const testing = std.testing;

// Compile-time pins from the spec's Required tests: `Static(64)` factory
// legality, on-wire constant identities, size/alignment lower bounds.
// Rejected shapes (documented, not runtime-testable because Zig has no
// probe for `@compileError`):
//   - `Static(15)`: below `2 * header_bytes`;
//   - `Static(0)`: below `2 * header_bytes`;
//   - `Static(std.math.maxInt(u32) + 1)`: exceeds the u32 offset limit.
comptime {
    const S = PanicLog.Static(64);
    std.debug.assert(S.capacity_bytes_const == 64);
    std.debug.assert(S.header_bytes == 8);
    std.debug.assert(S.max_payload_bytes == 56);
    std.debug.assert(@sizeOf(S) >= 64 + @sizeOf(CachePad(std.atomic.Value(usize))));
    std.debug.assert(@alignOf(S) >= @alignOf(CachePad(std.atomic.Value(usize))));

    // The smallest legal capacity is exactly `2 * header_bytes`.
    _ = PanicLog.Static(16);
    // Non-power-of-two capacities are legal (indexing uses modulo).
    _ = PanicLog.Static(48);
}

fn fixedSink(buffer: []u8) std.Io.Writer {
    return std.Io.Writer.fixed(buffer);
}

test "contract: module compiles on any target" {
    // Instantiate the type on the host without touching any x86-only path.
    var log: PanicLog.Static(64) = .init();
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
}

test "unit: init yields empty log" {
    var log: PanicLog.Static(64) = .init();
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
    try testing.expect(!log.isSeated());
    try testing.expect(log.isValid());
}

test "unit: clear resets state after writes" {
    var log: PanicLog.Static(64) = .init();
    try log.write("a");
    try log.write("bb");
    PanicLog.Static(64).test_only.forceSeatBusy(&log);
    try testing.expectError(error.WriterBusy, log.write("x"));
    PanicLog.Static(64).test_only.releaseSeat(&log);

    log.clear();
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
    try testing.expect(!log.isSeated());

    var buf: [64]u8 = undefined;
    var sink = fixedSink(&buf);
    var state: PanicLog.DrainState = .init();
    try log.drain(&state, &sink);
    try testing.expectEqualStrings("", sink.buffered());
    try testing.expectEqual(@as(u64, 1), state.next_seq);
}

test "unit: write happy path with sequential payloads" {
    var log: PanicLog.Static(64) = .init();

    try log.write("a");
    try log.write("bb");
    try log.write("ccc");

    try testing.expectEqual(@as(u64, 3), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());

    // Frame 1 at offset 0: len=1, seq_low=1, payload='a'.
    try testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 1, 0, 0, 0, 'a' }, log.bytes[0..9]);
    // Frame 2 at offset 9: len=2, seq_low=2, payload='bb'.
    try testing.expectEqualSlices(u8, &.{ 2, 0, 0, 0, 2, 0, 0, 0, 'b', 'b' }, log.bytes[9..19]);
    // Frame 3 at offset 19: len=3, seq_low=3, payload='ccc'.
    try testing.expectEqualSlices(u8, &.{ 3, 0, 0, 0, 3, 0, 0, 0, 'c', 'c', 'c' }, log.bytes[19..30]);
}

test "unit: write of max_payload_bytes on empty ring succeeds" {
    var log: PanicLog.Static(64) = .init();
    const payload: [56]u8 = [_]u8{'q'} ** 56;
    try log.write(&payload);
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
}

test "unit: write returns EmptyPayload on zero-length input" {
    var log: PanicLog.Static(64) = .init();
    try testing.expectError(error.EmptyPayload, log.write(""));
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
    try testing.expect(!log.isSeated());
}

test "unit: write returns PayloadTooLarge above max_payload_bytes" {
    var log: PanicLog.Static(64) = .init();
    const oversize: [57]u8 = [_]u8{'z'} ** 57;
    try testing.expectError(error.PayloadTooLarge, log.write(&oversize));
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
}

test "unit: write returns WriterBusy when seat is held" {
    const S = PanicLog.Static(64);
    var log: S = .init();

    S.test_only.forceSeatBusy(&log);
    try testing.expectError(error.WriterBusy, log.write("x"));
    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());
    try testing.expect(log.isSeated());

    S.test_only.releaseSeat(&log);
    try log.write("y");
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());
}

// Byte-overflow overwrite-oldest math for `Static(48)`:
//   header_bytes = 8, payload = 4 bytes → frame = 12 bytes.
//   4 × 12 = 48 exact → head=48, tail=0, free=0.
//   5th write needs 12 → evict frame 1 → tail=12 → head advances to 60 → offset 60 % 48 = 12.
//   The 5th frame occupies offsets 48..60 mod 48 (wraps from the tail
//   boundary into the buffer's start), producing exactly one whole-frame drop.
// Spec docs/specs/diag/panic-log.md lines 499-505 example a `Static(32)`
// case with four 4-byte writes dropping frame 1; that combination cannot
// yield dropped==1 under a consistent head/tail model (3rd 12-byte frame
// already forces eviction, so four writes drop 2 frames). The corrected
// Static(48)+5-writes shape here preserves the whole-message eviction
// invariant the spec ultimately requires.
test "unit: byte overflow evicts oldest whole frame" {
    const S = PanicLog.Static(48);
    var log: S = .init();

    try log.write("aaaa");
    try log.write("bbbb");
    try log.write("cccc");
    try log.write("dddd");
    try testing.expectEqual(@as(u64, 0), log.dropped());

    try log.write("eeee");
    try testing.expectEqual(@as(u64, 5), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());

    var buf: [128]u8 = undefined;
    var sink = fixedSink(&buf);
    var state: PanicLog.DrainState = .init();
    try log.drain(&state, &sink);

    // Drop marker + payloads of frames 2..5 (frame 1 was evicted).
    try testing.expectEqualStrings("... 1 messages dropped ...\nbbbbccccddddeeee", sink.buffered());
    try testing.expectEqual(@as(u64, 6), state.next_seq);
    try testing.expectEqual(@as(u64, 1), state.dropped_snapshot);
}

test "unit: drain sequential concatenates payloads without marker" {
    var log: PanicLog.Static(64) = .init();
    try log.write("a");
    try log.write("bb");
    try log.write("ccc");

    var buf: [64]u8 = undefined;
    var sink = fixedSink(&buf);
    var state: PanicLog.DrainState = .init();
    try log.drain(&state, &sink);
    try testing.expectEqualStrings("abbccc", sink.buffered());
    try testing.expectEqual(@as(u64, 4), state.next_seq);
    try testing.expectEqual(@as(u64, 0), state.dropped_snapshot);

    // Second drain with no new writes emits nothing.
    var buf2: [64]u8 = undefined;
    var sink2 = fixedSink(&buf2);
    try log.drain(&state, &sink2);
    try testing.expectEqualStrings("", sink2.buffered());
    try testing.expectEqual(@as(u64, 4), state.next_seq);
}

test "unit: drain reports N drops from seat contention" {
    const S = PanicLog.Static(64);
    var log: S = .init();

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        S.test_only.forceSeatBusy(&log);
        try testing.expectError(error.WriterBusy, log.write("x"));
        S.test_only.releaseSeat(&log);
    }
    try log.write("ok");
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 5), log.dropped());

    var buf: [64]u8 = undefined;
    var sink = fixedSink(&buf);
    var state: PanicLog.DrainState = .init();
    try log.drain(&state, &sink);
    try testing.expectEqualStrings("... 5 messages dropped ...\nok", sink.buffered());
    try testing.expectEqual(@as(u64, 5), state.dropped_snapshot);
    try testing.expectEqual(@as(u64, 2), state.next_seq);
}

// A synthetic mid-drain overwrite: prime the log with one message,
// begin draining, then simulate the writer overwriting a frame by
// bumping `dropped_seq` before the next drain outer iteration.
// The reader must observe the delta, emit the marker, and resync.
test "unit: drain resyncs on mid-drain overwrite" {
    const S = PanicLog.Static(64);
    var log: S = .init();

    try log.write("first");
    try log.write("second");
    try testing.expectEqual(@as(u64, 2), log.published());

    var state: PanicLog.DrainState = .init();

    // First drain observes "first" + "second" cleanly.
    var buf: [64]u8 = undefined;
    var sink = fixedSink(&buf);
    try log.drain(&state, &sink);
    try testing.expectEqualStrings("firstsecond", sink.buffered());
    try testing.expectEqual(@as(u64, 3), state.next_seq);
    try testing.expectEqual(@as(u64, 0), state.dropped_snapshot);

    // Synthetic mid-drain race: bump dropped_seq (as an overwrite would),
    // then land another real write. Reader must detect the delta, emit
    // the marker, and resync next_seq to `oldestSurvivingSeq`.
    S.test_only.bumpDroppedSeq(&log);
    try log.write("third");

    var buf2: [64]u8 = undefined;
    var sink2 = fixedSink(&buf2);
    try log.drain(&state, &sink2);
    // Spec §Reader step 3: on any drop delta the reader resets
    // `next_seq` to `oldestSurvivingSeq`. Because `tail` never
    // advanced (the bump was synthetic, no real eviction), the oldest
    // surviving seq is still 1 and the reader replays frames 1..3
    // after the marker.
    try testing.expectEqualStrings("... 1 messages dropped ...\nfirstsecondthird", sink2.buffered());
    try testing.expectEqual(@as(u64, 1), state.dropped_snapshot);
    try testing.expectEqual(@as(u64, 4), state.next_seq);
}

test "unit: seat CAS excludes contended writers until release" {
    const S = PanicLog.Static(64);
    var log: S = .init();

    // Writer A "in progress": force seat busy.
    S.test_only.forceSeatBusy(&log);
    try testing.expect(log.isSeated());

    // Writer B observes seat held → drops.
    try testing.expectError(error.WriterBusy, log.write("b"));
    try testing.expectEqual(@as(u64, 1), log.dropped());

    // Writer A completes → seat freed.
    S.test_only.releaseSeat(&log);
    try testing.expect(!log.isSeated());

    // Writer B's next write succeeds now.
    try log.write("b");
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());
}

test "unit: NMI-preemption model — nested writer drops while A holds seat" {
    // Simulate CPU state: writer A took the seat and was preempted by an
    // NMI. Writer B (the NMI handler) attempts a write; single-attempt
    // CAS fails, one drop accounted. A then completes cleanly. Drain
    // emits A's payload only, and dropped() reflects B's drop.
    const S = PanicLog.Static(64);
    var log: S = .init();

    // A acquires the seat (simulated).
    S.test_only.forceSeatBusy(&log);

    // Nested B tries to write → drops.
    try testing.expectError(error.WriterBusy, log.write("nmi"));
    try testing.expectEqual(@as(u64, 1), log.dropped());

    // A completes by releasing the seat, then publishes its payload.
    S.test_only.releaseSeat(&log);
    try log.write("apayload");

    var buf: [64]u8 = undefined;
    var sink = fixedSink(&buf);
    var state: PanicLog.DrainState = .init();
    try log.drain(&state, &sink);
    try testing.expectEqualStrings("... 1 messages dropped ...\napayload", sink.buffered());
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());
}

test "unit: counter queries reflect writer state accurately" {
    const S = PanicLog.Static(64);
    var log: S = .init();

    try testing.expectEqual(@as(u64, 0), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());
    try testing.expect(!log.isSeated());

    try log.write("one");
    try testing.expectEqual(@as(u64, 1), log.published());
    try testing.expectEqual(@as(u64, 0), log.dropped());

    S.test_only.forceSeatBusy(&log);
    try testing.expect(log.isSeated());
    try testing.expectError(error.WriterBusy, log.write("two"));
    try testing.expectEqual(@as(u64, 1), log.dropped());
    S.test_only.releaseSeat(&log);
    try testing.expect(!log.isSeated());

    try log.write("two");
    try testing.expectEqual(@as(u64, 2), log.published());
    try testing.expectEqual(@as(u64, 1), log.dropped());
}

test "unit: assertValid holds through 100 writes and 10 drains" {
    var log: PanicLog.Static(256) = .init();
    log.assertValid();

    var buf: [512]u8 = undefined;
    var state: PanicLog.DrainState = .init();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, @intCast(i), .little);
        try log.write(&payload);
        log.assertValid();

        if (i % 10 == 9) {
            var sink = fixedSink(&buf);
            try log.drain(&state, &sink);
            log.assertValid();
        }
    }

    try testing.expect(log.isValid());
}

test "unit: isValid rejects corrupt head and dropped_seq" {
    const S = PanicLog.Static(64);
    var log: S = .init();
    try log.write("a");
    try testing.expect(log.isValid());

    // head beyond capacity_bytes is structurally invalid.
    S.test_only.corruptHead(&log, 64 + 1);
    try testing.expect(!log.isValid());

    // Restore then corrupt dropped_seq > seq.
    log.clear();
    try log.write("b");
    try testing.expect(log.isValid());
    S.test_only.corruptDroppedSeq(&log, log.published() + 1);
    try testing.expect(!log.isValid());
}

test "stress: two writer threads plus periodic drain preserve write-outcome invariant" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const S = PanicLog.Static(512);
    const per_thread: usize = 1_000;
    const total: usize = per_thread * 2;

    var log: S = .init();
    var writer_busy = std.atomic.Value(u64).init(0);

    const Ctx = struct {
        log: *S,
        writer_busy: *std.atomic.Value(u64),
        iters: usize,

        fn run(ctx: @This()) void {
            var i: usize = 0;
            while (i < ctx.iters) : (i += 1) {
                const payload: [4]u8 = .{ 'x', 'y', 'z', 'w' };
                if (ctx.log.write(&payload)) |_| {} else |err| switch (err) {
                    error.WriterBusy => _ = ctx.writer_busy.fetchAdd(1, .monotonic),
                    error.EmptyPayload, error.PayloadTooLarge => unreachable,
                }
            }
        }
    };

    const ctx = Ctx{ .log = &log, .writer_busy = &writer_busy, .iters = per_thread };
    var t0 = try std.Thread.spawn(.{}, Ctx.run, .{ctx});
    var t1 = try std.Thread.spawn(.{}, Ctx.run, .{ctx});

    // Occasionally drain to demonstrate the reader tolerates a live writer;
    // the sink is a fixed buffer that may fill (WriteFailed), which is fine —
    // ignoring writer errors here isolates the invariant under test.
    var buf: [512]u8 = undefined;
    var state: PanicLog.DrainState = .init();
    var polls: usize = 0;
    while (polls < 16) : (polls += 1) {
        var sink = fixedSink(&buf);
        log.drain(&state, &sink) catch {};
        std.Thread.yield() catch {};
    }

    t0.join();
    t1.join();

    // Every write attempt is either a successful publish or an
    // `error.WriterBusy` return; overflow evictions bump `dropped_seq`
    // internally to a successful write and are not counted here per spec
    // §Writer semantics (docs/specs/diag/panic-log.md:213-214, 232-234).
    const busy = writer_busy.load(.monotonic);
    try testing.expectEqual(@as(u64, total), log.published() + busy);
    // `dropped()` combines busy drops and overflow evictions; it must be
    // at least the busy count observed by the writers.
    try testing.expect(log.dropped() >= busy);
}
