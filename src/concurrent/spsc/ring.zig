//! Bounded single-producer/single-consumer ring. Spec: docs/specs/concurrent/spsc-ring.md.

const std = @import("std");

const bits = @import("../../bits.zig");
const cache = @import("../../mem/cache.zig");

const CachePad = cache.CachePad;

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("SPSC ring element type must have nonzero size");
}

fn requireStaticCapacity(comptime capacity_items: usize) void {
    if (!bits.isPowerOfTwo(usize, capacity_items)) {
        @compileError("SPSC ring capacity must be non-zero and a power of two");
    }
}

/// Family of bounded single-producer/single-consumer FIFO rings. Both
/// variants share head/tail synchronization: exactly one producer
/// release-publishes tail advances, exactly one consumer release-publishes
/// head advances, and each side acquire-loads the peer's index before
/// touching the slot. The ring owns data movement and publication only;
/// wake, scheduler, and waiting policy belong to the caller (typically
/// paired with `stdx.sync.Signal`).
pub const Ring = struct {
    /// Inline `[capacity_items]Slot` storage. Capacity is a comptime
    /// non-zero power of two; zero-sized `T` is rejected at compile time.
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime requireRuntimeValue(T);
        comptime requireStaticCapacity(capacity_items);

        return struct {
            slots: [item_capacity]Slot = undefined,
            head: CachePad(std.atomic.Value(usize)) =
                .{ .value = std.atomic.Value(usize).init(0) },
            tail: CachePad(std.atomic.Value(usize)) =
                .{ .value = std.atomic.Value(usize).init(0) },

            const Self = @This();

            /// Per-slot storage. SPSC does not carry a per-slot publication
            /// sequence: head and tail alone synchronize slot ownership
            /// because there is exactly one producer and one consumer.
            pub const Slot = struct {
                item: T = undefined,
            };

            /// `Full`: `tryPushBack` observed `tail - head == capacity`;
            /// ring is unchanged.
            pub const Error = error{Full};

            /// Comptime capacity in items.
            pub const item_capacity = capacity_items;

            /// Reset head and tail to zero. Must be called before any
            /// concurrent use.
            pub fn init(self: *Self) void {
                self.head.value.store(0, .monotonic);
                self.tail.value.store(0, .monotonic);
            }

            /// Fixed capacity in items.
            pub fn capacity(self: *const Self) usize {
                _ = self;
                return item_capacity;
            }

            /// Consumer snapshot: true when the ring holds no published
            /// item. Uses an acquire load of the producer's tail. The
            /// producer must not consult this to decide whether to publish;
            /// `tryPushBack`'s return value is authoritative about full.
            pub fn isEmpty(self: *const Self) bool {
                return isEmptyImpl(&self.head, &self.tail);
            }

            /// One-attempt producer enqueue. On success, `item` is
            /// release-published by advancing tail. On `error.Full` the
            /// ring is unchanged; retry, backoff, and signaling policies
            /// belong to the caller.
            pub fn tryPushBack(self: *Self, item: T) Error!void {
                return tryPushBackImpl(Slot, T, self.slots[0..], &self.head, &self.tail, item);
            }

            /// Single-consumer dequeue. Returns the next published item in
            /// FIFO order and release-frees the slot, or `null` when the
            /// ring holds no published item.
            pub fn popFront(self: *Self) ?T {
                return popFrontImpl(Slot, T, self.slots[0..], &self.head, &self.tail);
            }

            /// Structural sanity check for exclusive or quiescent access.
            /// Does not prove absence of concurrent races.
            pub fn assertValid(self: *const Self) void {
                std.debug.assert(bits.isPowerOfTwo(usize, item_capacity));
                std.debug.assert(
                    self.tail.value.load(.monotonic) -% self.head.value.load(.monotonic) <= item_capacity,
                );
            }
        };
    }

    /// Borrowed `[]Slot` storage. Slice length must be a non-zero power of
    /// two; zero-sized `T` is rejected at compile time. Caller owns slot
    /// storage lifetime and address stability for the ring lifetime.
    pub fn Bounded(comptime T: type) type {
        comptime requireRuntimeValue(T);

        return struct {
            slots: []Slot,
            head: CachePad(std.atomic.Value(usize)) =
                .{ .value = std.atomic.Value(usize).init(0) },
            tail: CachePad(std.atomic.Value(usize)) =
                .{ .value = std.atomic.Value(usize).init(0) },

            const Self = @This();

            /// Per-slot storage. SPSC does not carry a per-slot publication
            /// sequence: head and tail alone synchronize slot ownership
            /// because there is exactly one producer and one consumer.
            pub const Slot = struct {
                item: T = undefined,
            };

            /// `Full`: `tryPushBack` observed `tail - head == capacity`;
            /// ring is unchanged.
            pub const Error = error{Full};

            /// Borrow `slots` and reset head and tail to zero. Asserts
            /// non-zero power-of-two slice length. Must be called before
            /// any concurrent use.
            pub fn init(self: *Self, slots: []Slot) void {
                std.debug.assert(bits.isPowerOfTwo(usize, slots.len));
                self.slots = slots;
                self.head.value.store(0, .monotonic);
                self.tail.value.store(0, .monotonic);
            }

            /// Runtime capacity in items, equal to `slots.len`.
            pub fn capacity(self: *const Self) usize {
                return self.slots.len;
            }

            /// Consumer snapshot: true when the ring holds no published
            /// item. Uses an acquire load of the producer's tail.
            pub fn isEmpty(self: *const Self) bool {
                return isEmptyImpl(&self.head, &self.tail);
            }

            /// One-attempt producer enqueue. On success, `item` is
            /// release-published by advancing tail. On `error.Full` the
            /// ring is unchanged.
            pub fn tryPushBack(self: *Self, item: T) Error!void {
                return tryPushBackImpl(Slot, T, self.slots, &self.head, &self.tail, item);
            }

            /// Single-consumer dequeue. Returns the next published item in
            /// FIFO order and release-frees the slot, or `null` when the
            /// ring holds no published item.
            pub fn popFront(self: *Self) ?T {
                return popFrontImpl(Slot, T, self.slots, &self.head, &self.tail);
            }

            /// Structural sanity check for exclusive or quiescent access.
            /// Does not prove absence of concurrent races.
            pub fn assertValid(self: *const Self) void {
                const item_capacity = self.slots.len;
                std.debug.assert(bits.isPowerOfTwo(usize, item_capacity));
                std.debug.assert(
                    self.tail.value.load(.monotonic) -% self.head.value.load(.monotonic) <= item_capacity,
                );
            }
        };
    }
};

