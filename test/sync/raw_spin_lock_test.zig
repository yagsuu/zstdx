//! threaded tests for `stdx.sync.RawSpinLock`

const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");

const RawSpinLock = stdx.sync.RawSpinLock;
const testing = std.testing;

test "contending threads preserve lock-protected counter updates" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Context = struct {
        lock: RawSpinLock = .init(),
        counter: u64 = 0,

        fn run(self: *@This()) void {
            for (0..2_500) |_| {
                self.lock.acquire();
                self.counter += 1;
                self.lock.release();
            }
        }
    };

    var context: Context = .{};
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    context.lock.acquire();
    while (started < threads.len) : (started += 1) {
        threads[started] = std.Thread.spawn(.{}, Context.run, .{&context}) catch |err| {
            context.lock.release();
            for (threads[0..started]) |thread| {
                thread.join();
            }
            return err;
        };
    }
    context.lock.release();
    for (threads) |thread| {
        thread.join();
    }

    try testing.expectEqual(@as(u64, 10_000), context.counter);
    try testing.expect(!context.lock.isLocked());
}

test "release and acquire publish an ordinary paired payload" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const Context = struct {
        lock: RawSpinLock = .init(),
        payload: [2]u64 = .{ 0, 0 },
        ready: bool = false,
        observed: [2]u64 = .{ 0, 0 },

        fn writer(self: *@This()) void {
            self.lock.acquire();
            self.payload = .{ 0xC0FFEE_1234_5678, 0x1234_5678_C0FFEE };
            self.ready = true;
            self.lock.release();
        }

        fn reader(self: *@This()) void {
            while (true) {
                self.lock.acquire();
                if (self.ready) {
                    self.observed = self.payload;
                    self.lock.release();
                    return;
                }
                self.lock.release();
                std.atomic.spinLoopHint();
            }
        }
    };

    for (0..32) |_| {
        var context: Context = .{};
        const writer = try std.Thread.spawn(.{}, Context.writer, .{&context});
        const reader = std.Thread.spawn(.{}, Context.reader, .{&context}) catch |err| {
            writer.join();
            return err;
        };
        writer.join();
        reader.join();

        try testing.expectEqual([2]u64{ 0xC0FFEE_1234_5678, 0x1234_5678_C0FFEE }, context.observed);
        try testing.expect(!context.lock.isLocked());
    }
}
