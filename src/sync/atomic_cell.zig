//! Typed atomic cell. See `docs/specs/sync/atomic-cell.md`.

const std = @import("std");

/// Typed atomic value whose per-method names encode the memory ordering.
/// Layout-compatible with `std.atomic.Value(T)`. Arithmetic operations are
/// only available when `T` is an integer type; referencing an arithmetic
/// method for any other supported `T` is a compile error.
pub fn AtomicCell(comptime T: type) type {
    comptime validateType(T);

    return struct {
        raw: std.atomic.Value(T),

        const Self = @This();

        comptime {
            std.debug.assert(@sizeOf(Self) == @sizeOf(std.atomic.Value(T)));
            std.debug.assert(@alignOf(Self) == @alignOf(std.atomic.Value(T)));
        }

        /// Returns a cell holding `value`. Publication is the caller's job;
        /// pair with a release-side store or RMW to establish visibility.
        pub fn init(value: T) Self {
            return .{ .raw = std.atomic.Value(T).init(value) };
        }

        /// Reinterpret an existing `std.atomic.Value(T)` as an `AtomicCell(T)`.
        /// Zero-cost; the two types share the same layout with a single
        /// `raw` field.
        pub fn fromStd(ptr: *std.atomic.Value(T)) *Self {
            return @ptrCast(ptr);
        }

        /// Const-preserving companion to `fromStd`.
        pub fn fromStdConst(ptr: *const std.atomic.Value(T)) *const Self {
            return @ptrCast(ptr);
        }

        /// Acquire-loads the value. If the load observes a release sequence,
        /// subsequent reads observe writes sequenced before that sequence.
        pub fn loadAcquire(self: *const Self) T {
            return self.raw.load(.acquire);
        }

        /// Monotonic (relaxed) load: no synchronizes-with edge established.
        pub fn loadMonotonic(self: *const Self) T {
            return self.raw.load(.monotonic);
        }

        /// Release store: writes preceding this store are visible to any
        /// thread that acquire-loads the cell.
        pub fn storeRelease(self: *Self, value: T) void {
            self.raw.store(value, .release);
        }

        /// Monotonic (relaxed) store: no synchronizes-with edge established.
        pub fn storeMonotonic(self: *Self, value: T) void {
            self.raw.store(value, .monotonic);
        }

        /// Acquire-release exchange; returns the previous value.
        pub fn swapAcqRel(self: *Self, value: T) T {
            return self.raw.swap(value, .acq_rel);
        }

        /// Acquire exchange; returns the previous value.
        pub fn swapAcquire(self: *Self, value: T) T {
            return self.raw.swap(value, .acquire);
        }

        /// Release exchange; returns the previous value.
        pub fn swapRelease(self: *Self, value: T) T {
            return self.raw.swap(value, .release);
        }

        /// Monotonic exchange; returns the previous value.
        pub fn swapMonotonic(self: *Self, value: T) T {
            return self.raw.swap(value, .monotonic);
        }

        /// Weak CAS with acq-rel success and acquire failure ordering. Returns
        /// `null` on success and the observed value on failure. Weak CAS can
        /// fail spuriously.
        pub fn cmpxchgWeakAcqRel(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgWeak(expected, new, .acq_rel, .acquire);
        }

        /// Strong CAS with acq-rel success and acquire failure ordering.
        pub fn cmpxchgStrongAcqRel(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgStrong(expected, new, .acq_rel, .acquire);
        }

        /// Weak CAS with acquire success and acquire failure ordering.
        pub fn cmpxchgWeakAcquire(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgWeak(expected, new, .acquire, .acquire);
        }

        /// Strong CAS with acquire success and acquire failure ordering.
        pub fn cmpxchgStrongAcquire(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgStrong(expected, new, .acquire, .acquire);
        }

        /// Weak CAS with release success and monotonic failure ordering.
        pub fn cmpxchgWeakRelease(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgWeak(expected, new, .release, .monotonic);
        }

        /// Strong CAS with release success and monotonic failure ordering.
        pub fn cmpxchgStrongRelease(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgStrong(expected, new, .release, .monotonic);
        }

        /// Weak CAS with monotonic success and monotonic failure ordering.
        pub fn cmpxchgWeakMonotonic(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgWeak(expected, new, .monotonic, .monotonic);
        }

        /// Strong CAS with monotonic success and monotonic failure ordering.
        pub fn cmpxchgStrongMonotonic(self: *Self, expected: T, new: T) ?T {
            return self.raw.cmpxchgStrong(expected, new, .monotonic, .monotonic);
        }

        /// Atomic add with acq-rel ordering; returns the pre-op value.
        /// Integer-only: rejected by `requireInt` for non-integer `T`.
        pub fn fetchAddAcqRel(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchAdd(delta, .acq_rel);
        }

        /// Atomic add with acquire ordering; returns the pre-op value.
        pub fn fetchAddAcquire(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchAdd(delta, .acquire);
        }

        /// Atomic add with release ordering; returns the pre-op value.
        pub fn fetchAddRelease(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchAdd(delta, .release);
        }

        /// Atomic add with monotonic ordering; returns the pre-op value.
        pub fn fetchAddMonotonic(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchAdd(delta, .monotonic);
        }

        /// Atomic subtract with acq-rel ordering; returns the pre-op value.
        pub fn fetchSubAcqRel(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchSub(delta, .acq_rel);
        }

        /// Atomic subtract with acquire ordering; returns the pre-op value.
        pub fn fetchSubAcquire(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchSub(delta, .acquire);
        }

        /// Atomic subtract with release ordering; returns the pre-op value.
        pub fn fetchSubRelease(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchSub(delta, .release);
        }

        /// Atomic subtract with monotonic ordering; returns the pre-op value.
        pub fn fetchSubMonotonic(self: *Self, delta: T) T {
            comptime requireInt();
            return self.raw.fetchSub(delta, .monotonic);
        }

        /// Atomic bitwise-and with acq-rel ordering; returns the pre-op value.
        pub fn fetchAndAcqRel(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchAnd(mask, .acq_rel);
        }

        /// Atomic bitwise-and with acquire ordering; returns the pre-op value.
        pub fn fetchAndAcquire(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchAnd(mask, .acquire);
        }

        /// Atomic bitwise-and with release ordering; returns the pre-op value.
        pub fn fetchAndRelease(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchAnd(mask, .release);
        }

        /// Atomic bitwise-and with monotonic ordering; returns the pre-op value.
        pub fn fetchAndMonotonic(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchAnd(mask, .monotonic);
        }

        /// Atomic bitwise-or with acq-rel ordering; returns the pre-op value.
        pub fn fetchOrAcqRel(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchOr(mask, .acq_rel);
        }

        /// Atomic bitwise-or with acquire ordering; returns the pre-op value.
        pub fn fetchOrAcquire(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchOr(mask, .acquire);
        }

        /// Atomic bitwise-or with release ordering; returns the pre-op value.
        pub fn fetchOrRelease(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchOr(mask, .release);
        }

        /// Atomic bitwise-or with monotonic ordering; returns the pre-op value.
        pub fn fetchOrMonotonic(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchOr(mask, .monotonic);
        }

        /// Atomic bitwise-xor with acq-rel ordering; returns the pre-op value.
        pub fn fetchXorAcqRel(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchXor(mask, .acq_rel);
        }

        /// Atomic bitwise-xor with acquire ordering; returns the pre-op value.
        pub fn fetchXorAcquire(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchXor(mask, .acquire);
        }

        /// Atomic bitwise-xor with release ordering; returns the pre-op value.
        pub fn fetchXorRelease(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchXor(mask, .release);
        }

        /// Atomic bitwise-xor with monotonic ordering; returns the pre-op value.
        pub fn fetchXorMonotonic(self: *Self, mask: T) T {
            comptime requireInt();
            return self.raw.fetchXor(mask, .monotonic);
        }

        /// Compile-time gate: arithmetic ops are only defined for integer `T`.
        /// Trips when a caller references any `fetch*` method on a `bool`,
        /// `enum`, pointer, `?*T`, or `packed struct` cell.
        fn requireInt() void {
            if (@typeInfo(T) != .int) {
                @compileError(
                    "AtomicCell(T): arithmetic operations require an integer T; " ++
                        "bool, enum, pointer, optional-pointer, and packed-struct T reject fetchAdd/Sub/And/Or/Xor",
                );
            }
        }
    };
}