fn tryPushBackImpl(
    comptime Slot: type,
    comptime T: type,
    slots: []Slot,
    head: *const CachePad(std.atomic.Value(usize)),
    tail: *CachePad(std.atomic.Value(usize)),
    item: T,
) error{Full}!void {
    std.debug.assert(slots.len != 0);
    std.debug.assert(bits.isPowerOfTwo(usize, slots.len));

    const capacity = slots.len;
    const mask = capacity - 1;
    const observed_tail = tail.value.load(.monotonic);

    // Ordering: the acquire load pairs with the consumer's release-store of head in popFrontImpl.
    // This ensures the slot at observed_tail & mask is free for reuse before writing it.
    const observed_head = head.value.load(.acquire);

    if (observed_tail -% observed_head >= capacity) return error.Full;

    const slot = &slots[observed_tail & mask];
    slot.item = item;

    // Ordering: the release store publishes slot.item to the consumer's acquire-load of tail in popFrontImpl.
    tail.value.store(observed_tail +% 1, .release);
}

fn popFrontImpl(
    comptime Slot: type,
    comptime T: type,
    slots: []Slot,
    head: *CachePad(std.atomic.Value(usize)),
    tail: *const CachePad(std.atomic.Value(usize)),
) ?T {
    std.debug.assert(slots.len != 0);
    std.debug.assert(bits.isPowerOfTwo(usize, slots.len));

    const observed_head = head.value.load(.monotonic);

    // Ordering: the acquire load pairs with the producer's release-store of tail in tryPushBackImpl.
    // This ensures the slot's item write is visible before it is read.
    const observed_tail = tail.value.load(.acquire);

    if (observed_tail == observed_head) return null;

    const slot = &slots[observed_head & (slots.len - 1)];
    const out = slot.item;

    // Ordering: the release store publishes slot consumption to the producer's acquire-load of head in tryPushBackImpl.
    head.value.store(observed_head +% 1, .release);
    return out;
}

fn isEmptyImpl(
    head: *const CachePad(std.atomic.Value(usize)),
    tail: *const CachePad(std.atomic.Value(usize)),
) bool {
    const observed_head = head.value.load(.monotonic);

    // Ordering: the acquire load pairs with the producer's release-store of tail in tryPushBackImpl.
    const observed_tail = tail.value.load(.acquire);
    return observed_head == observed_tail;
}
