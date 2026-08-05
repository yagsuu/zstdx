//! TimerWheel behavioral tests. See `docs/specs/time/timer_wheel.md`.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;
const Instant = stdx.time.Instant;
const Deadline = stdx.time.Deadline;
const TimerWheel = stdx.time.TimerWheel;

const test_config = TimerWheel.Config{
    .tick_ns = 10,
    .slot_count = 8,
};

fn instant(ns: u64) Instant {
    return Instant.fromNanos(ns);
}

fn deadline(ns: u64) Deadline {
    return Deadline.at(instant(ns));
}

fn TestWheel(comptime T: type, comptime capacity: usize) type {
    return TimerWheel.Static(T, capacity, test_config);
}

fn expectState(comptime Wheel: type, wheel: *const Wheel, len: usize, capacity: usize) !void {
    try testing.expectEqual(len, wheel.len());
    try testing.expectEqual(capacity, wheel.capacity());
    try testing.expectEqual(capacity - len, wheel.remaining());
    try testing.expectEqual(len == 0, wheel.isEmpty());
    try testing.expectEqual(len == capacity, wheel.isFull());
    wheel.assertValid();
}

fn expectNextWake(wake: ?Instant, expected_ns: ?u64) !void {
    if (expected_ns) |ns| {
        try testing.expect(wake != null);
        try testing.expectEqual(ns, wake.?.nanos());
    } else {
        try testing.expect(wake == null);
    }
}

fn itemBit(item: u8) u64 {
    return @as(u64, 1) << @as(u6, @intCast(item));
}

fn drainMask(comptime Wheel: type, wheel: *Wheel) u64 {
    var mask: u64 = 0;
    while (wheel.popExpired()) |entry| {
        const bit = itemBit(entry.item);
        testing.expectEqual(@as(u64, 0), mask & bit) catch unreachable;
        mask |= bit;
        wheel.assertValid();
    }
    return mask;
}

fn expectDrained(comptime Wheel: type, wheel: *Wheel, expected_mask: u64) !void {
    try testing.expectEqual(expected_mask, drainMask(Wheel, wheel));
    try testing.expect(wheel.popExpired() == null);
    wheel.assertValid();
}

test "contract: TimerWheel is exported only from stdx.time" {
    try testing.expect(@hasDecl(stdx.time, "TimerWheel"));
    try testing.expect(!@hasDecl(stdx, "TimerWheel"));
}

test "contract: valid config exposes strong handle and associated constants" {
    const Wheel = TimerWheel.Static(u8, 3, .{ .tick_ns = 1, .slot_count = 2 });
    const Bounded = TimerWheel.Bounded(u8, .{ .tick_ns = 1, .slot_count = 2 });

    switch (@typeInfo(Wheel.Handle)) {
        .@"enum" => |info| try testing.expect(info.tag_type == u128),
        else => try testing.expect(false),
    }
    switch (@typeInfo(Bounded.Handle)) {
        .@"enum" => |info| try testing.expect(info.tag_type == u128),
        else => try testing.expect(false),
    }
    try testing.expectEqual(@as(usize, 3), Wheel.item_capacity);
    try testing.expectEqual(@as(u64, 1), Wheel.wheel_config.tick_ns);
    try testing.expectEqual(@as(usize, 2), Wheel.wheel_config.slot_count);
    try testing.expectEqual(@as(u64, 1), Bounded.wheel_config.tick_ns);
    try testing.expectEqual(@as(usize, 2), Bounded.wheel_config.slot_count);
}

test "unit: Static init sets origin cursor and capacity state" {
    const Wheel = TestWheel(u8, 4);
    var wheel = Wheel.init(instant(100));

    try testing.expectEqual(@as(u64, 100), wheel.origin().nanos());
    try testing.expectEqual(@as(u64, 100), wheel.cursor().nanos());
    try expectState(Wheel, &wheel, 0, 4);
}

