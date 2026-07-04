//! Tests for `stdx.sync.spin.Backend`. Spec: docs/specs/sync/spin.md.

const std = @import("std");
const testing = std.testing;
const stdx = @import("stdx");
const sync = stdx.sync;

test "contract: module compiles" {
    // `sync.spin` reaches only `std.atomic.spinLoopHint`, which is
    // target-agnostic; the mere fact that this test file compiles on the
    // host proves the module compiles here. Same reasoning applies on
    // every supported target.
    _ = sync.spin;
}

test "unit: Backend is zero-sized" {
    try testing.expectEqual(@as(usize, 0), @sizeOf(sync.spin.Backend));
}

test "contract: WaitError is error{}" {
    comptime std.debug.assert(sync.spin.Backend.WaitError == error{});
    try testing.expectEqual(
        @as(usize, 0),
        @typeInfo(sync.spin.Backend.WaitError).error_set.?.len,
    );
}

test "unit: wait returns without error" {
    var backend: sync.spin.Backend = .{};
    const dummy_state: u32 = 0xdead_beef;
    const dummy_observed: u64 = 0x1234_5678_9abc_def0;
    try backend.wait(&dummy_state, dummy_observed);

    // Also exercise an arbitrary struct pointee and a non-integer
    // observed value to prove the parameters really are ignored.
    const OtherState = struct { a: u8, b: u16 };
    const other_state: OtherState = .{ .a = 1, .b = 2 };
    const other_observed = enum(u8) { alpha, beta }.beta;
    try backend.wait(&other_state, other_observed);
}

test "unit: wakeAll returns" {
    var backend: sync.spin.Backend = .{};
    const dummy_state: u32 = 42;
    backend.wakeAll(&dummy_state);

    // Second call is idempotent and equally safe.
    backend.wakeAll(&dummy_state);
}

test "contract: Signal.Manual instantiates against spin.Backend" {
    comptime {
        _ = sync.Signal.Manual(sync.spin.Backend);
    }

    // Also confirm runtime `init` + `wait` + `set` compose end-to-end.
    var signal: sync.Signal.Manual(sync.spin.Backend) =
        .init(.set, sync.spin.Backend{});
    try signal.wait();
    try testing.expect(signal.isSet());
    signal.clear();
    try testing.expect(!signal.isSet());
    signal.set();
    try signal.wait();
}
