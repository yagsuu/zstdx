const std = @import("std");
const bits = @import("bits");
const target = @import("../target.zig");

pub const RFLAGS = struct {
    const Fields = bits.BitField(u64, .{
        .carry = bool,
        .fixed_one = .{ .type = bool, .access = .reserved, .default = true },
        .parity = bool,
        ._reserved_3 = .{ .type = bool, .access = .reserved },
        .auxiliary_carry = bool,
        ._reserved_5 = .{ .type = bool, .access = .reserved },
        .zero = bool,
        .sign = bool,
        .trap = bool,
        .interrupt_enable = bool,
        .direction = bool,
        .overflow = bool,
        .iopl = u2,
        .nested_task = bool,
        ._reserved_15 = .{ .type = bool, .access = .reserved },
        .resume_flag = bool,
        .virtual_8086 = bool,
        .alignment_check = bool,
        .virtual_interrupt = bool,
        .virtual_interrupt_pending = bool,
        .id = bool,
        ._reserved_22 = .{ .type = u42, .access = .reserved },
    });

    pub const __StdxBitField = Fields.Metadata;

    pub const Int = Fields.Int;
    pub const Word = Fields.Word;

    pub const masks = Fields.masks;

    pub const default = Fields.default;
    pub const init = Fields.init;
    pub const from = Fields.from;
    pub const raw = Fields.raw;
    pub const encode = Fields.encode;
    pub const replace = Fields.replace;
    pub const mask = Fields.mask;

    pub fn read() Word {
        comptime target.require();
        return from(asm volatile (
            \\pushfq
            \\popq %[ret]
            : [ret] "=r" (-> u64),
        ));
    }

    /// Effects: Bits that the current CPL cannot modify remain unchanged.
    pub fn write(word: Word) void {
        comptime target.require();
        asm volatile (
            \\pushq %[v]
            \\popfq
            :
            : [v] "r" (raw(word)),
            : .{ .memory = true, .cc = true });
    }
};

pub const unit = struct {
    test "RFLAGS preserves raw bits and encodes architectural flags" {
        const testing = std.testing;

        const value = RFLAGS.from(0xa5f3_5ca9_3d7e_1c42);
        const interrupt = RFLAGS.from(1 << 9);

        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42), RFLAGS.raw(value));
        try testing.expect(interrupt.interrupt_enable);
        try testing.expectEqual(@as(u2, 3), RFLAGS.from(3 << 12).iopl);
    }

    test "RFLAGS defaults and replacement preserve fixed and reserved bits" {
        const testing = std.testing;

        const initial = RFLAGS.default();
        const snapshot = RFLAGS.from(0xa5f3_5ca9_3d7e_1c40);
        const changed = RFLAGS.replace(snapshot, .{ .interrupt_enable = true, .iopl = 3 });
        const selected = RFLAGS.mask(.{ .interrupt_enable, .iopl });

        try testing.expectEqual(@as(u64, 2), RFLAGS.raw(initial));
        try testing.expect(initial.fixed_one);
        try testing.expectEqual(@as(u64, 2), RFLAGS.encode(.{}));
        try testing.expectEqual(@as(u64, 0), RFLAGS.masks.unnamed);
        try testing.expectEqual(RFLAGS.mask(.fixed_one), RFLAGS.masks.reserved & 2);
        try testing.expectEqual(RFLAGS.raw(snapshot) & ~selected, RFLAGS.raw(changed) & ~selected);
        try testing.expect(changed.interrupt_enable);
        try testing.expectEqual(@as(u2, 3), changed.iopl);
        try testing.expect(!changed.fixed_one);
    }
};
