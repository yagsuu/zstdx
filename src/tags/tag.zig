//! Strongly typed tag values for tag allocator domains. See `docs/specs/tags/allocator.md`.

const std = @import("std");

pub fn Tag(comptime DomainT: type, comptime IntT: type) type {
    comptime requireUnsignedInt(IntT);
    return enum(IntT) {
        _,

        const Self = @This();

        pub const Domain = DomainT;
        pub const Int = IntT;

        pub fn fromInt(value: IntT) Self {
            return @enumFromInt(value);
        }

        pub fn raw(self: Self) IntT {
            return @intFromEnum(self);
        }
    };
}

fn requireUnsignedInt(comptime Int: type) void {
    const info = @typeInfo(Int);

    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Tag Int parameter must be an unsigned integer (u1..u64)");
    }

    if (info.int.bits == 0 or info.int.bits > 64) {
        @compileError("Tag Int parameter must have width u1 through u64");
    }
}

pub const unit = struct {
    const DomainA = struct {};
    const DomainB = struct {};

    test "raw values round-trip" {
        const T = Tag(DomainA, u16);

        try std.testing.expectEqual(@as(u16, 0), T.fromInt(0).raw());
        try std.testing.expectEqual(@as(u16, 0x4321), T.fromInt(0x4321).raw());
        try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), T.fromInt(std.math.maxInt(u16)).raw());
        try std.testing.expectEqual(@as(u1, 0), Tag(DomainA, u1).fromInt(0).raw());
        try std.testing.expectEqual(@as(u1, 1), Tag(DomainA, u1).fromInt(1).raw());
        try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), Tag(DomainA, u64).fromInt(std.math.maxInt(u64)).raw());
    }

    test "type identity" {
        comptime {
            std.debug.assert(Tag(DomainA, u16) != Tag(DomainB, u16));
            std.debug.assert(Tag(DomainA, u16) != Tag(DomainA, u32));
            std.debug.assert(Tag(DomainA, u16) == Tag(DomainA, u16));
        }
    }
};
