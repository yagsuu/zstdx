//! Shared safety-mode vocabulary used by stdx primitives.
//! See `docs/specs/core/options.md`.

/// Selects whether an operation compiles optional stdx safety checks.
/// `build_mode` defers to `builtin.mode`; `checked` and `unchecked` force
/// the result regardless of build mode.
pub const SafetyMode = enum {
    build_mode,
    checked,
    unchecked,
};
