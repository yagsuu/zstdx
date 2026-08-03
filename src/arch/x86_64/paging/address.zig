//! x86_64 paging address types and linear-address operations.

const std = @import("std");

const addr = @import("../../../addr.zig");
const bits = @import("../../../bits.zig");
const table = @import("table.zig");

pub const PhysAddr = addr.PhysAddr;
pub const Phys4K = addr.Page(PhysAddr, addr.pages._4kib);
pub const Phys2M = addr.Page(PhysAddr, addr.pages._2mib);
pub const Phys1G = addr.Page(PhysAddr, addr.pages._1gib);

const Index = table.Index;
const Indices = table.Indices;
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

pub const LinearAddress = enum(u64) {
    _,

    pub const Error = error{NonCanonical};

    pub fn fromInt(raw_address: u64) LinearAddress {
        return @enumFromInt(raw_address);
    }

    pub fn raw(self: LinearAddress) u64 {
        return @intFromEnum(self);
    }

    pub fn fromCanonical(raw_address: u64, mode: Mode) Error!LinearAddress {
        const address = fromInt(raw_address);
        if (!address.isCanonical(mode)) return error.NonCanonical;
        return address;
    }

    pub fn signExtend(raw_address: u64, mode: Mode) LinearAddress {
        const linear_bits: u6 = @intCast(mode.linearBits());
        const sign_bit = bits.mask.single(u64, linear_bits - 1);
        const low_mask = bits.mask.low(u64, linear_bits);
        const low_bits = raw_address & low_mask;

        if ((low_bits & sign_bit) != 0) return fromInt(low_bits | ~low_mask);

        return fromInt(low_bits);
    }

    pub fn isCanonical(self: LinearAddress, mode: Mode) bool {
        return signExtend(self.raw(), mode) == self;
    }

    pub fn indices(self: LinearAddress, mode: Mode) Indices {
        std.debug.assert(self.isCanonical(mode));
        return .{
            .pml5 = if (mode == .level5) self.indexAt(.pml5) else Index.fromInt(0),
            .pml4 = self.indexAt(.pml4),
            .pdpt = self.indexAt(.pdpt),
            .pd = self.indexAt(.pd),
            .pt = self.indexAt(.pt),
        };
    }

    fn indexAt(self: LinearAddress, level: Level) Index {
        return Index.fromInt(@truncate(self.raw() >> level.indexShift()));
    }
};
