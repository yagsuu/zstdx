//! x86_64 paging address types and linear-address operations.

const addr = @import("addr");
const bits = @import("bits");
const table = @import("table.zig");

pub const PhysAddr = addr.PhysAddr;
pub const Phys4K = addr.Page(PhysAddr, addr.pages._4kib);
pub const Phys2M = addr.Page(PhysAddr, addr.pages._2mib);
pub const Phys1G = addr.Page(PhysAddr, addr.pages._1gib);

const Index = table.Index;
const Level = table.Level;

pub const Mode = enum {
    level4,
    level5,

    pub fn rootLevel(self: Mode) Level {
        return switch (self) {
            .level4 => .pml4,
            .level5 => .pml5,
        };
    }

    pub fn linearBits(self: Mode) u8 {
        return switch (self) {
            .level4 => 48,
            .level5 => 57,
        };
    }
};

pub const LinearAddr = enum(u64) {
    _,

    pub const Error = error{NonCanonical};

    pub fn from(value: u64) LinearAddr {
        return @enumFromInt(value);
    }

    pub fn raw(self: LinearAddr) u64 {
        return @intFromEnum(self);
    }

    pub fn fromCanonical(value: u64, mode: Mode) Error!LinearAddr {
        const address = from(value);
        if (!address.isCanonical(mode)) {
            return error.NonCanonical;
        }
        return address;
    }

    pub fn signExtend(value: u64, mode: Mode) LinearAddr {
        const linear_bits: u6 = @intCast(mode.linearBits());
        const sign_bit = bits.mask.single(u64, linear_bits - 1);
        const low_mask = bits.mask.low(u64, linear_bits);
        const low_bits = value & low_mask;

        if ((low_bits & sign_bit) != 0) {
            return from(low_bits | ~low_mask);
        }

        return from(low_bits);
    }

    pub fn isCanonical(self: LinearAddr, mode: Mode) bool {
        return signExtend(self.raw(), mode) == self;
    }

    pub fn index(self: LinearAddr, level: Level) Index {
        return Index.from(@truncate(self.raw() >> level.shift()));
    }
};

pub const unit = struct {
    test "canonical addresses and indices distinguish four and five levels" {
        const testing = @import("std").testing;
        const cases = [_]struct { mode: Mode, low: u64, high: u64, invalid: u64 }{
            .{
                .mode = .level4,
                .low = 0x0000_7fff_ffff_ffff,
                .high = 0xffff_8000_0000_0000,
                .invalid = 0x0000_8000_0000_0000,
            },
            .{
                .mode = .level5,
                .low = 0x00ff_ffff_ffff_ffff,
                .high = 0xff00_0000_0000_0000,
                .invalid = 0x0100_0000_0000_0000,
            },
        };

        for (cases) |case| {
            const low = try LinearAddr.fromCanonical(case.low, case.mode);
            const high = try LinearAddr.fromCanonical(case.high, case.mode);

            try testing.expect(low.isCanonical(case.mode));
            try testing.expectEqual(@as(u9, 256), high.index(case.mode.rootLevel()).raw());
            try testing.expectError(error.NonCanonical, LinearAddr.fromCanonical(case.invalid, case.mode));
            try testing.expectEqual(case.high | 1, LinearAddr.signExtend(case.invalid | 1, case.mode).raw());
        }

        const levels = [_]Level{ .pt, .pd, .pdpt, .pml4, .pml5 };
        const expected = [_]u9{ 0x11, 0x22, 0x33, 0x44, 0x55 };
        var raw_address: u64 = 0xabc;
        for (levels, expected) |level, value| {
            raw_address |= @as(u64, value) << level.shift();
        }

        const linear = try LinearAddr.fromCanonical(raw_address, .level5);

        for (levels, expected) |level, value| {
            try testing.expectEqual(value, linear.index(level).raw());
        }
        try testing.expect(!linear.isCanonical(.level4));
    }
};
