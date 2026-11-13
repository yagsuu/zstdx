const std = @import("std");
const bits = @import("bits");

const msr = @import("../msr.zig");

pub const EFER = struct {
    const Fields = bits.BitField(u64, .{
        .syscall_enable = bool,
        ._reserved_1 = .{ .type = u7, .access = .reserved },
        .long_mode_enable = bool,
        ._reserved_9 = .{ .type = bool, .access = .reserved },
        .long_mode_active = .{ .type = bool, .access = .ro },
        .execute_disable_enable = bool,
        .secure_virtual_machine_enable = bool,
        .long_mode_segment_limit_enable = bool,
        .fast_fxsave_fxrstor = bool,
        .translation_cache_extension = bool,
        ._reserved_16 = .{ .type = bool, .access = .reserved },
        ._reserved_19 = .{ .offset = 19, .type = bool, .access = .reserved },
        ._reserved_22 = .{ .offset = 22, .type = u42, .access = .reserved },
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

    pub const Error = error{UnsupportedExecuteDisable};

    /// Privilege: CPL 0.
    pub fn read() Word {
        return from(msr.read(.IA32_EFER));
    }

    /// Privilege: CPL 0.
    /// Ordering: Compiler memory barrier.
    pub fn write(word: Word) void {
        msr.write(.IA32_EFER, raw(word));
    }

    pub fn executeDisableEnabled(word: Word, supported: bool) Error!bool {
        if (word.execute_disable_enable and !supported) {
            return error.UnsupportedExecuteDisable;
        }
        return word.execute_disable_enable;
    }
};

pub const unit = struct {
    const testing = std.testing;

    test "execute-disable capability validation preserves raw bits" {
        const value = EFER.from(0xa5f3_5ca9_3d7e_1c42 | (1 << 11));
        const disabled = EFER.default();

        try testing.expectEqual(@as(u64, 0xa5f3_5ca9_3d7e_1c42 | (1 << 11)), EFER.raw(value));
        try testing.expect(try EFER.executeDisableEnabled(value, true));
        try testing.expectError(error.UnsupportedExecuteDisable, EFER.executeDisableEnabled(value, false));
        try testing.expect(!try EFER.executeDisableEnabled(disabled, false));
    }

    test "EFER defaults and policies preserve read-only reserved and unknown bits" {
        const unnamed: u64 = (3 << 17) | (3 << 20);
        const snapshot = EFER.from(0xa5f3_5ca9_3d7e_1c42);
        const changed = EFER.replace(snapshot, .{ .execute_disable_enable = true });
        const selected = EFER.mask(.execute_disable_enable);

        try testing.expectEqual(@as(u64, 0), EFER.raw(EFER.default()));
        try testing.expectEqual(@as(u64, 0), EFER.encode(.{}));
        try testing.expectEqual(unnamed, EFER.masks.unnamed);
        try testing.expectEqual(@as(u64, 1 << 10) | unnamed, EFER.masks.ro);
        try testing.expectEqual(@as(u64, 0), EFER.masks.assign & (EFER.masks.ro | EFER.masks.reserved | unnamed));
        try testing.expectEqual(EFER.raw(snapshot) & ~selected, EFER.raw(changed) & ~selected);
        try testing.expect(changed.execute_disable_enable);
        try testing.expectEqual(snapshot.long_mode_active, changed.long_mode_active);
    }
};
