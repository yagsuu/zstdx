//! Core option contract tests. Spec: docs/specs/core/options.md.

const std = @import("std");

const stdx = @import("stdx");

const SafetyMode = stdx.core.SafetyMode;

const testing = std.testing;

test "unit: SafetyMode exports the three approved modes" {
    try testing.expectEqual(SafetyMode.build_mode, .build_mode);
    try testing.expectEqual(SafetyMode.checked, .checked);
    try testing.expectEqual(SafetyMode.unchecked, .unchecked);
}
