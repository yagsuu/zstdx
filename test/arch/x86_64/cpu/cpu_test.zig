const std = @import("std");
const x86 = @import("stdx").arch.x86_64;
const cpu = x86.cpu;

const testing = std.testing;

test "compile: CPU halt and pause instantiate" {
    if (!x86.supported) return;
    comptime {
        testing.expectEqual(fn () void, @TypeOf(cpu.halt)) catch unreachable;
        testing.expectEqual(fn () void, @TypeOf(cpu.pause)) catch unreachable;
    }
}

test "host: cpu.pause executes once" {
    if (!x86.supported) return;
    cpu.pause();
}
