//! Panic-safe ring log sink. See `docs/specs/diag/panic-log.md`.

const std = @import("std");
const builtin = @import("builtin");

const debug = @import("../core/debug.zig");
const cache = @import("../mem/cache.zig");
const endian = @import("../layout/endian.zig");

const CachePad = cache.CachePad;
const Le = endian.Le;

/// Panic-safe ring log sink family. `Static(capacity_bytes)` is the
/// inline-storage variant; `DrainState` carries the reader's
/// resume/resync cursor.
pub const PanicLog = struct {
    /// Inline byte storage plus atomic counters. `capacity_bytes`
    /// must be at least `2 * header_bytes` and at most
    /// `std.math.maxInt(u32)` — offsets in the on-wire header are
    /// `u32` little-endian.
    pub fn Static(comptime capacity_bytes: usize) type {
        if (capacity_bytes < 2 * 8) {
            @compileError("PanicLog.Static: capacity_bytes must be >= 2 * header_bytes (16)");
        }

        if (capacity_bytes > std.math.maxInt(u32)) {
            @compileError("PanicLog.Static: capacity_bytes exceeds the u32 offset-format limit (maxInt(u32))");
        }

        return struct {
            bytes: [capacity_bytes]u8 = [_]u8{0} ** capacity_bytes,
            head: CachePad(std.atomic.Value(usize)) =
                .{ .value = std.atomic.Value(usize).init(0) },
            tail: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
            seat: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
            seq: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
            dropped_seq: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

            const Self = @This();

            /// `WriterBusy` means that seat acquisition lost to a concurrent writer; the drop is already counted.
            /// `PayloadTooLarge` means that `payload.len` exceeds `max_payload_bytes`.
            /// `EmptyPayload` means that a zero-length write is invalid.
            pub const Error = error{
                WriterBusy,
                PayloadTooLarge,
                EmptyPayload,
            };

            /// Fixed 8-byte on-wire header: `[u32 len][u32 seq_low]`,
            /// both little-endian.
            pub const header_bytes: usize = 8;

            /// Comptime capacity in bytes (equals the `Static` factory argument).
            pub const capacity_bytes_const: usize = capacity_bytes;

            /// Largest payload accepted by `write`.
            pub const max_payload_bytes: usize = capacity_bytes - header_bytes;

            /// Initializes all fields without allocation.
            pub fn init() Self {
                return .{};
            }

            /// Resets counters and zeros the byte storage only when no writer holds
            /// the seat and no reader is mid-drain.
            pub fn clear(self: *Self) void {
                if (comptime debug.checksEnabled(.build_mode)) {
                    std.debug.assert(self.seat.load(.acquire) == 0);
                }

                self.head.value.store(0, .monotonic);
                self.tail.store(0, .monotonic);
                self.seat.store(0, .monotonic);
                self.seq.store(0, .monotonic);
                self.dropped_seq.store(0, .monotonic);
                @memset(&self.bytes, 0);
            }

            /// Publishes `payload` as a single frame. NMI-safe: a
            /// preempted or contending writer returns
            /// `error.WriterBusy` and bumps `dropped_seq`. On success,
            /// the ring reserves oldest-first bytes as needed via
            /// whole-frame eviction, each eviction bumping
            /// `dropped_seq` by one.
            pub fn write(self: *Self, payload: []const u8) Error!void {
                if (payload.len == 0) return error.EmptyPayload;
                if (payload.len > max_payload_bytes) return error.PayloadTooLarge;

                // Ordering: Pairs with the release store to `seat` at the end of `write`.
                if (self.seat.cmpxchgStrong(0, 1, .acquire, .monotonic) != null) {
                    // Ordering: Publishes the drop count to the acquire load of `dropped_seq` in `drain`.
                    _ = self.dropped_seq.fetchAdd(1, .release);
                    return error.WriterBusy;
                }

                const needed: usize = header_bytes + payload.len;
                var head_val = self.head.value.load(.monotonic);
                var tail_val = self.tail.load(.monotonic);

                while (capacity_bytes - (head_val - tail_val) < needed) {
                    const tail_off = tail_val % capacity_bytes;
                    const flen: usize = readU32Wrap(&self.bytes, tail_off, capacity_bytes);
                    tail_val += header_bytes + flen;
                    self.tail.store(tail_val, .release);
                    // Ordering: Publishes the drop count to the acquire load of `dropped_seq` in `drain`.
                    _ = self.dropped_seq.fetchAdd(1, .release);
                }

                const new_seq: u64 = self.seq.load(.monotonic) + 1;
                const head_off = head_val % capacity_bytes;
                const len_u32: u32 = @intCast(payload.len);
                const seq_low: u32 = @truncate(new_seq);

                writeHeader(&self.bytes, head_off, len_u32, seq_low, capacity_bytes);
                copyInWrap(&self.bytes, (head_off + header_bytes) % capacity_bytes, payload, capacity_bytes);

                head_val += needed;
                // Ordering: Publishes the header and payload bytes to the acquire load of `head` in `drain`.
                self.head.value.store(head_val, .release);
                // Ordering: Publishes the new sequence value to the acquire load of `seq` in `drain`.
                self.seq.store(new_seq, .release);
                // Ordering: Publishes the header and payload writes to the next `seat` CAS.
                self.seat.store(0, .release);
            }

            /// Drain published messages to `sink`. Emits payload bytes
            /// only, no headers; a drop delta emits a single
            /// `... N messages dropped ...\n` line and resyncs
            /// `reader_state.next_seq` to the oldest surviving frame.
            pub fn drain(
                self: *Self,
                reader_state: *DrainState,
                sink: *std.Io.Writer,
            ) std.Io.Writer.Error!void {
                var cursor: usize = 0;
                var cursor_ready = false;

                while (true) {
                    // Ordering: Pairs with the release store to `seq` in `write`.
                    const seq_now = self.seq.load(.acquire);
                    // Ordering: Pairs with the release operation on `dropped_seq` in `write`.
                    const dropped_now = self.dropped_seq.load(.acquire);

                    if (dropped_now != reader_state.dropped_snapshot) {
                        const delta = dropped_now - reader_state.dropped_snapshot;
                        try sink.print("... {} messages dropped ...\n", .{delta});
                        reader_state.dropped_snapshot = dropped_now;
                        reader_state.next_seq = self.oldestSurvivingSeq();
                        cursor_ready = false;
                        continue;
                    }

                    if (reader_state.next_seq > seq_now) return;

                    // Ordering: Pairs with the release store to `head` in `write`.
                    const head_now = self.head.value.load(.acquire);
                    const tail_now = self.tail.load(.acquire);

                    if (!cursor_ready) {
                        var walk_cursor = tail_now;
                        var walk_seq = self.oldestSurvivingSeq();
                        while (walk_seq < reader_state.next_seq and walk_cursor < head_now) : (walk_seq += 1) {
                            const flen: usize = readU32Wrap(&self.bytes, walk_cursor % capacity_bytes, capacity_bytes);
                            if (flen > max_payload_bytes) {
                                cursor_ready = false;
                                break;
                            }
                            walk_cursor += header_bytes + flen;
                        } else {
                            cursor = walk_cursor;
                            cursor_ready = true;
                        }

                        if (!cursor_ready) continue;
                    }

                    if (cursor + header_bytes > head_now) {
                        cursor_ready = false;
                        continue;
                    }

                    const cursor_off = cursor % capacity_bytes;
                    const frame_len_val: usize = readU32Wrap(&self.bytes, cursor_off, capacity_bytes);
                    if (frame_len_val == 0 or frame_len_val > max_payload_bytes) {
                        cursor_ready = false;
                        continue;
                    }

                    if (cursor + header_bytes + frame_len_val > head_now) {
                        cursor_ready = false;
                        continue;
                    }

                    const payload_off = (cursor_off + header_bytes) % capacity_bytes;
                    try emitWrap(sink, &self.bytes, payload_off, frame_len_val, capacity_bytes);

                    if (self.dropped_seq.load(.acquire) != reader_state.dropped_snapshot) {
                        cursor_ready = false;
                        continue;
                    }

                    cursor += header_bytes + frame_len_val;
                    reader_state.next_seq += 1;
                }
            }

            /// Monotonic drop counter. Includes both `WriterBusy`
            /// drops and whole-frame overwrites.
            pub fn dropped(self: *const Self) u64 {
                return self.dropped_seq.load(.acquire);
            }

            /// Monotonic publication counter. Increases by 1 per
            /// successful `write`.
            pub fn published(self: *const Self) u64 {
                return self.seq.load(.acquire);
            }

            /// True while a writer holds the seat.
            pub fn isSeated(self: *const Self) bool {
                return self.seat.load(.acquire) == 1;
            }

            /// Checks structural validity when the caller has exclusive ownership.
            /// This method is not race-safe against a running writer.
            pub fn isValid(self: *const Self) bool {
                const head_val = self.head.value.load(.acquire);
                const tail_val = self.tail.load(.acquire);
                const seat_val = self.seat.load(.acquire);
                const seq_val = self.seq.load(.acquire);
                const dropped_val = self.dropped_seq.load(.acquire);

                if (tail_val > head_val) return false;
                if (head_val - tail_val > capacity_bytes) return false;
                if (seat_val > 1) return false;
                if (dropped_val > seq_val) return false;

                if (seat_val == 0) {
                    var pos: usize = tail_val;
                    while (pos < head_val) {
                        const remaining = head_val - pos;
                        if (remaining < header_bytes) return false;
                        const flen: usize = readU32Wrap(&self.bytes, pos % capacity_bytes, capacity_bytes);
                        pos += header_bytes + flen;
                        if (pos > head_val) return false;
                    }
                    if (pos != head_val) return false;
                }

                return true;
            }

            /// Assert structural validity; invalid state is programmer error.
            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }

            /// Reconstruct the 64-bit sequence of the frame at
            /// `tail` from the frame's stored `seq_low` and the high
            /// bits of the current `seq` snapshot. Correct while the
            /// ring holds fewer than 2^32 in-flight messages, which
            /// is enforced by `capacity_bytes <= maxInt(u32)`.
            fn oldestSurvivingSeq(self: *const Self) u64 {
                const seq_now = self.seq.load(.acquire);
                if (seq_now == 0) return 1;

                const tail_val = self.tail.load(.acquire);
                if (tail_val == self.head.value.load(.acquire)) return seq_now + 1;

                const seq_low: u64 = readU32Wrap(&self.bytes, (tail_val + 4) % capacity_bytes, capacity_bytes);
                const high = seq_now & (~@as(u64, std.math.maxInt(u32)));
                var candidate: u64 = high | seq_low;
                if (candidate > seq_now) {
                    candidate -%= @as(u64, 1) << 32;
                }

                return candidate;
            }

            /// Test-only mutation hooks are available only when `builtin.is_test` is true.
            /// They can force a stuck seat or a synthetic drop.
            pub const test_only = if (builtin.is_test) struct {
                pub fn forceSeatBusy(self: *Self) void {
                    self.seat.store(1, .release);
                }

                pub fn releaseSeat(self: *Self) void {
                    self.seat.store(0, .release);
                }

                pub fn bumpDroppedSeq(self: *Self) void {
                    _ = self.dropped_seq.fetchAdd(1, .release);
                }

                pub fn corruptHead(self: *Self, new_head: usize) void {
                    self.head.value.store(new_head, .monotonic);
                }

                pub fn corruptDroppedSeq(self: *Self, new_dropped: u64) void {
                    self.dropped_seq.store(new_dropped, .monotonic);
                }
            } else struct {};
        };
    }

    /// Reader cursor. `next_seq` names the next sequence to emit;
    /// `dropped_snapshot` tracks the last observed drop counter.
    pub const DrainState = struct {
        next_seq: u64 = 1,
        dropped_snapshot: u64 = 0,

        pub fn init() DrainState {
            return .{};
        }
    };
};

