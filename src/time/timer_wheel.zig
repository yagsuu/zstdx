//! Fixed-tick, fixed-capacity timer wheel. Spec: docs/specs/time/timer-wheel.md.

const std = @import("std");

const debug = @import("../core/debug.zig");
const deadline = @import("deadline.zig");
const monotonic = @import("monotonic.zig");

const Deadline = deadline.Deadline;
const Instant = monotonic.Instant;

const none: usize = std.math.maxInt(usize);
const max_u64: u64 = std.math.maxInt(u64);

/// Fixed-capacity, single-level timer wheel for coarse timers. Callers supply
/// the origin and advance time explicitly; operations never read a clock or
/// invoke callbacks.
pub const TimerWheel = struct {
    pub const Config = struct {
        tick_ns: u64,
        slot_count: usize,
    };

    pub fn Static(
        comptime T: type,
        comptime capacity_items: usize,
        comptime config: Config,
    ) type {
        comptime validateConfig(config);

        return struct {
            pub const item_capacity = capacity_items;
            pub const wheel_config = config;

            pub const Handle = enum(u128) { _ };
            pub const Entry = struct {
                deadline: Deadline,
                item: T,
            };
            pub const Error = error{ Full, OutOfRange };
            pub const RangeError = error{OutOfRange};

            const Self = @This();
            const Slot = SlotFor(T);
            const Bucket = BucketFor();

            slots: [capacity_items]Slot,
            buckets: [config.slot_count]Bucket,
            origin_instant: Instant,
            cursor_tick: u64,
            live_len: usize,
            free_head: usize,
            expired_head: usize,
            expired_tail: usize,

            fn slotSlice(self: *Self) []Slot {
                return self.slots[0..capacity_items];
            }

            fn slotSliceConst(self: *const Self) []const Slot {
                return self.slots[0..capacity_items];
            }

            fn bucketSlice(self: *Self) []Bucket {
                return self.buckets[0..config.slot_count];
            }

            fn bucketSliceConst(self: *const Self) []const Bucket {
                return self.buckets[0..config.slot_count];
            }

            pub fn init(origin_value: Instant) Self {
                var self: Self = .{
                    .slots = undefined,
                    .buckets = undefined,
                    .origin_instant = origin_value,
                    .cursor_tick = 0,
                    .live_len = 0,
                    .free_head = none,
                    .expired_head = none,
                    .expired_tail = none,
                };
                initStorage(self.slotSlice(), self.bucketSlice(), &self.free_head);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return self.live_len;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return capacity_items;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.live_len;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.live_len == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.live_len == self.capacity();
            }

            pub fn origin(self: *const Self) Instant {
                return self.origin_instant;
            }

            pub fn cursor(self: *const Self) Instant {
                return instantForTick(self.origin_instant, self.cursor_tick, config.tick_ns);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                clearStorage(
                    self.slotSlice(),
                    self.bucketSlice(),
                    &self.live_len,
                    &self.free_head,
                    &self.expired_head,
                    &self.expired_tail,
                );
            }

            pub fn advanceTo(self: *Self, now: Instant) void {
                advanceToStorage(
                    self.slotSlice(),
                    self.bucketSlice(),
                    self.origin_instant,
                    &self.cursor_tick,
                    &self.expired_head,
                    &self.expired_tail,
                    now,
                    config,
                );
            }

            pub fn insert(self: *Self, dl: Deadline, item: T) Error!Handle {
                const due_tick = try self.quantize(dl);
                if (self.isFull()) return error.Full;
                return self.insertDueAssumeCapacity(dl, item, due_tick);
            }

            pub fn insertAssumeCapacity(
                self: *Self,
                dl: Deadline,
                item: T,
            ) RangeError!Handle {
                const due_tick = try self.quantize(dl);
                if (debug.checksEnabled(.build_mode)) std.debug.assert(!self.isFull());
                return self.insertDueAssumeCapacity(dl, item, due_tick);
            }

            pub fn nextWake(self: *const Self) ?Instant {
                return nextWakeStorage(
                    self.slotSliceConst(),
                    self.bucketSliceConst(),
                    self.origin_instant,
                    self.cursor_tick,
                    self.expired_head,
                    config.tick_ns,
                );
            }

            pub fn popExpired(self: *Self) ?Entry {
                const index = popExpiredIndex(
                    self.slotSlice(),
                    &self.expired_head,
                    &self.expired_tail,
                ) orelse return null;
                return self.removeSlotIndex(index);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                const index = self.liveIndex(handle) orelse return null;
                detachLiveIndex(
                    self.slotSlice(),
                    self.bucketSlice(),
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                );
                return self.removeSlotIndex(index);
            }

            pub fn updateDeadline(
                self: *Self,
                handle: Handle,
                dl: Deadline,
            ) RangeError!bool {
                const index = self.liveIndex(handle) orelse return false;
                const due_tick = try self.quantize(dl);

                detachLiveIndex(
                    self.slotSlice(),
                    self.bucketSlice(),
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                );

                var slot = &self.slotSlice()[index];
                slot.deadline = dl;
                slot.due_tick = due_tick;
                attachByDueTick(
                    self.slotSlice(),
                    self.bucketSlice(),
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                    self.cursor_tick,
                    config.slot_count,
                );
                return true;
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return self.liveIndex(handle) != null;
            }

            pub fn assertValid(self: *const Self) void {
                assertValidStorage(
                    self.slotSliceConst(),
                    self.bucketSliceConst(),
                    self.origin_instant,
                    self.cursor_tick,
                    self.live_len,
                    self.free_head,
                    self.expired_head,
                    self.expired_tail,
                    config,
                );
            }

            fn quantize(self: *const Self, dl: Deadline) RangeError!u64 {
                return quantizeDeadline(
                    dl,
                    self.origin_instant,
                    self.cursor_tick,
                    config,
                );
            }

            fn insertDueAssumeCapacity(
                self: *Self,
                dl: Deadline,
                item: T,
                due_tick: u64,
            ) Handle {
                const slots = self.slotSlice();
                const index = allocSlot(slots, &self.free_head);
                var slot = &slots[index];
                slot.item = item;
                slot.deadline = dl;
                slot.due_tick = due_tick;
                attachByDueTick(
                    self.slotSlice(),
                    self.bucketSlice(),
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                    self.cursor_tick,
                    config.slot_count,
                );
                self.live_len += 1;
                return encodeHandle(Handle, index, slot.generation);
            }

            fn liveIndex(self: *const Self, handle: Handle) ?usize {
                return liveIndexForHandle(self.slotSliceConst(), handle);
            }

            fn removeSlotIndex(self: *Self, index: usize) Entry {
                const slots = self.slotSlice();
                const slot = &slots[index];
                const entry: Entry = .{
                    .deadline = slot.deadline,
                    .item = slot.item,
                };
                freeSlot(slots, &self.free_head, index);
                self.live_len -= 1;
                return entry;
            }
        };
    }

    pub fn Bounded(
        comptime T: type,
        comptime config: Config,
    ) type {
        comptime validateConfig(config);

        return struct {
            pub const wheel_config = config;

            pub const Slot = SlotFor(T);
            pub const Bucket = BucketFor();

            pub const Handle = enum(u128) { _ };
            pub const Entry = struct {
                deadline: Deadline,
                item: T,
            };
            pub const Error = error{ Full, OutOfRange };
            pub const RangeError = error{OutOfRange};

            const Self = @This();

            slots: []Slot,
            buckets: []Bucket,
            origin_instant: Instant,
            cursor_tick: u64,
            live_len: usize,
            free_head: usize,
            expired_head: usize,
            expired_tail: usize,

            pub fn wrap(
                slots: []Slot,
                buckets: []Bucket,
                origin_value: Instant,
            ) Self {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(buckets.len == config.slot_count);
                }

                var self: Self = .{
                    .slots = slots,
                    .buckets = buckets,
                    .origin_instant = origin_value,
                    .cursor_tick = 0,
                    .live_len = 0,
                    .free_head = none,
                    .expired_head = none,
                    .expired_tail = none,
                };
                initStorage(self.slots, self.buckets, &self.free_head);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return self.live_len;
            }

            pub fn capacity(self: *const Self) usize {
                return self.slots.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.live_len;
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.live_len == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.live_len == self.capacity();
            }

            pub fn origin(self: *const Self) Instant {
                return self.origin_instant;
            }

            pub fn cursor(self: *const Self) Instant {
                return instantForTick(self.origin_instant, self.cursor_tick, config.tick_ns);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                clearStorage(
                    self.slots,
                    self.buckets,
                    &self.live_len,
                    &self.free_head,
                    &self.expired_head,
                    &self.expired_tail,
                );
            }

            pub fn advanceTo(self: *Self, now: Instant) void {
                advanceToStorage(
                    self.slots,
                    self.buckets,
                    self.origin_instant,
                    &self.cursor_tick,
                    &self.expired_head,
                    &self.expired_tail,
                    now,
                    config,
                );
            }

            pub fn insert(self: *Self, dl: Deadline, item: T) Error!Handle {
                const due_tick = try self.quantize(dl);
                if (self.isFull()) return error.Full;
                return self.insertDueAssumeCapacity(dl, item, due_tick);
            }

            pub fn insertAssumeCapacity(
                self: *Self,
                dl: Deadline,
                item: T,
            ) RangeError!Handle {
                const due_tick = try self.quantize(dl);
                if (debug.checksEnabled(.build_mode)) std.debug.assert(!self.isFull());
                return self.insertDueAssumeCapacity(dl, item, due_tick);
            }

            pub fn nextWake(self: *const Self) ?Instant {
                return nextWakeStorage(
                    self.slots,
                    self.buckets,
                    self.origin_instant,
                    self.cursor_tick,
                    self.expired_head,
                    config.tick_ns,
                );
            }

            pub fn popExpired(self: *Self) ?Entry {
                const index = popExpiredIndex(
                    self.slots,
                    &self.expired_head,
                    &self.expired_tail,
                ) orelse return null;
                return self.removeSlotIndex(index);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                const index = self.liveIndex(handle) orelse return null;
                detachLiveIndex(
                    self.slots,
                    self.buckets,
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                );
                return self.removeSlotIndex(index);
            }

            pub fn updateDeadline(
                self: *Self,
                handle: Handle,
                dl: Deadline,
            ) RangeError!bool {
                const index = self.liveIndex(handle) orelse return false;
                const due_tick = try self.quantize(dl);

                detachLiveIndex(
                    self.slots,
                    self.buckets,
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                );

                var slot = &self.slots[index];
                slot.deadline = dl;
                slot.due_tick = due_tick;
                attachByDueTick(
                    self.slots,
                    self.buckets,
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                    self.cursor_tick,
                    config.slot_count,
                );
                return true;
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return self.liveIndex(handle) != null;
            }

            pub fn assertValid(self: *const Self) void {
                assertValidStorage(
                    self.slots,
                    self.buckets,
                    self.origin_instant,
                    self.cursor_tick,
                    self.live_len,
                    self.free_head,
                    self.expired_head,
                    self.expired_tail,
                    config,
                );
            }

            fn quantize(self: *const Self, dl: Deadline) RangeError!u64 {
                return quantizeDeadline(
                    dl,
                    self.origin_instant,
                    self.cursor_tick,
                    config,
                );
            }

            fn insertDueAssumeCapacity(
                self: *Self,
                dl: Deadline,
                item: T,
                due_tick: u64,
            ) Handle {
                const index = allocSlot(self.slots, &self.free_head);
                var slot = &self.slots[index];
                slot.item = item;
                slot.deadline = dl;
                slot.due_tick = due_tick;
                attachByDueTick(
                    self.slots,
                    self.buckets,
                    &self.expired_head,
                    &self.expired_tail,
                    index,
                    self.cursor_tick,
                    config.slot_count,
                );
                self.live_len += 1;
                return encodeHandle(Handle, index, slot.generation);
            }

            fn liveIndex(self: *const Self, handle: Handle) ?usize {
                return liveIndexForHandle(self.slots, handle);
            }

            fn removeSlotIndex(self: *Self, index: usize) Entry {
                const slot = &self.slots[index];
                const entry: Entry = .{
                    .deadline = slot.deadline,
                    .item = slot.item,
                };
                freeSlot(self.slots, &self.free_head, index);
                self.live_len -= 1;
                return entry;
            }
        };
    }
};

