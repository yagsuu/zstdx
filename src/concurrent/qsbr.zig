//! Bounded quiescent-state-based reclamation substrate.
//! See `docs/specs/concurrent/qsbr.md`.

const std = @import("std");

const cache = @import("../mem/cache.zig");

const CachePad = cache.CachePad;

const Word = u64;
const AtomicWord = std.atomic.Value(Word);
const PaddedWord = CachePad(AtomicWord);
const SlotStorage = CachePad(AtomicWord);

const max_participants = @as(usize, std.math.maxInt(u32)) + 1;

/// Grace-period target generation token.
pub const GracePeriod = enum(u64) {
    _,

    pub fn generation(self: GracePeriod) u64 {
        return @intFromEnum(self);
    }
};

/// Participant slot token. The token carries only the numeric slot index.
pub const Participant = enum(u32) {
    _,

    pub fn index(self: Participant) u32 {
        return @intFromEnum(self);
    }
};

/// Fixed-capacity QSBR domain family. QSBR observes lifetime progress only;
/// retired-object storage, freeing, and payload synchronization belong to the caller.
pub const Domain = struct {
    /// Inline participant-slot storage. Capacity is fixed at comptime.
    pub fn Static(comptime capacity_participants: usize) type {
        comptime requireStaticCapacity(capacity_participants);

        return struct {
            global_generation: PaddedWord,
            slots: [participant_capacity]Slot,

            const Self = @This();

            /// Padded atomic participant-slot word.
            pub const Slot = SlotStorage;

            pub const participant_capacity = capacity_participants;

            /// Returns a domain at generation zero with every participant offline.
            pub fn init() Self {
                var self: Self = .{
                    .global_generation = initWord(0),
                    .slots = undefined,
                };
                initSlots(self.slots[0..]);
                return self;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return participant_capacity;
            }

            /// Acquire-loads and returns the current global generation.
            pub fn generation(self: *const Self) u64 {
                return generationImpl(&self.global_generation);
            }

            /// Returns a token for `index`; the token does not reserve or claim the slot.
            pub fn participant(self: *const Self, index: usize) Participant {
                return participantImpl(index, self.capacity());
            }

            /// Reports the current generation; earlier grace periods do not wait on a late-online slot.
            pub fn online(self: *Self, participant_token: Participant) void {
                onlineImpl(&self.global_generation, self.slots[0..], participant_token);
            }

            /// Release-publishes offline state; offline slots never block grace periods.
            pub fn offline(self: *Self, participant_token: Participant) void {
                offlineImpl(self.slots[0..], participant_token);
            }

            /// Release-publishes quiescence at the current generation.
            pub fn quiescent(self: *Self, participant_token: Participant) void {
                quiescentImpl(&self.global_generation, self.slots[0..], participant_token);
            }

            /// Creates a lifetime barrier for objects retired before the call.
            pub fn beginGracePeriod(self: *Self) GracePeriod {
                return beginGracePeriodImpl(&self.global_generation);
            }

            /// Returns whether every blocking participant has reached `grace_period`.
            pub fn isComplete(self: *const Self, grace_period: GracePeriod) bool {
                return isCompleteImpl(self.slots[0..], grace_period);
            }
        };
    }

    /// Borrowed participant-slot storage. Caller owns slice lifetime and address stability.
    pub const Bounded = struct {
        global_generation: PaddedWord,
        slots: []Slot,

        const Self = @This();

        /// Padded atomic participant-slot word.
        pub const Slot = SlotStorage;

        /// Borrows `slots`, resets generation to zero, and marks every participant offline.
        pub fn wrap(slots: []Slot) Self {
            assertRuntimeCapacity(slots.len);
            initSlots(slots);
            return .{
                .global_generation = initWord(0),
                .slots = slots,
            };
        }

        pub fn capacity(self: *const Self) usize {
            return self.slots.len;
        }

        /// Acquire-loads and returns the current global generation.
        pub fn generation(self: *const Self) u64 {
            return generationImpl(&self.global_generation);
        }

        /// Returns a token for `index`; the token does not reserve or claim the slot.
        pub fn participant(self: *const Self, index: usize) Participant {
            return participantImpl(index, self.capacity());
        }

        /// Reports the current generation; earlier grace periods do not wait on a late-online slot.
        pub fn online(self: *Self, participant_token: Participant) void {
            onlineImpl(&self.global_generation, self.slots, participant_token);
        }

        /// Release-publishes offline state; offline slots never block grace periods.
        pub fn offline(self: *Self, participant_token: Participant) void {
            offlineImpl(self.slots, participant_token);
        }

        /// Release-publishes quiescence at the current generation.
        pub fn quiescent(self: *Self, participant_token: Participant) void {
            quiescentImpl(&self.global_generation, self.slots, participant_token);
        }

        /// Creates a lifetime barrier for objects retired before the call.
        pub fn beginGracePeriod(self: *Self) GracePeriod {
            return beginGracePeriodImpl(&self.global_generation);
        }

        /// Returns whether every blocking participant has reached `grace_period`.
        pub fn isComplete(self: *const Self, grace_period: GracePeriod) bool {
            return isCompleteImpl(self.slots, grace_period);
        }
    };
};