test "unit: Bounded wrap uses caller slots and matching bucket storage" {
    const Wheel = TimerWheel.Bounded(u8, test_config);
    var slots: [3]Wheel.Slot = undefined;
    var buckets: [test_config.slot_count]Wheel.Bucket = undefined;
    var wheel = Wheel.wrap(&slots, &buckets, instant(50));

    try testing.expectEqual(@as(u64, 50), wheel.origin().nanos());
    try testing.expectEqual(@as(u64, 50), wheel.cursor().nanos());
    try expectState(Wheel, &wheel, 0, 3);
}

test "contract: Bounded bucket mismatch is a debug-trap precondition" {
    // Invalid bucket storage is a debug-trap precondition. This suite exercises
    // the valid shape because std.debug.assert aborts without an expect-panic
    // harness.
    const Wheel = TimerWheel.Bounded(u8, test_config);
    var slots: [1]Wheel.Slot = undefined;
    var buckets: [test_config.slot_count]Wheel.Bucket = undefined;
    var wheel = Wheel.wrap(&slots, &buckets, instant(0));
    wheel.assertValid();
}

test "unit: insert tracks capacity and validates range before full" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(0));

    const h0 = try wheel.insert(deadline(0), 0);
    const h1 = try wheel.insert(deadline(10), 1);
    try testing.expect(wheel.contains(h0));
    try testing.expect(wheel.contains(h1));
    try expectState(Wheel, &wheel, 2, 2);

    try testing.expectError(error.OutOfRange, wheel.insert(Deadline.never, 2));
    try testing.expectError(error.OutOfRange, wheel.insert(deadline(80), 2));
    try testing.expectError(error.Full, wheel.insert(deadline(20), 2));
    try expectState(Wheel, &wheel, 2, 2);
}

test "unit: insertAssumeCapacity succeeds after explicit capacity check" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(0));

    try testing.expect(!wheel.isFull());
    const h = try wheel.insertAssumeCapacity(deadline(10), 7);
    try testing.expect(wheel.contains(h));
    try expectState(Wheel, &wheel, 1, 2);

    try testing.expectError(error.OutOfRange, wheel.insertAssumeCapacity(Deadline.never, 8));
    try expectState(Wheel, &wheel, 1, 2);
}

test "unit: farthest in-horizon tick is accepted and first beyond is rejected" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(100));

    const h = try wheel.insert(deadline(170), 1); // due tick 7, farthest accepted at current tick 0.
    try testing.expect(wheel.contains(h));
    try expectState(Wheel, &wheel, 1, 2);

    try testing.expectError(error.OutOfRange, wheel.insert(deadline(171), 2)); // quantizes to tick 8.
    try testing.expectError(error.OutOfRange, wheel.insert(deadline(180), 2)); // exact tick 8 boundary.
    try testing.expectError(error.OutOfRange, wheel.insert(Deadline.never, 2));
    try expectState(Wheel, &wheel, 1, 2);
}

test "unit: deadline at cursor is immediately expired" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(100));

    const h = try wheel.insert(deadline(100), 3);
    try testing.expect(wheel.contains(h));
    try expectNextWake(wheel.nextWake(), 100);

    const entry = wheel.popExpired().?;
    try testing.expectEqual(@as(u64, 100), entry.deadline.instant().nanos());
    try testing.expectEqual(@as(u8, 3), entry.item);
    try testing.expect(!wheel.contains(h));
    try expectState(Wheel, &wheel, 0, 2);
}

test "unit: quantization rounds up and prevents early expiration" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(100));

    _ = try wheel.insert(deadline(105), 4);
    try expectNextWake(wheel.nextWake(), 110);
    try testing.expect(wheel.popExpired() == null);

    wheel.advanceTo(instant(109));
    try testing.expectEqual(@as(u64, 100), wheel.cursor().nanos());
    try testing.expect(wheel.popExpired() == null);

    wheel.advanceTo(instant(110));
    try testing.expectEqual(@as(u64, 110), wheel.cursor().nanos());
    const entry = wheel.popExpired().?;
    try testing.expectEqual(@as(u64, 105), entry.deadline.instant().nanos());
    try testing.expectEqual(@as(u8, 4), entry.item);
    try testing.expect(wheel.popExpired() == null);
}