const SlotState = enum {
    free,
    bucket,
    expired,
};

fn SlotFor(comptime T: type) type {
    return struct {
        item: T = undefined,
        deadline: Deadline = undefined,
        due_tick: u64 = 0,
        generation: u64 = 1,
        prev: usize = none,
        next: usize = none,
        bucket: usize = 0,
        state: SlotState = .free,
        next_free: usize = none,
    };
}

fn BucketFor() type {
    return struct {
        head: usize = none,
        tail: usize = none,
    };
}

fn validateConfig(comptime config: TimerWheel.Config) void {
    if (config.tick_ns == 0) @compileError("TimerWheel.Config.tick_ns must be greater than zero");
    if (config.slot_count < 2) @compileError("TimerWheel.Config.slot_count must be at least 2");
    if (!std.math.isPowerOfTwo(config.slot_count)) {
        @compileError("TimerWheel.Config.slot_count must be a power of two");
    }

    const horizon_ticks: u128 = @as(u128, config.slot_count - 1);
    const horizon_ns: u128 = horizon_ticks * @as(u128, config.tick_ns);
    if (horizon_ns > max_u64) {
        @compileError("TimerWheel.Config horizon must fit in the Instant nanosecond domain");
    }
}

fn initStorage(slots: anytype, buckets: anytype, free_head: *usize) void {
    var i: usize = 0;
    while (i < buckets.len) : (i += 1) {
        buckets[i] = .{};
    }

    free_head.* = if (slots.len == 0) none else 0;
    i = 0;
    while (i < slots.len) : (i += 1) {
        slots[i].generation = 1;
        slots[i].prev = none;
        slots[i].next = none;
        slots[i].bucket = 0;
        slots[i].state = .free;
        slots[i].next_free = if (i + 1 < slots.len) i + 1 else none;
        slots[i].due_tick = 0;
    }
}

