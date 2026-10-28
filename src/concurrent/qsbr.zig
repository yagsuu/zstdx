//! bounded quiescent-state-based reclamation

const std = @import("std");

const cache = @import("layout").cache;

const AtomicWord = std.atomic.Value(u64);
const PaddedAtomic = cache.CachePad(AtomicWord);

pub const GracePeriod = enum(u64) {
    _,

    pub fn generation(self: GracePeriod) u64 {
        return @intFromEnum(self);
    }
};

pub const Participant = enum(u32) {
    _,

    pub fn index(self: Participant) u32 {
        return @intFromEnum(self);
    }
};

pub const Domain = struct {
    pub fn Static(comptime count: usize) type {
        comptime Impl.requireCapacity(count);

        return struct {
            current: PaddedAtomic,
            slots: [bound]Slot,

            pub const bound = count;

            pub const Slot = cache.CachePad(std.atomic.Value(Impl.Word));

            const Self = @This();

            pub fn init() Self {
                var self: Self = undefined;
                Impl.initialize(&self);
                return self;
            }

            pub fn capacity(self: *const Self) usize {
                _ = self;
                return bound;
            }

            pub fn generation(self: *const Self) u64 {
                return self.current.value.load(.acquire);
            }

            pub fn participant(self: *const Self, index: usize) Participant {
                std.debug.assert(index < self.capacity());
                return @enumFromInt(@as(u32, @intCast(index)));
            }

            pub fn online(self: *Self, token: Participant) void {
                Impl.online(self, token);
            }

            pub fn offline(self: *Self, token: Participant) void {
                Impl.offline(self, token);
            }

            pub fn quiescent(self: *Self, token: Participant) void {
                Impl.quiescent(self, token);
            }

            /// begins a lifetime barrier for objects retired before this call; generation must not be exhausted
            pub fn beginGracePeriod(self: *Self) GracePeriod {
                return Impl.beginGracePeriod(self);
            }

            pub fn isComplete(self: *const Self, period: GracePeriod) bool {
                return Impl.isComplete(self, period);
            }
        };
    }

    pub const Bounded = struct {
        current: PaddedAtomic,
        slots: []Slot,

        pub const Slot = cache.CachePad(std.atomic.Value(Impl.Word));

        const Self = @This();

        /// slots must remain valid and address-stable during domain use
        pub fn wrap(slots: []Slot) Self {
            std.debug.assert(slots.len > 0);
            std.debug.assert(slots.len - 1 <= std.math.maxInt(u32));

            var self: Self = .{ .current = undefined, .slots = slots };
            Impl.initialize(&self);

            return self;
        }

        pub fn capacity(self: *const Self) usize {
            return self.slots.len;
        }

        pub fn generation(self: *const Self) u64 {
            return self.current.value.load(.acquire);
        }

        pub fn participant(self: *const Self, index: usize) Participant {
            std.debug.assert(index < self.capacity());
            return @enumFromInt(@as(u32, @intCast(index)));
        }

        pub fn online(self: *Self, token: Participant) void {
            Impl.online(self, token);
        }

        pub fn offline(self: *Self, token: Participant) void {
            Impl.offline(self, token);
        }

        pub fn quiescent(self: *Self, token: Participant) void {
            Impl.quiescent(self, token);
        }

        pub fn beginGracePeriod(self: *Self) GracePeriod {
            return Impl.beginGracePeriod(self);
        }

        pub fn isComplete(self: *const Self, period: GracePeriod) bool {
            return Impl.isComplete(self, period);
        }
    };
};

