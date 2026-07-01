//! Signal contract tests. Spec: docs/specs/sync/signal.md.

const std = @import("std");

const stdx = @import("stdx");

const Signal = stdx.sync.Signal;
const ReadySignal = Signal.Manual(TestBackend);
const testing = std.testing;

const TestBackend = struct {
    wait_calls: usize = 0,
    wake_calls: usize = 0,
    spurious_successes_before_error: usize = 0,
    fail_next_wait: bool = false,

    pub const WaitError = error{Canceled};

    pub fn wait(self: *TestBackend, state: *const Signal.State, observed: Signal.Token) WaitError!void {
        self.wait_calls += 1;
        if (self.fail_next_wait) {
            self.fail_next_wait = false;
            return error.Canceled;
        }
        if (state.changedSince(observed)) return;
        if (self.spurious_successes_before_error > 0) {
            self.spurious_successes_before_error -= 1;
            return;
        }
        return error.Canceled;
    }

    pub fn wakeAll(self: *TestBackend) void {
        self.wake_calls += 1;
    }
};

test "unit: Signal.State initializes tokens for unset and set levels" {
    const unset_state = Signal.State.init(.unset);
    const unset_token = unset_state.observe();
    try testing.expect(!unset_state.isSet());
    try testing.expect(!unset_token.isSet());
    try testing.expect(!unset_state.changedSince(unset_token));

    const set_state = Signal.State.init(.set);
    const set_token = set_state.observe();
    try testing.expect(set_state.isSet());
    try testing.expect(set_token.isSet());
    try testing.expect(!set_state.changedSince(set_token));

    try testing.expect(unset_state.changedSince(set_token));
    try testing.expect(set_state.changedSince(unset_token));
}

test "unit: Signal.Manual set and clear publish level changes without redundant wakes" {
    var signal: ReadySignal = undefined;
    signal.init(.unset, .{});

    const initial = signal.stateRef().observe();
    try testing.expect(!initial.isSet());
    try testing.expect(!signal.isSet());

    signal.set();
    const after_set = signal.stateRef().observe();
    try testing.expect(signal.isSet());
    try testing.expect(after_set.isSet());
    try testing.expect(signal.stateRef().changedSince(initial));
    try testing.expectEqual(@as(usize, 1), signal.backend.wake_calls);

    signal.set();
    try testing.expect(signal.isSet());
    try testing.expect(!signal.stateRef().changedSince(after_set));
    try testing.expectEqual(@as(usize, 1), signal.backend.wake_calls);

    signal.clear();
    const after_clear = signal.stateRef().observe();
    try testing.expect(!signal.isSet());
    try testing.expect(!after_clear.isSet());
    try testing.expect(signal.stateRef().changedSince(after_set));
    try testing.expectEqual(@as(usize, 1), signal.backend.wake_calls);

    signal.clear();
    try testing.expect(!signal.isSet());
    try testing.expect(!signal.stateRef().changedSince(after_clear));
    try testing.expectEqual(@as(usize, 1), signal.backend.wake_calls);
}

test "unit: Signal.wait returns immediately for an already set signal" {
    var signal: ReadySignal = undefined;
    signal.init(.set, .{
        .fail_next_wait = true,
        .spurious_successes_before_error = 2,
    });

    try signal.wait();
    try testing.expect(signal.isSet());
    try testing.expectEqual(@as(usize, 0), signal.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), signal.backend.wake_calls);
}

test "unit: Signal.wait propagates backend errors unchanged while unset" {
    var signal: ReadySignal = undefined;
    signal.init(.unset, .{ .fail_next_wait = true });

    try testing.expectError(error.Canceled, signal.wait());
    try testing.expect(!signal.isSet());
    try testing.expectEqual(@as(usize, 1), signal.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), signal.backend.wake_calls);
}

test "unit: Signal.wait retries spurious backend successes while still unset" {
    var signal: ReadySignal = undefined;
    signal.init(.unset, .{ .spurious_successes_before_error = 2 });

    try testing.expectError(error.Canceled, signal.wait());
    try testing.expect(!signal.isSet());
    try testing.expectEqual(@as(usize, 3), signal.backend.wait_calls);
    try testing.expectEqual(@as(usize, 0), signal.backend.wake_calls);
}

test "unit: Signal backend recheck observes set between token capture and registration" {
    var signal: ReadySignal = undefined;
    signal.init(.unset, .{});

    const observed = signal.stateRef().observe();
    try testing.expect(!observed.isSet());

    signal.set();
    try signal.backend.wait(signal.stateRef(), observed);

    try testing.expect(signal.isSet());
    try testing.expectEqual(@as(usize, 1), signal.backend.wait_calls);
    try testing.expectEqual(@as(usize, 1), signal.backend.wake_calls);
}