fn clearStorage(
    slots: anytype,
    buckets: anytype,
    live_len: *usize,
    free_head: *usize,
    expired_head: *usize,
    expired_tail: *usize,
) void {
    var i: usize = 0;
    while (i < buckets.len) : (i += 1) {
        buckets[i].head = none;
        buckets[i].tail = none;
    }

    expired_head.* = none;
    expired_tail.* = none;
    live_len.* = 0;
    free_head.* = if (slots.len == 0) none else 0;

    i = 0;
    while (i < slots.len) : (i += 1) {
        if (slots[i].state != .free) bumpGeneration(&slots[i].generation);
        slots[i].prev = none;
        slots[i].next = none;
        slots[i].bucket = 0;
        slots[i].state = .free;
        slots[i].next_free = if (i + 1 < slots.len) i + 1 else none;
    }
}

fn quantizeDeadline(
    dl: Deadline,
    origin: Instant,
    cursor_tick: u64,
    comptime config: TimerWheel.Config,
) error{OutOfRange}!u64 {
    if (dl.isNever()) return error.OutOfRange;

    const cursor_ns = instantNsForTick(origin, cursor_tick, config.tick_ns) orelse {
        return error.OutOfRange;
    };
    const deadline_ns = dl.instant().nanos();

    const due_tick: u64 = if (deadline_ns <= cursor_ns) cursor_tick else due: {
        const origin_ns = origin.nanos();
        const delta: u128 = if (deadline_ns <= origin_ns) 0 else @as(u128, deadline_ns - origin_ns);
        const tick_ns: u128 = config.tick_ns;
        const due_u128 = @divFloor(delta + tick_ns - 1, tick_ns);
        if (due_u128 > max_u64) return error.OutOfRange;
        break :due @intCast(due_u128);
    };

    const horizon_end: u128 = @as(u128, cursor_tick) + @as(u128, config.slot_count);
    if (@as(u128, due_tick) < @as(u128, cursor_tick)) return error.OutOfRange;
    if (@as(u128, due_tick) >= horizon_end) return error.OutOfRange;
    if (instantNsForTick(origin, due_tick, config.tick_ns) == null) return error.OutOfRange;
    return due_tick;
}

