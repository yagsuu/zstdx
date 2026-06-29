//! Shared safety-mode vocabulary used by zstdx primitives. See
//! docs/specs/core/options.md.

/// Selects whether zstdx optional safety checks are compiled into an
/// operation. `build_mode` defers to `builtin.mode`; `checked`/`unchecked`
/// force the answer regardless of build mode.
pub const SafetyMode = enum {
    build_mode,
    checked,
    unchecked,
};