fn readU32Wrap(bytes_ptr: []const u8, offset: usize, comptime capacity_bytes: usize) u32 {
    if (offset + 4 <= capacity_bytes) {
        var buf: [4]u8 = undefined;
        @memcpy(&buf, bytes_ptr[offset..][0..4]);
        const wrapper: Le(u32) = .{ .bytes = buf };
        return wrapper.native();
    }

    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        buf[i] = bytes_ptr[(offset + i) % capacity_bytes];
    }

    const wrapper: Le(u32) = .{ .bytes = buf };
    return wrapper.native();
}

fn writeHeader(
    bytes_ptr: []u8,
    head_off: usize,
    len_u32: u32,
    seq_low: u32,
    comptime capacity_bytes: usize,
) void {
    const len_bytes = Le(u32).fromNative(len_u32).bytes;
    const seq_bytes = Le(u32).fromNative(seq_low).bytes;
    if (head_off + 8 <= capacity_bytes) {
        @memcpy(bytes_ptr[head_off..][0..4], &len_bytes);
        @memcpy(bytes_ptr[head_off + 4 ..][0..4], &seq_bytes);
        return;
    }

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        bytes_ptr[(head_off + i) % capacity_bytes] = len_bytes[i];
    }

    i = 0;
    while (i < 4) : (i += 1) {
        bytes_ptr[(head_off + 4 + i) % capacity_bytes] = seq_bytes[i];
    }
}

fn copyInWrap(
    bytes_ptr: []u8,
    start_off: usize,
    payload: []const u8,
    comptime capacity_bytes: usize,
) void {
    if (payload.len == 0) return;

    const first_span = @min(payload.len, capacity_bytes - start_off);
    @memcpy(bytes_ptr[start_off..][0..first_span], payload[0..first_span]);

    if (first_span < payload.len) {
        const remainder = payload.len - first_span;
        @memcpy(bytes_ptr[0..remainder], payload[first_span..]);
    }
}

fn emitWrap(
    sink: *std.Io.Writer,
    bytes_ptr: []const u8,
    start_off: usize,
    length: usize,
    comptime capacity_bytes: usize,
) std.Io.Writer.Error!void {
    if (length == 0) return;

    const first_span = @min(length, capacity_bytes - start_off);
    try sink.writeAll(bytes_ptr[start_off..][0..first_span]);

    if (first_span < length) {
        const remainder = length - first_span;
        try sink.writeAll(bytes_ptr[0..remainder]);
    }
}
