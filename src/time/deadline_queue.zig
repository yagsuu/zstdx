//! Fixed-capacity deadline priority queue. See `docs/specs/time/deadline_queue.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const deadline = @import("deadline.zig");
const monotonic = @import("monotonic.zig");

const Deadline = deadline.Deadline;
const Instant = monotonic.Instant;

const invalid_index = std.math.maxInt(usize);

/// Fixed-capacity deadline queues for caller-owned scheduling state. `Static`
/// owns inline storage; `Bounded` wraps caller storage. Operations never
/// allocate, wait, read a clock, or invoke callbacks.
pub const DeadlineQueue = struct {
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime if (capacity_items == 0) @compileError("DeadlineQueue.Static capacity_items must be non-zero");

        const SlotType = QueueSlot(T);

        return struct {
            slots: [capacity_items]Slot,
            heap: [capacity_items]usize,
            count: usize,
            free_head: usize,

            pub const item_capacity = capacity_items;

            const Self = @This();

            const Slot = SlotType;
            const Impl = Common(T, Self);

            pub const Handle = Impl.Handle;
            pub const Entry = Impl.Entry;
            pub const Error = Impl.Error;

            pub fn init() Self {
                var self: Self = .{
                    .slots = undefined,
                    .heap = undefined,
                    .count = 0,
                    .free_head = invalid_index,
                };
                Impl.initializeStorage(&self);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return Impl.len(self);
            }

            pub fn capacity(self: *const Self) usize {
                return Impl.capacity(self);
            }

            pub fn remaining(self: *const Self) usize {
                return Impl.remaining(self);
            }

            pub fn isEmpty(self: *const Self) bool {
                return Impl.isEmpty(self);
            }

            pub fn isFull(self: *const Self) bool {
                return Impl.isFull(self);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clearRetainingCapacity(self);
            }

            pub fn insert(self: *Self, dl: Deadline, item: T) Error!Handle {
                return Impl.insert(self, dl, item);
            }

            pub fn insertAssumeCapacity(self: *Self, dl: Deadline, item: T) Handle {
                return Impl.insertAssumeCapacity(self, dl, item);
            }

            pub fn peekDeadline(self: *const Self) ?Deadline {
                return Impl.peekDeadline(self);
            }

            pub fn popExpired(self: *Self, now: Instant) ?Entry {
                return Impl.popExpired(self, now);
            }

            pub fn popNext(self: *Self) ?Entry {
                return Impl.popNext(self);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, dl: Deadline) bool {
                return Impl.updateDeadline(self, handle, dl);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.contains(self, handle);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(self);
            }

            fn slotsSlice(self: *Self) []Slot {
                return self.slots[0..];
            }

            fn slotsConstSlice(self: *const Self) []const Slot {
                return self.slots[0..];
            }

            fn heapSlice(self: *Self) []usize {
                return self.heap[0..];
            }

            fn heapConstSlice(self: *const Self) []const usize {
                return self.heap[0..];
            }
        };
    }

    pub fn Bounded(comptime T: type) type {
        const SlotType = QueueSlot(T);

        return struct {
            slots: []Slot,
            heap: []usize,
            count: usize,
            free_head: usize,

            const Self = @This();
            const Impl = Common(T, Self);

            pub const Slot = SlotType;
            pub const Handle = Impl.Handle;
            pub const Entry = Impl.Entry;
            pub const Error = Impl.Error;

            pub fn wrap(slots: []Slot, heap: []usize) Self {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(slots.len == heap.len);
                }

                var self: Self = .{
                    .slots = slots,
                    .heap = heap,
                    .count = 0,
                    .free_head = invalid_index,
                };

                Impl.initializeStorage(&self);
                return self;
            }

            pub fn len(self: *const Self) usize {
                return Impl.len(self);
            }

            pub fn capacity(self: *const Self) usize {
                return Impl.capacity(self);
            }

            pub fn remaining(self: *const Self) usize {
                return Impl.remaining(self);
            }

            pub fn isEmpty(self: *const Self) bool {
                return Impl.isEmpty(self);
            }

            pub fn isFull(self: *const Self) bool {
                return Impl.isFull(self);
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                Impl.clearRetainingCapacity(self);
            }

            pub fn insert(self: *Self, dl: Deadline, item: T) Error!Handle {
                return Impl.insert(self, dl, item);
            }

            pub fn insertAssumeCapacity(self: *Self, dl: Deadline, item: T) Handle {
                return Impl.insertAssumeCapacity(self, dl, item);
            }

            pub fn peekDeadline(self: *const Self) ?Deadline {
                return Impl.peekDeadline(self);
            }

            pub fn popExpired(self: *Self, now: Instant) ?Entry {
                return Impl.popExpired(self, now);
            }

            pub fn popNext(self: *Self) ?Entry {
                return Impl.popNext(self);
            }

            pub fn remove(self: *Self, handle: Handle) ?Entry {
                return Impl.remove(self, handle);
            }

            pub fn updateDeadline(self: *Self, handle: Handle, dl: Deadline) bool {
                return Impl.updateDeadline(self, handle, dl);
            }

            pub fn contains(self: *const Self, handle: Handle) bool {
                return Impl.contains(self, handle);
            }

            pub fn assertValid(self: *const Self) void {
                Impl.assertValid(self);
            }

            fn slotsSlice(self: *Self) []Slot {
                return self.slots;
            }

            fn slotsConstSlice(self: *const Self) []const Slot {
                return self.slots;
            }

            fn heapSlice(self: *Self) []usize {
                return self.heap;
            }

            fn heapConstSlice(self: *const Self) []const usize {
                return self.heap;
            }
        };
    }
};

