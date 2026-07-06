//! Closure inline-storage tests. Spec: docs/specs/func/callback.md.

const std = @import("std");

const stdx = @import("stdx");

const testing = std.testing;

const Callback = stdx.func.Callback;
const Closure = stdx.func.Closure;

const Retry = struct {
    attempts: u32,
    seen: u32,

    pub fn record(self: *Retry, x: u32) void {
        self.seen = x;
        self.attempts += 1;
    }

    pub fn combine(self: *Retry, a: u32, b: u32) u32 {
        self.attempts += 1;
        return self.seen + a + b;
    }
};

fn recordState(self: *Retry, x: u32) void {
    self.record(x);
}

fn combineState(self: *Retry, a: u32, b: u32) u32 {
    return self.combine(a, b);
}

fn zeroArgTick(self: *Retry) void {
    self.attempts += 1;
}

test "unit: Closure size equals aligned capacity plus invoke word" {
    const C = Closure(fn () void, 16);
    const expected = (try stdx.mem.alignUp(usize, 16, @alignOf(usize))) + @sizeOf(usize);
    try testing.expectEqual(expected, @sizeOf(C));
}

test "unit: Closure aligns capacity that is not a multiple of usize" {
    const C = Closure(fn () void, 5);
    const expected = (try stdx.mem.alignUp(usize, 5, @alignOf(usize))) + @sizeOf(usize);
    try testing.expectEqual(expected, @sizeOf(C));
}

test "unit: init bit-copies state into inline storage" {
    var c: Closure(fn (u32) void, 16) = .init(
        Retry,
        .{ .attempts = 3, .seen = 0 },
        &recordState,
    );

    const stored: *Retry = @ptrCast(@alignCast(&c.storage));
    try testing.expectEqual(@as(u32, 3), stored.attempts);
    try testing.expectEqual(@as(u32, 0), stored.seen);
}

test "unit: mutating caller state after init does not affect the closure" {
    var seed: Retry = .{ .attempts = 5, .seen = 0 };
    var c: Closure(fn (u32) void, 16) = .init(Retry, seed, &recordState);

    seed.attempts = 999;
    seed.seen = 999;

    const stored: *Retry = @ptrCast(@alignCast(&c.storage));
    try testing.expectEqual(@as(u32, 5), stored.attempts);
    try testing.expectEqual(@as(u32, 0), stored.seen);
}

test "unit: callback() reaches the callee with the closure's stored state" {
    var c: Closure(fn (u32) void, 16) = .init(
        Retry,
        .{ .attempts = 0, .seen = 0 },
        &recordState,
    );

    const cb: Callback(fn (u32) void) = c.callback();
    cb.call(.{42});

    const stored: *Retry = @ptrCast(@alignCast(&c.storage));
    try testing.expectEqual(@as(u32, 42), stored.seen);
    try testing.expectEqual(@as(u32, 1), stored.attempts);
}

test "unit: callback() context equals the closure's storage address" {
    var c: Closure(fn (u32) void, 16) = .init(
        Retry,
        .{ .attempts = 0, .seen = 0 },
        &recordState,
    );

    const cb: Callback(fn (u32) void) = c.callback();
    try testing.expectEqual(
        @as(?*anyopaque, @ptrCast(&c.storage)),
        cb.context,
    );
}

test "unit: multi-argument callback dispatches state and args correctly" {
    var c: Closure(fn (u32, u32) u32, 16) = .init(
        Retry,
        .{ .attempts = 0, .seen = 100 },
        &combineState,
    );

    const cb: Callback(fn (u32, u32) u32) = c.callback();

    try testing.expectEqual(@as(u32, 100 + 1 + 2), cb.call(.{ 1, 2 }));
    try testing.expectEqual(@as(u32, 100 + 3 + 4), cb.call(.{ 3, 4 }));

    const stored: *Retry = @ptrCast(@alignCast(&c.storage));
    try testing.expectEqual(@as(u32, 2), stored.attempts);
}

test "unit: zero-extra-arg closure dispatches through call(.{})" {
    var c: Closure(fn () void, 16) = .init(
        Retry,
        .{ .attempts = 0, .seen = 0 },
        &zeroArgTick,
    );

    const cb: Callback(fn () void) = c.callback();
    cb.call(.{});
    cb.call(.{});

    const stored: *Retry = @ptrCast(@alignCast(&c.storage));
    try testing.expectEqual(@as(u32, 2), stored.attempts);
}

test "unit: closure stored in a heap slot retains callback stability" {
    // The spec calls out that callback() borrows storage; a Closure kept
    // at a stable heap address produces a durable Callback.
    const gpa = testing.allocator;
    const slot = try gpa.create(Closure(fn (u32) void, 16));
    defer gpa.destroy(slot);

    slot.* = .init(Retry, .{ .attempts = 0, .seen = 0 }, &recordState);
    const cb = slot.callback();
    cb.call(.{7});

    const stored: *Retry = @ptrCast(@alignCast(&slot.storage));
    try testing.expectEqual(@as(u32, 7), stored.seen);
}

// Compile-only rejections — enforced by `Closure(Fn, N).init` inside
// `src/func/closure.zig`. The following invariants are trapped by the
// source:
//
//   Closure(Fn, N).init(State, state, fn_ptr) traps when:
//     - @sizeOf(State) > N
//     - @alignOf(State) > alignment (currently @alignOf(usize))
//     - fn_ptr's type is not a pointer to a function whose signature
//       equals `Fn` with `*State` prepended as the first parameter.

test "unit: Closure compiles and executes on the host regardless of arch" {
    var c: Closure(fn () void, 16) = .init(
        Retry,
        .{ .attempts = 0, .seen = 0 },
        &zeroArgTick,
    );
    const cb = c.callback();
    cb.call(.{});
}
