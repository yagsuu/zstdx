const std = @import("std");

const Atomic = std.atomic.Value;
const Writer = std.Io.Writer;

pub const EventLog = struct {
    pub const Cursor = struct {
        next: ?u64 = null,
        drops: u64 = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }
    };

    pub fn Static(comptime cap: usize) type {
        if (cap < 2 * Header.size or cap > std.math.maxInt(u32)) {
            @compileError("EventLog.Static requires capacity between 16 and maxInt(u32)");
        }

        return struct {
            bytes: [cap]u8 = @splat(0),
            locked: Atomic(bool) = .init(false),
            head: usize = 0,
            tail: usize = 0,
            used: usize = 0,
            sequence: Atomic(u64) = .init(0),
            drops: Atomic(u64) = .init(0),

            pub const capacity: usize = cap;
            pub const max_payload: usize = cap - Header.size;

            const Self = @This();

            pub const Error = Impl.Error;
            pub const DrainError = Impl.DrainError;

            pub fn init() Self {
                return .{};
            }

            /// requires exclusive access; reset all reader cursors after clearing.
            pub fn clear(self: *Self) void {
                std.debug.assert(!self.locked.load(.monotonic));

                self.head = 0;
                self.tail = 0;
                self.used = 0;

                self.sequence.store(0, .monotonic);
                self.drops.store(0, .monotonic);

                @memset(&self.bytes, 0);
            }

            /// wait free: the event is dropped on contention.
            /// oldest events are evicted when the available capacity is exhausted.
            pub fn write(self: *Self, payload: []const u8) Error!void {
                return Impl.write(self, payload);
            }

            pub fn drain(self: *Self, cursor: *Cursor, sink: *Writer) DrainError!void {
                return Impl.drain(self, cursor, sink);
            }

            pub fn dropped(self: *const Self) u64 {
                return self.drops.load(.monotonic);
            }

            pub fn published(self: *const Self) u64 {
                return self.sequence.load(.acquire);
            }

            pub fn isBusy(self: *const Self) bool {
                return self.locked.load(.monotonic);
            }

            pub fn isValid(self: *const Self) bool {
                return Impl.isValid(self);
            }
        };
    }
};

