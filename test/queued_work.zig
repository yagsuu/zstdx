const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Provider = struct {
    value: u32 = 0,
    history: [4]u32 = undefined,
    count: usize = 0,

    pub fn record(self: *@This(), digit: u32) void {
        self.value = self.value * 10 + digit;
        self.history[self.count] = self.value;
        self.count += 1;
    }
};

const Work = struct {
    node: stdx.intrusive.List.SinglyLinkedNode = .{},
    callback: stdx.dispatch.Delegate(fn (u32) void),
    digit: u32,
};

const WorkQueue = stdx.intrusive.Queue(Work, "node");

test "integration: queued delegates execute FIFO against their borrowed provider" {
    var provider: Provider = .{};
    const callback = stdx.dispatch.Delegate(fn (u32) void).bind(Provider, &provider, &Provider.record);

    var work = [_]Work{
        .{ .callback = callback, .digit = 3 },
        .{ .callback = callback, .digit = 1 },
        .{ .callback = callback, .digit = 4 },
    };

    var queue = WorkQueue.init();
    defer queue.clear();

    for (&work) |*item| queue.pushBack(item);

    provider.value = 2;

    while (queue.popFront()) |item| item.callback.call(item.digit);

    try testing.expectEqualSlices(u32, &.{ 23, 231, 2314 }, provider.history[0..provider.count]);
    try testing.expectEqual(@as(u32, 2314), provider.value);
    try testing.expect(queue.isEmpty());

    for (&work) |*item| try testing.expect(item.node.next == null);
}

test "integration: clearing queued work cancels callbacks and permits detached work to be reused" {
    var provider: Provider = .{};
    const callback = stdx.dispatch.Delegate(fn (u32) void).bind(Provider, &provider, &Provider.record);

    var work = [_]Work{
        .{ .callback = callback, .digit = 7 },
        .{ .callback = callback, .digit = 8 },
        .{ .callback = callback, .digit = 9 },
    };

    var queue = WorkQueue.init();
    defer queue.clear();

    for (&work) |*item| queue.pushBack(item);

    const first = queue.popFront().?;
    first.callback.call(first.digit);
    queue.clear();

    try testing.expectEqual(@as(usize, 1), provider.count);
    try testing.expectEqual(@as(u32, 7), provider.value);
    try testing.expect(queue.isEmpty());
    for (&work) |*item| try testing.expect(item.node.next == null);

    queue.pushBack(&work[2]);
    const resumed = queue.popFront().?;
    resumed.callback.call(resumed.digit);

    try testing.expectEqualSlices(u32, &.{ 7, 79 }, provider.history[0..provider.count]);
    try testing.expectEqual(@as(u32, 79), provider.value);
    try testing.expect(queue.isEmpty());
}