const SlotWord = enum(Word) {
    _,

    const offline_bit: Word = @as(Word, 1) << 63;
    const generation_mask: Word = offline_bit - 1;

    fn offline() SlotWord {
        return @enumFromInt(offline_bit);
    }

    fn online(reported_generation: Word) SlotWord {
        std.debug.assert(reported_generation <= generation_mask);
        return @enumFromInt(reported_generation);
    }

    fn fromRaw(encoded: Word) SlotWord {
        return @enumFromInt(encoded);
    }

    fn raw(self: SlotWord) Word {
        return @intFromEnum(self);
    }

    fn isOffline(self: SlotWord) bool {
        return self.raw() & offline_bit != 0;
    }

    fn generation(self: SlotWord) Word {
        return self.raw() & generation_mask;
    }
};

fn requireStaticCapacity(comptime capacity_participants: usize) void {
    if (capacity_participants == 0) {
        @compileError("QSBR Static capacity must be non-zero");
    }

    if (capacity_participants > max_participants) {
        @compileError("QSBR Static capacity exceeds Participant index range");
    }
}

fn assertRuntimeCapacity(capacity_participants: usize) void {
    std.debug.assert(capacity_participants != 0);
    std.debug.assert(capacity_participants <= max_participants);
}

fn initWord(value: Word) PaddedWord {
    return .{ .value = AtomicWord.init(value) };
}

fn initSlot(value: Word) SlotStorage {
    return .{ .value = AtomicWord.init(value) };
}

fn initSlots(slots: []SlotStorage) void {
    for (slots) |*slot| {
        slot.* = initSlot(SlotWord.offline().raw());
    }
}

fn participantImpl(index: usize, capacity_participants: usize) Participant {
    std.debug.assert(index < capacity_participants);
    std.debug.assert(index <= std.math.maxInt(u32));
    return @enumFromInt(@as(u32, @intCast(index)));
}

fn slotIndex(participant_token: Participant, slot_count: usize) usize {
    const index: usize = participant_token.index();
    std.debug.assert(index < slot_count);
    return index;
}

fn generationImpl(global_generation: *const PaddedWord) u64 {
    return global_generation.value.load(.acquire);
}

fn onlineImpl(global_generation: *const PaddedWord, slots: []SlotStorage, participant_token: Participant) void {
    const index = slotIndex(participant_token, slots.len);
    const generation = global_generation.value.load(.acquire);
    slots[index].value.store(SlotWord.online(generation).raw(), .release);
}

fn offlineImpl(slots: []SlotStorage, participant_token: Participant) void {
    const index = slotIndex(participant_token, slots.len);
    slots[index].value.store(SlotWord.offline().raw(), .release);
}

fn quiescentImpl(global_generation: *const PaddedWord, slots: []SlotStorage, participant_token: Participant) void {
    const index = slotIndex(participant_token, slots.len);
    const word = SlotWord.fromRaw(slots[index].value.load(.monotonic));
    std.debug.assert(!word.isOffline());
    const generation = global_generation.value.load(.acquire);
    slots[index].value.store(SlotWord.online(generation).raw(), .release);
}

fn beginGracePeriodImpl(global_generation: *PaddedWord) GracePeriod {
    var current = global_generation.value.load(.acquire);
    while (true) {
        std.debug.assert(current < SlotWord.generation_mask);

        const next = current + 1;
        if (global_generation.value.cmpxchgWeak(current, next, .acq_rel, .acquire)) |observed| {
            current = observed;
            continue;
        }

        return @enumFromInt(next);
    }
}

fn isCompleteImpl(slots: []const SlotStorage, grace_period: GracePeriod) bool {
    const target = grace_period.generation();
    for (slots) |*slot| {
        const word = SlotWord.fromRaw(slot.value.load(.acquire));
        if (word.isOffline()) continue;
        if (word.generation() < target) return false;
    }
    return true;
}

comptime {
    std.debug.assert(@alignOf(SlotStorage) == std.atomic.cache_line);
    std.debug.assert(@sizeOf(SlotStorage) >= std.atomic.cache_line);
}