const Impl = struct {
    const Error = error{ WriterBusy, PayloadTooLarge, EmptyPayload };
    const DrainError = Writer.Error || error{Busy};

    fn write(log: anytype, payload: []const u8) Error!void {
        const capacity = log.bytes.len;

        if (payload.len == 0) {
            return error.EmptyPayload;
        }

        if (payload.len > capacity - Header.size) {
            return error.PayloadTooLarge;
        }

        if (log.locked.cmpxchgStrong(false, true, .acquire, .monotonic) != null) {
            _ = log.drops.fetchAdd(1, .monotonic);
            return error.WriterBusy;
        }

        defer log.locked.store(false, .release);

        const size = Header.size + payload.len;
        while (capacity - log.used < size) {
            const oldest = Header.read(&log.bytes, log.head);
            const evicted = Header.size + @as(usize, oldest.len);

            log.head = advance(log.head, evicted, capacity);
            log.used -= evicted;
            _ = log.drops.fetchAdd(1, .monotonic);
        }

        const sequence = log.sequence.load(.monotonic) +% 1;
        const header: Header = .{ .len = @intCast(payload.len), .sequence = @truncate(sequence) };

        header.write(&log.bytes, log.tail);
        copyIn(&log.bytes, advance(log.tail, Header.size, capacity), payload);

        log.tail = advance(log.tail, size, capacity);
        log.used += size;

        log.sequence.store(sequence, .release);
    }

    fn drain(log: anytype, cursor: *EventLog.Cursor, sink: *Writer) DrainError!void {
        if (log.locked.cmpxchgStrong(false, true, .acquire, .monotonic) != null) {
            return error.Busy;
        }

        defer log.locked.store(false, .release);

        const drops = log.drops.load(.monotonic);
        if (drops != cursor.drops) {
            try sink.print("... {d} messages dropped ...\n", .{drops -% cursor.drops});
            cursor.drops = drops;
        }

        const sequence = log.sequence.load(.monotonic);
        const end = sequence +% 1;

        if (log.used == 0) {
            cursor.next = end;
            return;
        }

        const first = Header.read(&log.bytes, log.head);
        const low: u32 = @truncate(sequence);
        const distance = low -% first.sequence;
        const oldest = sequence -% distance;

        var next = cursor.next orelse oldest;
        if (next != end and next -% oldest > sequence -% oldest) {
            next = oldest;
        }

        cursor.next = next;

        if (next == end) {
            return;
        }

        var offset = log.head;
        var remaining = log.used;
        var current = oldest;

        while (remaining != 0) {
            const header = Header.read(&log.bytes, offset);
            const size = Header.size + @as(usize, header.len);

            if (current == next) {
                try emit(sink, &log.bytes, advance(offset, Header.size, log.bytes.len), header.len);

                next +%= 1;
                cursor.next = next;
            }

            offset = advance(offset, size, log.bytes.len);
            remaining -= size;
            current +%= 1;
        }
    }

    fn isValid(log: anytype) bool {
        const capacity = log.bytes.len;

        if (log.head >= capacity or log.tail >= capacity or log.used > capacity) {
            return false;
        }

        var offset = log.head;
        var remaining = log.used;
        var next: ?u32 = null;

        while (remaining != 0) {
            if (remaining < Header.size) {
                return false;
            }

            const header = Header.read(&log.bytes, offset);
            if (header.len == 0 or header.len > capacity - Header.size) {
                return false;
            }

            const size = Header.size + @as(usize, header.len);
            if (size > remaining) {
                return false;
            }

            if (next) |expected| {
                if (header.sequence != expected) {
                    return false;
                }
            }

            next = header.sequence +% 1;
            offset = advance(offset, size, capacity);
            remaining -= size;
        }

        if (offset != log.tail) {
            return false;
        }

        if (next) |expected| {
            return expected -% 1 == @as(u32, @truncate(log.sequence.load(.monotonic)));
        }

        return true;
    }

    fn advance(offset: usize, amount: usize, capacity: usize) usize {
        const remaining = capacity - offset;

        if (amount >= remaining) {
            return amount - remaining;
        }

        return offset + amount;
    }

    fn copyIn(bytes: []u8, offset: usize, source: []const u8) void {
        const first = @min(source.len, bytes.len - offset);

        @memcpy(bytes[offset..][0..first], source[0..first]);
        @memcpy(bytes[0 .. source.len - first], source[first..]);
    }

    fn copyOut(bytes: []const u8, offset: usize, destination: []u8) void {
        const first = @min(destination.len, bytes.len - offset);

        @memcpy(destination[0..first], bytes[offset..][0..first]);
        @memcpy(destination[first..], bytes[0 .. destination.len - first]);
    }

    fn emit(sink: *Writer, bytes: []const u8, offset: usize, length: usize) Writer.Error!void {
        const first = @min(length, bytes.len - offset);

        try sink.writeAll(bytes[offset..][0..first]);

        if (first < length) {
            try sink.writeAll(bytes[0 .. length - first]);
        }
    }
};

const Header = packed struct(u64) {
    len: u32,
    sequence: u32,

    const size = @sizeOf(Self);

    const Self = @This();

    fn read(bytes: []const u8, offset: usize) Self {
        var buffer: [size]u8 = undefined;

        Impl.copyOut(bytes, offset, &buffer);

        return @bitCast(std.mem.readInt(u64, &buffer, .little));
    }

    fn write(self: Self, bytes: []u8, offset: usize) void {
        var buffer: [size]u8 = undefined;

        std.mem.writeInt(u64, &buffer, @bitCast(self), .little);
        Impl.copyIn(bytes, offset, &buffer);
    }
};