fn advanceToStorage(
    slots: anytype,
    buckets: anytype,
    origin: Instant,
    cursor_tick: *u64,
    expired_head: *usize,
    expired_tail: *usize,
    now: Instant,
    comptime config: TimerWheel.Config,
) void {
    const cursor_ns = instantNsForTick(origin, cursor_tick.*, config.tick_ns) orelse unreachable;
    const now_ns = now.nanos();

    if (debug.checksEnabled(.build_mode)) std.debug.assert(now_ns >= cursor_ns);
    if (now_ns <= cursor_ns) return;

    const target_tick = tickFloor(origin, now, config.tick_ns);
    if (target_tick <= cursor_tick.*) return;

    const old_tick = cursor_tick.*;
    const advanced: u128 = @as(u128, target_tick) - @as(u128, old_tick);

    if (advanced >= config.slot_count) {
        var bucket_index: usize = 0;
        while (bucket_index < buckets.len) : (bucket_index += 1) {
            expireBucket(slots, &buckets[bucket_index], expired_head, expired_tail);
        }
    } else {
        var tick = old_tick + 1;
        while (tick <= target_tick) : (tick += 1) {
            const bucket_index = bucketIndex(tick, config.slot_count);
            expireBucket(slots, &buckets[bucket_index], expired_head, expired_tail);
        }
    }

    cursor_tick.* = target_tick;
}

