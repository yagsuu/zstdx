//! Optional build-mode checks.

const builtin = @import("builtin");

/// Enables optional checks in Debug and ReleaseSafe.
pub fn checksEnabled() bool {
    return switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}
