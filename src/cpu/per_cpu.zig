//! Per-CPU cache-line-padded storage. See `docs/specs/cpu/per-cpu.md`.

const std = @import("std");

const debug = @import("../core/debug.zig");
const cache = @import("../mem/cache.zig");

const CachePad = cache.CachePad;

/// Fixed-capacity, cache-line-padded, typed per-CPU storage. `Static` owns
/// inline `[N]CachePad(T)` storage; `Bounded` borrows a caller-provided
/// `[]CachePad(T)` slice. Neither variant discovers CPUs, orders accesses
/// across slots, or enforces affinity; routing is caller policy.
pub const PerCPU = struct {
    /// Provides inline `[N]CachePad(T)` storage indexed by a caller-supplied
    /// CPU index. `Static(T, 0)` is a compile error because a zero-capacity
    /// array has no valid consumer.
    pub fn Static(comptime T: type, comptime N: usize) type {
        if (N == 0) {
            @compileError("PerCPU.Static: capacity N must be > 0");
        }

        return struct {
            storage: [N]Padded,

            const Self = @This();

            /// Cache-line-padded slot type; `Padded.value` is the payload `T`.
            pub const Padded = CachePad(T);

            /// `OutOfBounds`: index at or past `capacity()`.
            pub const Error = error{OutOfBounds};

            /// Fill every slot's payload with `default`.
            pub fn init(default: T) Self {
                var self: Self = .{ .storage = undefined };
                fillDefault(Padded, T, self.storage[0..], default);
                return self;
            }

            /// Call `make(index)` once per slot, in index order, and store
            /// each returned value in the matching slot.
            pub fn initFn(comptime make: fn (index: usize) T) Self {
                var self: Self = .{ .storage = undefined };
                fillFn(Padded, T, self.storage[0..], make);
                return self;
            }

            /// Call `fill(index, slot_ptr)` once per slot, in index order,
            /// with a pointer to that slot's payload.
            pub fn initEach(comptime fill: fn (index: usize, slot: *T) void) Self {
                var self: Self = .{ .storage = undefined };
                fillEach(Padded, T, self.storage[0..], fill);
                return self;
            }

            /// Leaves every slot's payload undefined. The caller must write
            /// each slot before reading.
            pub fn initUndefined() Self {
                return .{ .storage = undefined };
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return N;
            }

            pub fn len(self: *const Self) usize {
                _ = self;
                return N;
            }

            /// Unchecked read. Out-of-bounds behavior follows the ambient
            /// Zig array-bounds policy: trap in Debug/ReleaseSafe, undefined
            /// in ReleaseFast/ReleaseSmall.
            pub fn get(self: *const Self, index: usize) T {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(index < N);
                }
                return self.storage[index].value;
            }

            /// Unchecked pointer to the payload in slot `index`. Same bounds
            /// policy as `get`.
            pub fn getPtr(self: *Self, index: usize) *T {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(index < N);
                }
                return &self.storage[index].value;
            }

            /// Bounds-checked read; returns `error.OutOfBounds` when
            /// `index >= capacity()`.
            pub fn at(self: *const Self, index: usize) Error!T {
                if (index >= N) return error.OutOfBounds;
                return self.storage[index].value;
            }

            /// Bounds-checked pointer; returns `error.OutOfBounds` when
            /// `index >= capacity()`.
            pub fn atPtr(self: *Self, index: usize) Error!*T {
                if (index >= N) return error.OutOfBounds;
                return &self.storage[index].value;
            }

            /// Returns a mutable padded slot slice. Access each payload through
            /// `slot.value`.
            pub fn slots(self: *Self) []Padded {
                return self.storage[0..];
            }

            /// Returns an immutable padded slot slice. Access each payload through
            /// `slot.value`.
            pub fn slotsConst(self: *const Self) []const Padded {
                return self.storage[0..];
            }

            /// Invariant: The storage base is padded-aligned, and adjacent slots are
            /// exactly `@sizeOf(Padded)` apart. This method does not gate checks;
            /// callers can gate it with `stdx.core.debug.checksEnabled(.build_mode)`.
            pub fn assertValid(self: *const Self) void {
                assertValidPadded(Padded, self.storage[0..]);
            }
        };
    }

    /// Runtime-capacity per-CPU storage over a caller-provided
    /// `[]CachePad(T)` slice. Copying a `Bounded` shares the backing slice;
    /// every copy sees writes performed through any other copy.
    pub fn Bounded(comptime T: type) type {
        return struct {
            slots_backing: []Padded,

            const Self = @This();

            /// Cache-line-padded slot type; `Padded.value` is the payload `T`.
            pub const Padded = CachePad(T);

            /// `OutOfBounds`: index at or past `capacity()`.
            pub const Error = error{OutOfBounds};

            /// Stores `backing` and fills every slot's payload with `default`.
            pub fn init(backing: []Padded, default: T) Self {
                fillDefault(Padded, T, backing, default);
                return .{ .slots_backing = backing };
            }

            /// Stores `backing` and calls `make(index)` once per slot in index
            /// order.
            pub fn initFn(
                backing: []Padded,
                comptime make: fn (index: usize) T,
            ) Self {
                fillFn(Padded, T, backing, make);
                return .{ .slots_backing = backing };
            }

            /// Stores `backing` and calls `fill(index, slot_ptr)` once per slot
            /// in index order.
            pub fn initEach(
                backing: []Padded,
                comptime fill: fn (index: usize, slot: *T) void,
            ) Self {
                fillEach(Padded, T, backing, fill);
                return .{ .slots_backing = backing };
            }

            /// Stores `backing` without writing. The caller must write each
            /// slot before reading.
            pub fn initUndefined(backing: []Padded) Self {
                return .{ .slots_backing = backing };
            }

            pub fn capacity(self: *const Self) usize {
                return self.slots_backing.len;
            }

            pub fn len(self: *const Self) usize {
                return self.slots_backing.len;
            }

            pub fn get(self: *const Self, index: usize) T {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(index < self.slots_backing.len);
                }
                return self.slots_backing[index].value;
            }

            pub fn getPtr(self: *Self, index: usize) *T {
                if (debug.checksEnabled(.build_mode)) {
                    std.debug.assert(index < self.slots_backing.len);
                }
                return &self.slots_backing[index].value;
            }

            pub fn at(self: *const Self, index: usize) Error!T {
                if (index >= self.slots_backing.len) return error.OutOfBounds;
                return self.slots_backing[index].value;
            }

            pub fn atPtr(self: *Self, index: usize) Error!*T {
                if (index >= self.slots_backing.len) return error.OutOfBounds;
                return &self.slots_backing[index].value;
            }

            pub fn slots(self: *Self) []Padded {
                return self.slots_backing;
            }

            pub fn slotsConst(self: *const Self) []const Padded {
                return self.slots_backing;
            }

            /// Invariant: The backing-slice base is padded-aligned, and adjacent slots
            /// are exactly `@sizeOf(Padded)` apart. This method does not gate checks;
            /// callers can gate it with `stdx.core.debug.checksEnabled(.build_mode)`.
            pub fn assertValid(self: *const Self) void {
                assertValidPadded(Padded, self.slots_backing);
            }
        };
    }
};

fn fillDefault(
    comptime Padded: type,
    comptime T: type,
    padded: []Padded,
    default: T,
) void {
    for (padded) |*slot| {
        slot.value = default;
    }
}

fn fillFn(
    comptime Padded: type,
    comptime T: type,
    padded: []Padded,
    comptime make: fn (index: usize) T,
) void {
    for (padded, 0..) |*slot, index| {
        slot.value = make(index);
    }
}

fn fillEach(
    comptime Padded: type,
    comptime T: type,
    padded: []Padded,
    comptime fill: fn (index: usize, slot: *T) void,
) void {
    for (padded, 0..) |*slot, index| {
        fill(index, &slot.value);
    }
}

fn assertValidPadded(comptime Padded: type, padded: []const Padded) void {
    const base = @intFromPtr(padded.ptr);
    std.debug.assert(base % @alignOf(Padded) == 0);

    if (padded.len >= 2) {
        const first = @intFromPtr(&padded[0]);
        const second = @intFromPtr(&padded[1]);
        std.debug.assert(second - first == @sizeOf(Padded));
    }
}