fn tickFloor(origin: Instant, now: Instant, tick_ns: u64) u64 {
    const now_ns = now.nanos();
    const origin_ns = origin.nanos();
    if (now_ns <= origin_ns) return 0;
    return @divFloor(now_ns - origin_ns, tick_ns);
}

fn nextWakeStorage(
    slots: anytype,
    buckets: anytype,
    origin: Instant,
    cursor_tick: u64,
    expired_head: usize,
    tick_ns: u64,
) ?Instant {
    if (expired_head != none) return instantForTick(origin, cursor_tick, tick_ns);

    var best: ?u64 = null;
    var bucket_index_value: usize = 0;
    while (bucket_index_value < buckets.len) : (bucket_index_value += 1) {
        const head = buckets[bucket_index_value].head;
        if (head == none) continue;
        const due_tick = slots[head].due_tick;
        if (best == null or due_tick < best.?) best = due_tick;
    }

    return if (best) |due_tick| instantForTick(origin, due_tick, tick_ns) else null;
}

fn allocSlot(slots: anytype, free_head: *usize) usize {
    const index = free_head.*;
    std.debug.assert(index != none);
    var slot = &slots[index];
    std.debug.assert(slot.state == .free);
    free_head.* = slot.next_free;
    slot.next_free = none;
    slot.prev = none;
    slot.next = none;
    return index;
}

fn freeSlot(slots: anytype, free_head: *usize, index: usize) void {
    var slot = &slots[index];
    bumpGeneration(&slot.generation);
    slot.prev = none;
    slot.next = none;
    slot.bucket = 0;
    slot.state = .free;
    slot.next_free = free_head.*;
    free_head.* = index;
}

fn bumpGeneration(generation: *u64) void {
    generation.* +%= 1;
    if (generation.* == 0) generation.* = 1;
}

fn attachByDueTick(
    slots: anytype,
    buckets: anytype,
    expired_head: *usize,
    expired_tail: *usize,
    index: usize,
    cursor_tick: u64,
    comptime slot_count: usize,
) void {
    if (slots[index].due_tick <= cursor_tick) {
        appendExpired(slots, expired_head, expired_tail, index);
        return;
    }

    const bucket_index_value = bucketIndex(slots[index].due_tick, slot_count);
    appendBucket(slots, &buckets[bucket_index_value], bucket_index_value, index);
}