const Impl = struct {
    const Word = packed struct(u64) {
        generation: u63,
        offline: bool,

        const inactive: Word = .{ .generation = 0, .offline = true };
    };

    fn requireCapacity(comptime count: usize) void {
        if (count == 0) {
            @compileError("QSBR Static capacity must be non-zero");
        }
        if (count - 1 > std.math.maxInt(u32)) {
            @compileError("QSBR Static capacity exceeds Participant index range");
        }
    }

    fn initialize(domain: anytype) void {
        domain.current = .{ .value = AtomicWord.init(0) };
        for (domain.slots[0..]) |*slot| {
            slot.* = .{ .value = .init(Word.inactive) };
        }
    }

    fn online(domain: anytype, token: Participant) void {
        const index: usize = token.index();
        std.debug.assert(index < domain.slots.len);

        const current = domain.current.value.load(.acquire);
        domain.slots[index].value.store(.{
            .generation = @intCast(current),
            .offline = false,
        }, .release);
    }

    fn offline(domain: anytype, token: Participant) void {
        const index: usize = token.index();
        std.debug.assert(index < domain.slots.len);
        domain.slots[index].value.store(Word.inactive, .release);
    }

    fn quiescent(domain: anytype, token: Participant) void {
        const index: usize = token.index();
        std.debug.assert(index < domain.slots.len);

        const word = domain.slots[index].value.load(.monotonic);
        std.debug.assert(!word.offline);

        const current = domain.current.value.load(.acquire);
        domain.slots[index].value.store(.{
            .generation = @intCast(current),
            .offline = false,
        }, .release);
    }

    fn beginGracePeriod(domain: anytype) GracePeriod {
        var current = domain.current.value.load(.acquire);
        while (true) {
            std.debug.assert(current < std.math.maxInt(u63));

            const next = current + 1;
            if (domain.current.value.cmpxchgWeak(current, next, .acq_rel, .acquire)) |observed| {
                current = observed;
                continue;
            }

            return @enumFromInt(next);
        }
    }

    fn isComplete(domain: anytype, period: GracePeriod) bool {
        const target = period.generation();
        for (domain.slots[0..]) |*slot| {
            const word = slot.value.load(.acquire);
            if (word.offline) {
                continue;
            }

            if (word.generation < target) {
                return false;
            }
        }
        return true;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "multiple blockers require separate quiescent or offline reports" {
        var domain = Domain.Static(3).init();
        const first = domain.participant(0);
        const second = domain.participant(1);

        const empty = Impl.beginGracePeriod(&domain);

        try testing.expect(Impl.isComplete(&domain, empty));
        try testing.expectEqual(@as(usize, 3), domain.capacity());

        Impl.online(&domain, first);
        Impl.online(&domain, second);
        const period = Impl.beginGracePeriod(&domain);

        try testing.expect(!Impl.isComplete(&domain, period));

        Impl.quiescent(&domain, first);

        try testing.expect(!Impl.isComplete(&domain, period));

        Impl.offline(&domain, second);
        Impl.offline(&domain, second);

        try testing.expect(Impl.isComplete(&domain, period));

        Impl.offline(&domain, first);
        const future = Impl.beginGracePeriod(&domain);

        try testing.expect(Impl.isComplete(&domain, future));
    }

    test "late and repeated online reports do not nest" {
        var domain = Domain.Static(1).init();
        const token = domain.participant(0);

        const earlier = Impl.beginGracePeriod(&domain);
        Impl.online(&domain, token);

        try testing.expect(Impl.isComplete(&domain, earlier));

        const first = Impl.beginGracePeriod(&domain);

        try testing.expect(!Impl.isComplete(&domain, first));

        Impl.online(&domain, token);

        try testing.expect(Impl.isComplete(&domain, first));

        const second = Impl.beginGracePeriod(&domain);

        try testing.expect(!Impl.isComplete(&domain, second));

        Impl.online(&domain, token);
        Impl.offline(&domain, token);
        const future = Impl.beginGracePeriod(&domain);

        try testing.expect(Impl.isComplete(&domain, second));
        try testing.expect(Impl.isComplete(&domain, future));
    }

    test "overlapping periods distinguish reports before and after begin" {
        {
            var domain = Domain.Static(1).init();
            const token = domain.participant(0);

            Impl.online(&domain, token);
            Impl.quiescent(&domain, token);
            const first = Impl.beginGracePeriod(&domain);

            try testing.expect(!Impl.isComplete(&domain, first));

            Impl.quiescent(&domain, token);
            const second = Impl.beginGracePeriod(&domain);

            try testing.expect(Impl.isComplete(&domain, first));
            try testing.expect(!Impl.isComplete(&domain, second));

            Impl.quiescent(&domain, token);

            try testing.expect(Impl.isComplete(&domain, first));
            try testing.expect(Impl.isComplete(&domain, second));
        }

        {
            var domain = Domain.Static(1).init();
            const token = domain.participant(0);

            Impl.online(&domain, token);
            const first = Impl.beginGracePeriod(&domain);
            const second = Impl.beginGracePeriod(&domain);

            try testing.expect(!Impl.isComplete(&domain, first));
            try testing.expect(!Impl.isComplete(&domain, second));

            Impl.quiescent(&domain, token);

            try testing.expect(Impl.isComplete(&domain, first));
            try testing.expect(Impl.isComplete(&domain, second));
        }
    }

    test "borrowed storage reinitialization clears participant progress" {
        var slots: [3]Domain.Bounded.Slot = undefined;
        var domain = Domain.Bounded.wrap(&slots);
        const token = domain.participant(2);

        const empty = domain.beginGracePeriod();

        try testing.expect(domain.isComplete(empty));
        try testing.expectEqual(@as(usize, 3), domain.capacity());

        domain.online(token);
        const blocked = domain.beginGracePeriod();

        try testing.expect(!domain.isComplete(blocked));

        domain = Domain.Bounded.wrap(&slots);
        const reset = domain.beginGracePeriod();

        try testing.expectEqual(@as(u64, 1), reset.generation());
        try testing.expect(domain.isComplete(reset));

        domain.online(token);
        const next = domain.beginGracePeriod();

        try testing.expect(!domain.isComplete(next));

        domain.quiescent(token);

        try testing.expect(domain.isComplete(next));
    }

    test "bounded operation stream matches independent reference state" {
        const participant_count = 3;

        var domain = Domain.Static(participant_count).init();
        var online = [_]bool{false} ** participant_count;
        var reported = [_]u64{0} ** participant_count;
        var periods: [64]GracePeriod = undefined;
        var period_count: usize = 0;
        var model_generation: u64 = 0;
        var prng = std.Random.Xoshiro256.init(0xA51C_0FFE_EE12_3456);

        const random = prng.random();

        for (0..512) |_| {
            const index = random.uintLessThan(usize, participant_count);
            const token = domain.participant(index);
            switch (random.uintLessThan(u8, 5)) {
                0 => {
                    Impl.online(&domain, token);
                    online[index] = true;
                    reported[index] = model_generation;
                },
                1 => {
                    Impl.offline(&domain, token);
                    online[index] = false;
                },
                2 => {
                    if (online[index]) {
                        Impl.quiescent(&domain, token);
                        reported[index] = model_generation;
                    }
                },
                3 => {
                    if (period_count < periods.len) {
                        const period = Impl.beginGracePeriod(&domain);
                        model_generation += 1;
                        periods[period_count] = period;
                        period_count += 1;

                        try testing.expectEqual(model_generation, period.generation());
                    }
                },
                else => {},
            }

            for (periods[0..period_count]) |period| {
                var expected = true;
                for (online, reported) |is_online, generation| {
                    if (is_online and generation < period.generation()) {
                        expected = false;
                        break;
                    }
                }

                try testing.expectEqual(expected, Impl.isComplete(&domain, period));
            }
        }
    }
};