test "unit: exact future tick boundary expires at that boundary" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(100));

    _ = try wheel.insert(deadline(120), 5);
    wheel.advanceTo(instant(119));
    try testing.expect(wheel.popExpired() == null);

    wheel.advanceTo(instant(120));
    const entry = wheel.popExpired().?;
    try testing.expectEqual(@as(u64, 120), entry.deadline.instant().nanos());
    try testing.expectEqual(@as(u8, 5), entry.item);
}

test "unit: one nanosecond after tick boundary expires at following tick" {
    const Wheel = TestWheel(u8, 2);
    var wheel = Wheel.init(instant(100));

    _ = try wheel.insert(deadline(121), 6);
    try expectNextWake(wheel.nextWake(), 130);
    wheel.advanceTo(instant(129));
    try testing.expect(wheel.popExpired() == null);
    wheel.advanceTo(instant(130));
    try testing.expectEqual(@as(u8, 6), wheel.popExpired().?.item);
}

test "unit: multiple and large advances expire all skipped due ticks" {
    const Wheel = TestWheel(u8, 4);
    var wheel = Wheel.init(instant(0));

    _ = try wheel.insert(deadline(10), 1);
    _ = try wheel.insert(deadline(25), 2);
    _ = try wheel.insert(deadline(70), 3);

    wheel.advanceTo(instant(30));
    try expectDrained(Wheel, &wheel, itemBit(1) | itemBit(2));
    try expectState(Wheel, &wheel, 1, 4);

    _ = try wheel.insert(deadline(90), 4);
    wheel.advanceTo(instant(200)); // jump is >= slot_count ticks.
    try expectDrained(Wheel, &wheel, itemBit(3) | itemBit(4));
    try expectState(Wheel, &wheel, 0, 4);
}

test "unit: popExpired drains all due entries with unspecified order" {
    const Wheel = TestWheel(u8, 5);
    var wheel = Wheel.init(instant(0));

    const h0 = try wheel.insert(deadline(11), 0);
    const h1 = try wheel.insert(deadline(12), 1);
    const h2 = try wheel.insert(deadline(35), 2);

    wheel.advanceTo(instant(20));
    try expectDrained(Wheel, &wheel, itemBit(0) | itemBit(1));
    try testing.expect(!wheel.contains(h0));
    try testing.expect(!wheel.contains(h1));
    try testing.expect(wheel.contains(h2));
    try expectState(Wheel, &wheel, 1, 5);
}

test "unit: remove handles active expired and stale entries" {
    const Wheel = TestWheel(u8, 4);
    var wheel = Wheel.init(instant(0));

    const active = try wheel.insert(deadline(30), 1);
    const expired = try wheel.insert(deadline(10), 2);

    const active_entry = wheel.remove(active).?;
    try testing.expectEqual(@as(u8, 1), active_entry.item);
    try testing.expect(!wheel.contains(active));
    try testing.expect(wheel.remove(active) == null);

    wheel.advanceTo(instant(10));
    const expired_entry = wheel.remove(expired).?;
    try testing.expectEqual(@as(u8, 2), expired_entry.item);
    try testing.expect(!wheel.contains(expired));
    try testing.expect(wheel.remove(expired) == null);
    try testing.expect(wheel.popExpired() == null);
    try expectState(Wheel, &wheel, 0, 4);
}

test "unit: stale handle cannot mutate a reused slot" {
    const Wheel = TestWheel(u8, 1);
    var wheel = Wheel.init(instant(0));

    const old = try wheel.insert(deadline(10), 1);
    _ = wheel.remove(old).?;
    try testing.expect(!wheel.contains(old));

    const new = try wheel.insert(deadline(20), 2);
    try testing.expect(wheel.contains(new));
    try testing.expect(wheel.remove(old) == null);
    try testing.expect(!try wheel.updateDeadline(old, deadline(0)));
    try testing.expect(wheel.contains(new));

    wheel.advanceTo(instant(20));
    const entry = wheel.popExpired().?;
    try testing.expectEqual(@as(u8, 2), entry.item);
    try testing.expect(!wheel.contains(new));
}