/// Reject any `T` outside the spec's supported category set. Emits a
/// `@compileError` naming the offending category.
fn validateType(comptime T: type) void {
    switch (@typeInfo(T)) {
        .int => validateAtomicInt(T, "AtomicCell(T): integer"),
        .bool => {},
        .@"enum" => |info| validateAtomicInt(info.tag_type, "AtomicCell(T): enum backing integer"),
        .pointer => {},
        .optional => |info| {
            if (@typeInfo(info.child) != .pointer) {
                @compileError(
                    "AtomicCell(T): optional T is only supported when it wraps a pointer (?*U); " ++
                        "other optional payloads are not a supported type category",
                );
            }
        },
        .@"struct" => |info| {
            if (info.layout != .@"packed") {
                @compileError(
                    "AtomicCell(T): non-packed struct is not a supported type category; " ++
                        "use a packed struct(uN) with N in {8, 16, 32, 64}",
                );
            }
            const backing = info.backing_integer orelse @compileError(
                "AtomicCell(T): packed struct T must declare an explicit backing integer",
            );
            validateAtomicInt(backing, "AtomicCell(T): packed struct backing integer");
        },
        else => @compileError(
            "AtomicCell(T): unsupported type category; " ++
                "allowed: integer (u8/u16/u32/u64/i8/i16/i32/i64/usize/isize), bool, enum, pointer, packed struct(uN)",
        ),
    }
}

/// Enforce that `I` is one of the widths `std.atomic.Value` guarantees on
/// every supported target: 8, 16, 32, or 64 bits (`usize`/`isize` always
/// alias one of these on the targets zstdx supports).
fn validateAtomicInt(comptime I: type, comptime label: []const u8) void {
    switch (@typeInfo(I)) {
        .int => |info| {
            const bits = info.bits;
            const ok = bits == 8 or bits == 16 or bits == 32 or bits == 64;
            if (!ok) {
                @compileError(label ++ ": width must be 8, 16, 32, or 64 bits");
            }
        },
        else => @compileError(label ++ ": must be an integer type"),
    }
}
