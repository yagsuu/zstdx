const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const interrupts = x86.interrupts;

const testing = std.testing;

test "compile: interrupt wrappers instantiate" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn () void, @TypeOf(interrupts.enable)) catch unreachable;
        testing.expectEqual(fn () void, @TypeOf(interrupts.disable)) catch unreachable;
        testing.expectEqual(fn () bool, @TypeOf(interrupts.enabled)) catch unreachable;
    }
}