test "unit: updateDeadline moves entries earlier later same and already due" {
    const Wheel = TestWheel(u8, 4);
    var wheel = Wheel.init(instant(0));

    const earlier = try wheel.insert(deadline(50), 1);
    try testing.expect(try wheel.updateDeadline(earlier, deadline(20)));
    try testing.expect(wheel.contains(earlier));
    try expectNextWake(wheel.nextWake(), 20);
    wheel.advanceTo(instant(20));
    try testing.expectEqual(@as(u8, 1), wheel.popExpired().?.item);

    const later = try wheel.insert(deadline(30), 2);
    try testing.expect(try wheel.updateDeadline(later, deadline(60)));
    wheel.advanceTo(instant(59));
    try testing.expect(wheel.popExpired() == null);
    wheel.advanceTo(instant(60));
    try testing.expectEqual(@as(u8, 2), wheel.popExpired().?.item);

    const same = try wheel.insert(deadline(70), 3);
    try testing.expect(try wheel.updateDeadline(same, deadline(70)));
    try testing.expect(wheel.contains(same));

    const due = try wheel.insert(deadline(75), 4);
    try testing.expect(try wheel.updateDeadline(due, deadline(60)));
    try expectNextWake(wheel.nextWake(), 60);
    try expectDrained(Wheel, &wheel, itemBit(4));

    wheel.advanceTo(instant(70));
    try testing.expectEqual(@as(u8, 3), wheel.popExpired().?.item);
}

test "unit: updateDeadline errors and stale updates leave wheel unchanged" {
    const Wheel = TestWheel(u8, 3);
    var wheel = Wheel.init(instant(0));

    const live = try wheel.insert(deadline(30), 1);
    const stale = try wheel.insert(deadline(20), 2);
    _ = wheel.remove(stale).?;

    try testing.expectError(error.OutOfRange, wheel.updateDeadline(live, Deadline.never));
    try testing.expectError(error.OutOfRange, wheel.updateDeadline(live, deadline(80)));
    try testing.expect(!try wheel.updateDeadline(stale, deadline(0)));
    try testing.expect(wheel.contains(live));
    try expectNextWake(wheel.nextWake(), 30);
    try expectState(Wheel, &wheel, 1, 3);

    wheel.advanceTo(instant(30));
    try testing.expectEqual(@as(u8, 1), wheel.popExpired().?.item);
}

test "unit: nextWake reports empty expired quantized and successor buckets" {
    const Wheel = TestWheel(u8, 4);
    var wheel = Wheel.init(instant(0));

    try expectNextWake(wheel.nextWake(), null);

    const early = try wheel.insert(deadline(11), 1);
    const late = try wheel.insert(deadline(35), 2);
    try expectNextWake(wheel.nextWake(), 20);
    try testing.expect(wheel.nextWake().?.nanos() > deadline(11).instant().nanos());
    try testing.expect(wheel.nextWake().?.nanos() - deadline(11).instant().nanos() < test_config.tick_ns);

    wheel.advanceTo(instant(20));
    try expectNextWake(wheel.nextWake(), 20);
    try testing.expectEqual(@as(u8, 1), wheel.popExpired().?.item);
    try testing.expect(!wheel.contains(early));
    try expectNextWake(wheel.nextWake(), 40);

    _ = wheel.remove(late).?;
    try expectNextWake(wheel.nextWake(), null);
}

test "unit: clear empties wheel and retains capacity origin and cursor" {
    const Wheel = TestWheel(u8, 3);
    var wheel = Wheel.init(instant(100));

    const h0 = try wheel.insert(deadline(110), 1);
    const h1 = try wheel.insert(deadline(130), 2);
    wheel.advanceTo(instant(120));
    try testing.expectEqual(@as(u64, 120), wheel.cursor().nanos());

    wheel.clearRetainingCapacity();
    try testing.expectEqual(@as(u64, 100), wheel.origin().nanos());
    try testing.expectEqual(@as(u64, 120), wheel.cursor().nanos());
    try expectState(Wheel, &wheel, 0, 3);
    try testing.expect(!wheel.contains(h0));
    try testing.expect(!wheel.contains(h1));
    try testing.expect(wheel.remove(h0) == null);
    try testing.expect(!try wheel.updateDeadline(h1, deadline(120)));

    const h2 = try wheel.insert(deadline(120), 3);
    try testing.expect(wheel.contains(h2));
    try expectDrained(Wheel, &wheel, itemBit(3));
}