fn QueueSlot(comptime T: type) type {
    return struct {
        deadline: Deadline,
        item: T,
        generation: u64,
        heap_pos: usize,
        next_free: usize,
        occupied: bool,
    };
}

fn Common(comptime T: type, comptime Self: type) type {
    return struct {
        pub const Handle = enum(u128) { _ };

        pub const Entry = struct {
            deadline: Deadline,
            item: T,
        };

        pub const Error = error{Full};

        const DecodedHandle = struct {
            index: usize,
            generation: u64,
        };

        pub fn len(self: *const Self) usize {
            return self.count;
        }

        pub fn capacity(self: *const Self) usize {
            return self.slotsConstSlice().len;
        }

        pub fn remaining(self: *const Self) usize {
            return self.capacity() - self.count;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.count == self.capacity();
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            const slots = self.slotsSlice();
            const heap = self.heapSlice();
            const old_len = self.count;

            for (heap[0..old_len]) |*heap_entry| {
                const index = heap_entry.*;
                const slot = &slots[index];

                bumpGeneration(slot);

                slot.deadline = Deadline.never;
                slot.item = undefined;
                slot.heap_pos = invalid_index;
                slot.next_free = self.free_head;
                slot.occupied = false;
                self.free_head = index;
                heap_entry.* = invalid_index;
            }

            self.count = 0;
        }

        pub fn insert(self: *Self, dl: Deadline, item: T) Error!Handle {
            if (self.isFull()) return error.Full;
            return self.insertAssumeCapacity(dl, item);
        }

        pub fn insertAssumeCapacity(self: *Self, dl: Deadline, item: T) Handle {
            if (debug.checksEnabled(.build_mode)) {
                std.debug.assert(!self.isFull());
            }

            const slots = self.slotsSlice();
            const heap = self.heapSlice();
            const index = self.free_head;

            std.debug.assert(index != invalid_index);
            std.debug.assert(index < slots.len);

            const slot = &slots[index];
            self.free_head = slot.next_free;

            slot.deadline = dl;
            slot.item = item;
            slot.heap_pos = self.count;
            slot.next_free = invalid_index;
            slot.occupied = true;

            heap[self.count] = index;
            self.count += 1;
            siftUp(self, slot.heap_pos);

            return makeHandle(index, slot.generation);
        }

        pub fn peekDeadline(self: *const Self) ?Deadline {
            if (self.count == 0) return null;
            const slots = self.slotsConstSlice();
            const heap = self.heapConstSlice();
            return slots[heap[0]].deadline;
        }

        pub fn popExpired(self: *Self, now: Instant) ?Entry {
            if (self.count == 0) return null;

            const slots = self.slotsConstSlice();
            const heap = self.heapConstSlice();
            const index = heap[0];
            const dl = slots[index].deadline;

            if (!now.afterOrEq(dl.instant())) return null;

            return removeHeapPosition(self, 0);
        }

        pub fn popNext(self: *Self) ?Entry {
            if (self.count == 0) return null;
            return removeHeapPosition(self, 0);
        }

        pub fn remove(self: *Self, handle: Handle) ?Entry {
            const index = resolveHandle(self, handle) orelse return null;
            const pos = self.slotsConstSlice()[index].heap_pos;
            return removeHeapPosition(self, pos);
        }

        pub fn updateDeadline(self: *Self, handle: Handle, dl: Deadline) bool {
            const index = resolveHandle(self, handle) orelse return false;
            const slots = self.slotsSlice();
            const old_key = deadlineKey(slots[index].deadline);
            const new_key = deadlineKey(dl);
            const pos = slots[index].heap_pos;

            slots[index].deadline = dl;

            if (new_key < old_key) {
                siftUp(self, pos);
            } else if (new_key > old_key) {
                siftDown(self, pos);
            }

            return true;
        }

        pub fn contains(self: *const Self, handle: Handle) bool {
            return resolveHandle(self, handle) != null;
        }

        pub fn assertValid(self: *const Self) void {
            const slots = self.slotsConstSlice();
            const heap = self.heapConstSlice();

            std.debug.assert(heap.len == slots.len);
            std.debug.assert(self.count <= slots.len);
            std.debug.assert(self.remaining() == self.capacity() - self.count);
            std.debug.assert(self.isEmpty() == (self.count == 0));
            std.debug.assert(self.isFull() == (self.count == self.capacity()));
            std.debug.assert((self.peekDeadline() == null) == (self.count == 0));

            var occupied_count: usize = 0;
            for (slots, 0..) |slot, index| {
                if (slot.occupied) {
                    occupied_count += 1;
                    std.debug.assert(slot.next_free == invalid_index);
                    std.debug.assert(slot.heap_pos < self.count);
                    std.debug.assert(heap[slot.heap_pos] == index);
                } else {
                    std.debug.assert(slot.heap_pos == invalid_index);
                }
            }

            std.debug.assert(occupied_count == self.count);

            for (heap[0..self.count], 0..) |index, pos| {
                std.debug.assert(index < slots.len);
                std.debug.assert(slots[index].occupied);
                std.debug.assert(slots[index].heap_pos == pos);
                if (pos > 0) {
                    const parent = @divFloor(pos - 1, 2);
                    std.debug.assert(!lessHeap(self, pos, parent));
                }
            }

            if (self.count == 0) {
                std.debug.assert(self.peekDeadline() == null);
            } else {
                const first = heap[0];
                const first_key = deadlineKey(slots[first].deadline);
                std.debug.assert(self.peekDeadline().? == slots[first].deadline);
                for (heap[0..self.count]) |index| {
                    std.debug.assert(first_key <= deadlineKey(slots[index].deadline));
                }
            }

            var free_count: usize = 0;
            var cursor = self.free_head;
            while (cursor != invalid_index) {
                std.debug.assert(cursor < slots.len);
                std.debug.assert(!slots[cursor].occupied);

                var previous_cursor = self.free_head;
                var previous_count: usize = 0;
                while (previous_count < free_count) : (previous_count += 1) {
                    std.debug.assert(previous_cursor != cursor);
                    previous_cursor = slots[previous_cursor].next_free;
                }

                free_count += 1;
                std.debug.assert(free_count <= slots.len);
                cursor = slots[cursor].next_free;
            }

            std.debug.assert(free_count + occupied_count == slots.len);
        }

        fn initializeStorage(self: *Self) void {
            const slots = self.slotsSlice();
            const heap = self.heapSlice();

            for (slots, 0..) |*slot, index| {
                slot.* = .{
                    .deadline = Deadline.never,
                    .item = undefined,
                    .generation = 1,
                    .heap_pos = invalid_index,
                    .next_free = nextIndex(index, slots.len),
                    .occupied = false,
                };
            }

            for (heap) |*entry| {
                entry.* = invalid_index;
            }

            self.count = 0;
            self.free_head = if (slots.len == 0) invalid_index else 0;
        }

        fn removeHeapPosition(self: *Self, pos: usize) Entry {
            const slots = self.slotsSlice();
            const heap = self.heapSlice();
            std.debug.assert(pos < self.count);

            const removed_index = heap[pos];
            const removed_slot = &slots[removed_index];
            const entry: Entry = .{
                .deadline = removed_slot.deadline,
                .item = removed_slot.item,
            };

            const last_pos = self.count - 1;
            if (pos != last_pos) {
                const moved_index = heap[last_pos];
                heap[pos] = moved_index;
                slots[moved_index].heap_pos = pos;
            }
            heap[last_pos] = invalid_index;
            self.count -= 1;

            removed_slot.heap_pos = invalid_index;

            if (pos != last_pos) {
                fixHeapAt(self, pos);
            }

            releaseSlot(self, removed_index);
            return entry;
        }

        fn releaseSlot(self: *Self, index: usize) void {
            const slot = &self.slotsSlice()[index];
            bumpGeneration(slot);
            slot.deadline = Deadline.never;
            slot.item = undefined;
            slot.heap_pos = invalid_index;
            slot.next_free = self.free_head;
            slot.occupied = false;
            self.free_head = index;
        }

        fn fixHeapAt(self: *Self, pos: usize) void {
            if (pos > 0) {
                const parent = @divFloor(pos - 1, 2);
                if (lessHeap(self, pos, parent)) {
                    siftUp(self, pos);
                    return;
                }
            }
            siftDown(self, pos);
        }

        fn siftUp(self: *Self, start_pos: usize) void {
            var pos = start_pos;
            while (pos > 0) {
                const parent = @divFloor(pos - 1, 2);
                if (!lessHeap(self, pos, parent)) break;
                swapHeap(self, pos, parent);
                pos = parent;
            }
        }

        fn siftDown(self: *Self, start_pos: usize) void {
            var pos = start_pos;
            while (true) {
                const left = pos * 2 + 1;
                if (left >= self.count) break;

                const right = left + 1;
                var best = left;
                if (right < self.count and lessHeap(self, right, left)) {
                    best = right;
                }

                if (!lessHeap(self, best, pos)) break;
                swapHeap(self, pos, best);
                pos = best;
            }
        }

        fn swapHeap(self: *Self, a: usize, b: usize) void {
            if (a == b) return;

            const slots = self.slotsSlice();
            const heap = self.heapSlice();
            const a_index = heap[a];
            const b_index = heap[b];

            heap[a] = b_index;
            heap[b] = a_index;
            slots[a_index].heap_pos = b;
            slots[b_index].heap_pos = a;
        }

        fn lessHeap(self: *const Self, a: usize, b: usize) bool {
            const slots = self.slotsConstSlice();
            const heap = self.heapConstSlice();
            return deadlineKey(slots[heap[a]].deadline) < deadlineKey(slots[heap[b]].deadline);
        }

        fn resolveHandle(self: *const Self, handle: Handle) ?usize {
            const decoded = decodeHandle(handle) orelse return null;
            const slots = self.slotsConstSlice();
            if (decoded.index >= slots.len) return null;

            const slot = slots[decoded.index];
            if (!slot.occupied) return null;
            if (slot.generation != decoded.generation) return null;
            return decoded.index;
        }

        fn makeHandle(index: usize, generation: u64) Handle {
            const index_u64: u64 = @intCast(index);
            const raw = (@as(u128, generation) << 64) | @as(u128, index_u64);
            return @enumFromInt(raw);
        }

        fn decodeHandle(handle: Handle) ?DecodedHandle {
            const raw = @intFromEnum(handle);
            const index_u64: u64 = @truncate(raw);
            const index = std.math.cast(usize, index_u64) orelse return null;
            const generation: u64 = @truncate(raw >> 64);
            return .{
                .index = index,
                .generation = generation,
            };
        }
    };
}

fn nextIndex(index: usize, len: usize) usize {
    return if (index + 1 == len) invalid_index else index + 1;
}

fn deadlineKey(dl: Deadline) u64 {
    return dl.instant().nanos();
}

fn bumpGeneration(slot: anytype) void {
    slot.generation +%= 1;
    if (slot.generation == 0) slot.generation = 1;
}