fn appendBucket(slots: anytype, bucket: anytype, bucket_index_value: usize, index: usize) void {
    var slot = &slots[index];
    slot.state = .bucket;
    slot.bucket = bucket_index_value;
    slot.prev = bucket.tail;
    slot.next = none;

    if (bucket.tail == none) {
        bucket.head = index;
    } else {
        slots[bucket.tail].next = index;
    }
    bucket.tail = index;
}

fn appendExpired(slots: anytype, expired_head: *usize, expired_tail: *usize, index: usize) void {
    var slot = &slots[index];
    slot.state = .expired;
    slot.prev = expired_tail.*;
    slot.next = none;

    if (expired_tail.* == none) {
        expired_head.* = index;
    } else {
        slots[expired_tail.*].next = index;
    }
    expired_tail.* = index;
}

fn expireBucket(slots: anytype, bucket: anytype, expired_head: *usize, expired_tail: *usize) void {
    while (bucket.head != none) {
        const index = bucket.head;
        removeFromBucket(slots, bucket, index);
        appendExpired(slots, expired_head, expired_tail, index);
    }
}

fn popExpiredIndex(slots: anytype, expired_head: *usize, expired_tail: *usize) ?usize {
    const index = expired_head.*;
    if (index == none) return null;
    removeFromExpired(slots, expired_head, expired_tail, index);
    return index;
}

fn detachLiveIndex(
    slots: anytype,
    buckets: anytype,
    expired_head: *usize,
    expired_tail: *usize,
    index: usize,
) void {
    switch (slots[index].state) {
        .bucket => removeFromBucket(slots, &buckets[slots[index].bucket], index),
        .expired => removeFromExpired(slots, expired_head, expired_tail, index),
        .free => unreachable,
    }
}

fn removeFromBucket(slots: anytype, bucket: anytype, index: usize) void {
    const prev = slots[index].prev;
    const next = slots[index].next;

    if (prev == none) {
        bucket.head = next;
    } else {
        slots[prev].next = next;
    }

    if (next == none) {
        bucket.tail = prev;
    } else {
        slots[next].prev = prev;
    }

    slots[index].prev = none;
    slots[index].next = none;
}

fn removeFromExpired(slots: anytype, expired_head: *usize, expired_tail: *usize, index: usize) void {
    const prev = slots[index].prev;
    const next = slots[index].next;

    if (prev == none) {
        expired_head.* = next;
    } else {
        slots[prev].next = next;
    }

    if (next == none) {
        expired_tail.* = prev;
    } else {
        slots[next].prev = prev;
    }

    slots[index].prev = none;
    slots[index].next = none;
}

fn bucketIndex(tick: u64, comptime slot_count: usize) usize {
    return @intCast(tick & @as(u64, slot_count - 1));
}

fn encodeHandle(comptime Handle: type, index: usize, generation: u64) Handle {
    const index_u64: u64 = @intCast(index);
    const raw = (@as(u128, generation) << 64) | @as(u128, index_u64);
    return @enumFromInt(raw);
}

const DecodedHandle = struct {
    index: usize,
    generation: u64,
};

fn decodeHandle(handle: anytype) ?DecodedHandle {
    const raw: u128 = @intFromEnum(handle);
    const index_u64: u64 = @truncate(raw);
    const generation: u64 = @truncate(raw >> 64);
    const index = std.math.cast(usize, index_u64) orelse return null;
    return .{
        .index = index,
        .generation = generation,
    };
}

fn liveIndexForHandle(slots: anytype, handle: anytype) ?usize {
    const decoded = decodeHandle(handle) orelse return null;
    if (decoded.index >= slots.len) return null;

    const slot = &slots[decoded.index];
    if (slot.state == .free) return null;
    if (slot.generation != decoded.generation) return null;
    return decoded.index;
}

fn instantForTick(origin: Instant, tick: u64, tick_ns: u64) Instant {
    return Instant.fromNanos(instantNsForTick(origin, tick, tick_ns) orelse unreachable);
}

