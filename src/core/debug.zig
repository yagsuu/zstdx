//! Comptime mapping from `SafetyMode` to whether a debug check is compiled
//! in. See docs/specs/core/debug.md.

const builtin = @import("builtin");

const options = @import("options.zig");

const SafetyMode = options.SafetyMode;

/// Returns true when the caller's `mode` should compile zstdx's optional
/// safety checks. `.build_mode` enables them in Debug and ReleaseSafe and
/// disables them in ReleaseFast and ReleaseSmall.
pub fn checksEnabled(comptime mode: SafetyMode) bool {
    return switch (mode) {
        .checked => true,
        .unchecked => false,
        .build_mode => switch (builtin.mode) {
            .Debug, .ReleaseSafe => true,
            .ReleaseFast, .ReleaseSmall => false,
        },
    };
}