test "unit: void payload inserts removes and pops" {
    const Wheel = TestWheel(void, 2);
    var wheel = Wheel.init(instant(0));

    const active = try wheel.insert(deadline(10), {});
    const removed = wheel.remove(active).?;
    _ = removed.item;
    try testing.expectEqual(@as(u64, 10), removed.deadline.instant().nanos());

    _ = try wheel.insert(deadline(0), {});
    const popped = wheel.popExpired().?;
    _ = popped.item;
    try testing.expectEqual(@as(u64, 0), popped.deadline.instant().nanos());
    try expectState(Wheel, &wheel, 0, 2);
}

test "unit: pointer payload values round-trip through remove and pop" {
    const Wheel = TestWheel(*u32, 2);
    var wheel = Wheel.init(instant(0));
    var a: u32 = 11;
    var b: u32 = 22;

    const ha = try wheel.insert(deadline(20), &a);
    const removed = wheel.remove(ha).?;
    try testing.expect(removed.item == &a);
    try testing.expectEqual(@as(u32, 11), removed.item.*);

    _ = try wheel.insert(deadline(0), &b);
    const popped = wheel.popExpired().?;
    try testing.expect(popped.item == &b);
    try testing.expectEqual(@as(u32, 22), popped.item.*);
}

const Model = struct {
    const capacity = 6;
    const origin_ns = 0;
    const tick_ns = test_config.tick_ns;
    const slot_count = test_config.slot_count;

    const Entry = struct {
        live: bool = false,
        deadline_ns: u64 = 0,
        due_tick: u64 = 0,
        item: u8 = 0,
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    current_tick: u64 = 0,
    len: usize = 0,

    fn cursorNs(self: *const Model) u64 {
        return origin_ns + self.current_tick * tick_ns;
    }

    fn quantize(self: *const Model, ns: u64) error{OutOfRange}!u64 {
        const due_tick = if (ns <= self.cursorNs())
            self.current_tick
        else
            @divFloor(ns - origin_ns + tick_ns - 1, tick_ns);

        if (due_tick < self.current_tick or due_tick >= self.current_tick + slot_count) {
            return error.OutOfRange;
        }
        return due_tick;
    }

    fn insert(self: *Model, id: usize, ns: u64, item: u8) error{OutOfRange}!void {
        const due_tick = try self.quantize(ns);
        testing.expect(!self.entries[id].live) catch unreachable;
        self.entries[id] = .{
            .live = true,
            .deadline_ns = ns,
            .due_tick = due_tick,
            .item = item,
        };
        self.len += 1;
    }

    fn remove(self: *Model, id: usize) bool {
        if (!self.entries[id].live) return false;
        self.entries[id].live = false;
        self.len -= 1;
        return true;
    }

    fn update(self: *Model, id: usize, ns: u64) error{OutOfRange}!bool {
        if (!self.entries[id].live) return false;
        const due_tick = try self.quantize(ns);
        self.entries[id].deadline_ns = ns;
        self.entries[id].due_tick = due_tick;
        return true;
    }

    fn advanceTo(self: *Model, ns: u64) void {
        const target_tick = @divFloor(ns - origin_ns, tick_ns);
        if (target_tick > self.current_tick) self.current_tick = target_tick;
    }

    fn nextWakeNs(self: *const Model) ?u64 {
        if (self.len == 0) return null;

        var best: ?u64 = null;
        for (self.entries) |entry| {
            if (!entry.live) continue;
            if (entry.due_tick <= self.current_tick) return self.cursorNs();
            if (best == null or entry.due_tick < best.?) best = entry.due_tick;
        }
        return origin_ns + best.? * tick_ns;
    }

    fn expiredMask(self: *const Model) u64 {
        var mask: u64 = 0;
        for (self.entries) |entry| {
            if (entry.live and entry.due_tick <= self.current_tick) {
                mask |= itemBit(entry.item);
            }
        }
        return mask;
    }

    fn popExpiredItem(self: *Model, item: u8) void {
        for (&self.entries) |*entry| {
            if (entry.live and entry.item == item and entry.due_tick <= self.current_tick) {
                entry.live = false;
                self.len -= 1;
                return;
            }
        }
        unreachable;
    }

    fn clear(self: *Model) void {
        for (&self.entries) |*entry| entry.live = false;
        self.len = 0;
    }
};

fn expectModelState(comptime Wheel: type, wheel: *const Wheel, model: *const Model) !void {
    try testing.expectEqual(model.len, wheel.len());
    try expectNextWake(wheel.nextWake(), model.nextWakeNs());
    wheel.assertValid();
}

fn popAndMirror(comptime Wheel: type, wheel: *Wheel, model: *Model) !void {
    const expired = model.expiredMask();
    const entry = wheel.popExpired() orelse {
        try testing.expectEqual(@as(u64, 0), expired);
        return;
    };
    const bit = itemBit(entry.item);
    try testing.expect((expired & bit) != 0);
    model.popExpiredItem(entry.item);
    try expectModelState(Wheel, wheel, model);
}

test "model: deterministic sequence matches reference wheel semantics" {
    const Wheel = TestWheel(u8, Model.capacity);
    var wheel = Wheel.init(instant(Model.origin_ns));
    var model = Model{};
    var handles: [Model.capacity]Wheel.Handle = undefined;

    try expectModelState(Wheel, &wheel, &model);

    handles[0] = try wheel.insert(deadline(5), 0);
    try model.insert(0, 5, 0);
    try expectModelState(Wheel, &wheel, &model);

    handles[1] = try wheel.insert(deadline(24), 1);
    try model.insert(1, 24, 1);
    try expectModelState(Wheel, &wheel, &model);

    try testing.expectError(error.OutOfRange, wheel.insert(deadline(80), 5));
    try expectModelState(Wheel, &wheel, &model);

    try testing.expect(try wheel.updateDeadline(handles[1], deadline(45)));
    try testing.expect(try model.update(1, 45));
    try expectModelState(Wheel, &wheel, &model);

    try testing.expectError(error.OutOfRange, wheel.updateDeadline(handles[0], Deadline.never));
    try expectModelState(Wheel, &wheel, &model);

    wheel.advanceTo(instant(9));
    model.advanceTo(9);
    try expectModelState(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);

    wheel.advanceTo(instant(10));
    model.advanceTo(10);
    try expectModelState(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);
    try testing.expect(!wheel.contains(handles[0]));
    try testing.expect(wheel.remove(handles[0]) == null);
    try testing.expect(!try wheel.updateDeadline(handles[0], deadline(10)));
    try expectModelState(Wheel, &wheel, &model);

    handles[2] = try wheel.insert(deadline(70), 2);
    try model.insert(2, 70, 2);
    try expectModelState(Wheel, &wheel, &model);

    try testing.expect(try wheel.updateDeadline(handles[1], deadline(15)));
    try testing.expect(try model.update(1, 15));
    try expectModelState(Wheel, &wheel, &model);

    try testing.expectError(error.OutOfRange, wheel.updateDeadline(handles[1], deadline(90)));
    try expectModelState(Wheel, &wheel, &model);

    wheel.advanceTo(instant(100));
    model.advanceTo(100);
    try expectModelState(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);
    try expectModelState(Wheel, &wheel, &model);

    handles[3] = try wheel.insert(deadline(100), 3);
    try model.insert(3, 100, 3);
    try expectModelState(Wheel, &wheel, &model);
    try popAndMirror(Wheel, &wheel, &model);

    handles[4] = try wheel.insert(deadline(120), 4);
    try model.insert(4, 120, 4);
    handles[5] = try wheel.insert(deadline(150), 5);
    try model.insert(5, 150, 5);
    try expectModelState(Wheel, &wheel, &model);

    wheel.clearRetainingCapacity();
    model.clear();
    try expectModelState(Wheel, &wheel, &model);
    try testing.expect(wheel.remove(handles[4]) == null);
    try testing.expect(!try wheel.updateDeadline(handles[5], deadline(100)));
    try expectModelState(Wheel, &wheel, &model);
}