fn instantNsForTick(origin: Instant, tick: u64, tick_ns: u64) ?u64 {
    const ns_u128 = @as(u128, origin.nanos()) + @as(u128, tick) * @as(u128, tick_ns);
    if (ns_u128 > max_u64) return null;
    return @intCast(ns_u128);
}

fn assertValidStorage(
    slots: anytype,
    buckets: anytype,
    origin: Instant,
    cursor_tick: u64,
    live_len: usize,
    free_head: usize,
    expired_head: usize,
    expired_tail: usize,
    comptime config: TimerWheel.Config,
) void {
    std.debug.assert(buckets.len == config.slot_count);
    std.debug.assert(live_len <= slots.len);
    std.debug.assert(instantNsForTick(origin, cursor_tick, config.tick_ns) != null);

    var state_free_count: usize = 0;
    var state_live_count: usize = 0;
    var i: usize = 0;
    while (i < slots.len) : (i += 1) {
        switch (slots[i].state) {
            .free => state_free_count += 1,
            .bucket, .expired => {
                std.debug.assert(slots[i].generation != 0);
                state_live_count += 1;
            },
        }
    }
    std.debug.assert(state_live_count == live_len);

    const free_count = countFreeList(slots, free_head);
    std.debug.assert(free_count == state_free_count);
    std.debug.assert(free_count + live_len == slots.len);

    var listed_live_count: usize = 0;
    listed_live_count += validateExpiredList(slots, expired_head, expired_tail, cursor_tick);

    var bucket_index_value: usize = 0;
    while (bucket_index_value < buckets.len) : (bucket_index_value += 1) {
        listed_live_count += validateBucketList(
            slots,
            buckets[bucket_index_value],
            bucket_index_value,
            cursor_tick,
            config,
        );
    }
    std.debug.assert(listed_live_count == live_len);
}

fn countFreeList(slots: anytype, free_head: usize) usize {
    var count: usize = 0;
    var index = free_head;
    while (index != none) {
        std.debug.assert(index < slots.len);
        std.debug.assert(slots[index].state == .free);
        count += 1;
        std.debug.assert(count <= slots.len);
        index = slots[index].next_free;
    }
    return count;
}

fn validateExpiredList(slots: anytype, head: usize, tail: usize, cursor_tick: u64) usize {
    if (head == none) std.debug.assert(tail == none);
    if (tail == none) std.debug.assert(head == none);

    var count: usize = 0;
    var prev: usize = none;
    var index = head;
    while (index != none) {
        std.debug.assert(index < slots.len);
        std.debug.assert(slots[index].state == .expired);
        std.debug.assert(slots[index].prev == prev);
        std.debug.assert(slots[index].due_tick <= cursor_tick);
        prev = index;
        index = slots[index].next;
        count += 1;
        std.debug.assert(count <= slots.len);
    }
    std.debug.assert(prev == tail);
    return count;
}

fn validateBucketList(
    slots: anytype,
    bucket: anytype,
    bucket_index_value: usize,
    cursor_tick: u64,
    comptime config: TimerWheel.Config,
) usize {
    if (bucket.head == none) std.debug.assert(bucket.tail == none);
    if (bucket.tail == none) std.debug.assert(bucket.head == none);

    const horizon_end: u128 = @as(u128, cursor_tick) + @as(u128, config.slot_count);
    var count: usize = 0;
    var prev: usize = none;
    var index = bucket.head;
    while (index != none) {
        std.debug.assert(index < slots.len);
        std.debug.assert(slots[index].state == .bucket);
        std.debug.assert(slots[index].bucket == bucket_index_value);
        std.debug.assert(slots[index].prev == prev);
        std.debug.assert(slots[index].due_tick > cursor_tick);
        std.debug.assert(@as(u128, slots[index].due_tick) < horizon_end);
        std.debug.assert(bucketIndex(slots[index].due_tick, config.slot_count) == bucket_index_value);
        prev = index;
        index = slots[index].next;
        count += 1;
        std.debug.assert(count <= slots.len);
    }
    std.debug.assert(prev == bucket.tail);
    return count;
}
