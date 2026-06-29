//! Typed, fixed-capacity, intrusive-free-list object pool family. See
//! docs/specs/mem/pool.md.
//!
//! Storage discipline: a bump-then-freelist hybrid. Until a slot is
//! released, the pool serves new allocations by carving from an unused
//! tail. Released slots are linked into a LIFO free list whose pointers
//! reference the live pool storage. The eager-link `init()` strategy
//! would require self-referential pointers to outlive the return-by-value
//! of `init()`, which is unsafe; the bump-then-freelist strategy avoids
//! constructing any pointer into pool storage until a `release` call
//! against a pool whose address is already stable.

const std = @import("std");

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("pool element type must have nonzero size");
}

/// Fixed-capacity object pool family. Both variants store `T` inside a
/// private `Slot = union(enum) { free, occupied }` and share LIFO
/// intrusive-free-list discipline.
pub const Pool = struct {
    /// Inline `[capacity_items]Slot` storage. The pool value owns its
    /// backing storage; do not move the value while any pointer is live.
    pub fn Static(comptime T: type, comptime capacity_items: usize) type {
        comptime requireRuntimeValue(T);
        return struct {
            buffer: [capacity_items]Slot = undefined,
            free_head: ?*Slot = null,
            bump_index: usize = 0,
            live_count: usize = 0,

            const Self = @This();

            /// Per-element storage. `free` carries the next pointer in the
            /// intrusive free list; `occupied` holds the live `T`.
            pub const Slot = union(enum) {
                free: ?*Slot,
                occupied: T,
            };

            /// `OutOfMemory`: pool has no free slots.
            pub const Error = error{OutOfMemory};

            /// Comptime capacity in items.
            pub const item_capacity = capacity_items;

            pub fn init() Self {
                return .{};
            }

            pub fn len(self: *const Self) usize {
                return self.live_count;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return item_capacity;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.live_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.live_count == item_capacity;
            }

            /// Reset to a fresh empty pool. Invalidates every outstanding
            /// acquired pointer.
            pub fn clearRetainingCapacity(self: *Self) void {
                self.free_head = null;
                self.bump_index = 0;
                self.live_count = 0;
            }

            /// Acquire one uninitialized `T`. Returns `error.OutOfMemory`
            /// when the pool is full.
            pub fn acquire(self: *Self) Error!*T {
                return acquireSlot(Slot, T, self.buffer[0..], &self.free_head, &self.bump_index, &self.live_count);
            }

            /// Return a previously acquired pointer to the free list. The
            /// pointer must come from this pool and must not have been
            /// released already.
            pub fn release(self: *Self, item: *T) void {
                releaseSlot(Slot, T, &self.free_head, &self.live_count, item);
            }

            pub fn isValid(self: *const Self) bool {
                return checkValid(Slot, self.buffer[0..], self.free_head, self.bump_index, self.live_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }

    /// Borrowed `[]Slot` storage. The caller keeps the buffer alive for the
    /// lifetime of the pool and every acquired pointer.
    pub fn Bounded(comptime T: type) type {
        comptime requireRuntimeValue(T);
        return struct {
            buffer: []Slot,
            free_head: ?*Slot = null,
            bump_index: usize = 0,
            live_count: usize = 0,

            const Self = @This();

            pub const Slot = union(enum) {
                free: ?*Slot,
                occupied: T,
            };

            pub const Error = error{OutOfMemory};

            pub fn wrap(buffer: []Slot) Self {
                return .{ .buffer = buffer };
            }

            pub fn len(self: *const Self) usize {
                return self.live_count;
            }

            pub fn capacity(self: *const Self) usize {
                return self.buffer.len;
            }

            pub fn remaining(self: *const Self) usize {
                return self.capacity() - self.len();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.live_count == 0;
            }

            pub fn isFull(self: *const Self) bool {
                return self.live_count == self.buffer.len;
            }

            pub fn clearRetainingCapacity(self: *Self) void {
                self.free_head = null;
                self.bump_index = 0;
                self.live_count = 0;
            }

            pub fn acquire(self: *Self) Error!*T {
                return acquireSlot(Slot, T, self.buffer, &self.free_head, &self.bump_index, &self.live_count);
            }

            pub fn release(self: *Self, item: *T) void {
                releaseSlot(Slot, T, &self.free_head, &self.live_count, item);
            }

            pub fn isValid(self: *const Self) bool {
                return checkValid(Slot, self.buffer, self.free_head, self.bump_index, self.live_count);
            }

            pub fn assertValid(self: *const Self) void {
                std.debug.assert(self.isValid());
            }
        };
    }
};

fn acquireSlot(
    comptime Slot: type,
    comptime T: type,
    buffer: []Slot,
    free_head: *?*Slot,
    bump_index: *usize,
    live_count: *usize,
) error{OutOfMemory}!*T {
    if (free_head.*) |slot| {
        free_head.* = slot.free;
        slot.* = .{ .occupied = undefined };
        live_count.* += 1;
        return &slot.occupied;
    }
    if (bump_index.* >= buffer.len) return error.OutOfMemory;
    const slot = &buffer[bump_index.*];
    bump_index.* += 1;
    slot.* = .{ .occupied = undefined };
    live_count.* += 1;
    return &slot.occupied;
}

fn releaseSlot(
    comptime Slot: type,
    comptime T: type,
    free_head: *?*Slot,
    live_count: *usize,
    item: *T,
) void {
    const slot: *Slot = @alignCast(@fieldParentPtr("occupied", item));
    std.debug.assert(slot.* == .occupied);
    std.debug.assert(live_count.* > 0);
    slot.* = .{ .free = free_head.* };
    free_head.* = slot;
    live_count.* -= 1;
}

fn checkValid(
    comptime Slot: type,
    buffer: []const Slot,
    free_head: ?*Slot,
    bump_index: usize,
    live_count: usize,
) bool {
    if (bump_index > buffer.len) return false;
    if (live_count > bump_index) return false;
    const free_count = bump_index - live_count;
    var seen: usize = 0;
    var current = free_head;
    while (current) |slot| {
        seen += 1;
        if (seen > free_count) return false; // cycle or over-count
        if (!slotInBuffer(Slot, buffer, slot)) return false;
        if (slot.* != .free) return false;
        current = slot.free;
    }
    return seen == free_count;
}

fn slotInBuffer(comptime Slot: type, buffer: []const Slot, slot: *const Slot) bool {
    if (buffer.len == 0) return false;
    const slot_addr = @intFromPtr(slot);
    const base_addr = @intFromPtr(buffer.ptr);
    if (slot_addr < base_addr) return false;
    const offset = slot_addr - base_addr;
    if (offset % @sizeOf(Slot) != 0) return false;
    return offset / @sizeOf(Slot) < buffer.len;
}
