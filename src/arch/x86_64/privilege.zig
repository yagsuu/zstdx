const target = @import("target.zig");

const CS = @import("register/segment.zig").CS;

pub fn currentLevel() u2 {
    comptime target.require();
    return CS.read().rpl;
}

pub const unit = struct {
    const testing = @import("std").testing;

    test "unit: host user mode reports privilege level three" {
        if (!target.supported) {
            return error.SkipZigTest;
        }

        try testing.expectEqual(@as(u2, 3), currentLevel());
    }
};