pub const unit = struct {
    const testing = std.testing;

    const ReentrantSink = struct {
        log: *EventLog.Static(64),
        cursor: *EventLog.Cursor,
        output: *Writer,
        write_error: ?EventLog.Static(64).Error = null,
        drain_error: ?EventLog.Static(64).DrainError = null,
        writer: Writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} },

        const Self = @This();

        fn drain(writer: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
            const self: *Self = @alignCast(@fieldParentPtr("writer", writer));

            self.log.write("nested") catch |err| {
                self.write_error = err;
            };

            self.log.drain(self.cursor, self.output) catch |err| {
                self.drain_error = err;
            };

            return self.output.writeSplat(data, splat);
        }
    };

    test "payload boundaries and clear preserve usable storage" {
        var log: EventLog.Static(16) = .init();
        var cursor: EventLog.Cursor = .init();

        try testing.expectError(error.EmptyPayload, log.write(""));
        try testing.expectError(error.PayloadTooLarge, log.write("123456789"));
        try log.write("12345678");

        var buffer: [64]u8 = undefined;
        var sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("12345678", sink.buffered());
        try testing.expectEqual(@as(u64, 1), log.published());
        try testing.expect(log.isValid());

        log.clear();
        cursor = .init();
        try log.write("new");
        sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("new", sink.buffered());
        try testing.expectEqual(@as(u64, 0), log.dropped());
    }

    test "non-power-of-two storage wraps headers and evicts whole events" {
        var log: EventLog.Static(31) = .init();
        var cursor: EventLog.Cursor = .init();

        try log.write("aaaa");
        try log.write("bbbb");
        try log.write("cccc");

        var buffer: [128]u8 = undefined;
        var sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("... 1 messages dropped ...\nbbbbcccc", sink.buffered());
        try testing.expect(log.isValid());

        try log.write("dddd");
        sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("... 1 messages dropped ...\ndddd", sink.buffered());
        try testing.expectEqual(@as(u64, 4), log.published());
        try testing.expect(log.isValid());
    }

    test "busy drops do not invalidate storage or replay drained events" {
        var log: EventLog.Static(64) = .init();
        var cursor: EventLog.Cursor = .init();

        log.locked.store(true, .monotonic);

        for (0..5) |_| {
            try testing.expectError(error.WriterBusy, log.write("busy"));
        }

        log.locked.store(false, .monotonic);

        try testing.expect(log.isValid());
        try testing.expectEqual(@as(u64, 0), log.published());
        try testing.expectEqual(@as(u64, 5), log.dropped());

        try log.write("first");
        var buffer: [128]u8 = undefined;
        var sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("... 5 messages dropped ...\nfirst", sink.buffered());

        log.locked.store(true, .monotonic);
        try testing.expectError(error.WriterBusy, log.write("busy"));
        log.locked.store(false, .monotonic);

        try log.write("second");
        sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("... 1 messages dropped ...\nsecond", sink.buffered());
    }

    test "sink failure preserves the pending event and releases ownership" {
        var log: EventLog.Static(64) = .init();
        var cursor: EventLog.Cursor = .init();

        try log.write("first");
        try log.write("second");

        var short: [7]u8 = undefined;
        var failing = Writer.fixed(&short);

        try testing.expectError(error.WriteFailed, log.drain(&cursor, &failing));

        try testing.expectEqualStrings("firstse", failing.buffered());
        try testing.expectEqual(@as(?u64, 2), cursor.next);
        try testing.expect(!log.isBusy());

        var buffer: [32]u8 = undefined;
        var sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("second", sink.buffered());
    }

    test "sink reentrancy cannot overwrite bytes or recursively drain" {
        var log: EventLog.Static(64) = .init();
        var cursor: EventLog.Cursor = .init();

        try log.write("payload");

        var buffer: [128]u8 = undefined;
        var output = Writer.fixed(&buffer);
        var sink: ReentrantSink = .{ .log = &log, .cursor = &cursor, .output = &output };

        try log.drain(&cursor, &sink.writer);

        try testing.expectEqualStrings("payload", output.buffered());
        try testing.expectEqual(error.WriterBusy, sink.write_error.?);
        try testing.expectEqual(error.Busy, sink.drain_error.?);
        try testing.expectEqual(@as(u64, 1), log.dropped());
        try testing.expect(log.isValid());

        output = Writer.fixed(&buffer);
        try log.drain(&cursor, &output);

        try testing.expectEqualStrings("... 1 messages dropped ...\n", output.buffered());
    }

    test "publication and drop counters wrap without losing pending events" {
        var log: EventLog.Static(64) = .init();
        var cursor: EventLog.Cursor = .init();

        log.sequence.store(std.math.maxInt(u64) - 1, .monotonic);
        log.drops.store(std.math.maxInt(u64), .monotonic);
        cursor.drops = std.math.maxInt(u64);

        log.locked.store(true, .monotonic);
        try testing.expectError(error.WriterBusy, log.write("busy"));
        log.locked.store(false, .monotonic);

        try log.write("last");
        try log.write("zero");

        var buffer: [128]u8 = undefined;
        var sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("... 1 messages dropped ...\nlastzero", sink.buffered());
        try testing.expectEqual(@as(u64, 0), log.published());
        try testing.expectEqual(@as(u64, 0), log.dropped());
        try testing.expect(log.isValid());

        try log.write("next");
        sink = Writer.fixed(&buffer);
        try log.drain(&cursor, &sink);

        try testing.expectEqualStrings("next", sink.buffered());
    }
};
