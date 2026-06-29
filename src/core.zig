//! Core primitives. See docs/specs/core/options.md,
//! docs/specs/core/debug.md, and docs/specs/core/range.md.

pub const debug = @import("core/debug.zig");

pub const SafetyMode = @import("core/options.zig").SafetyMode;
pub const Range = @import("core/range.zig").Range;
