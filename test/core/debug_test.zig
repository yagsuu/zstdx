//! Debug policy contract tests. Spec: docs/specs/core/debug.md.

const std = @import("std");
const builtin = @import("builtin");

const stdx = @import("stdx");

const debug = stdx.core.debug;

const testing = std.testing;

test "unit: checksEnabled forces on for checked and off for unchecked" {
    try testing.expect(debug.checksEnabled(.checked));
    try testing.expect(!debug.checksEnabled(.unchecked));
}

test "unit: checksEnabled tracks builtin.mode for build_mode" {
    const expected = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    try testing.expectEqual(expected, debug.checksEnabled(.build_mode));
}
