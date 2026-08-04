//! Runtime-erased callback and inline closure primitives. See `docs/specs/func/callback.md`.

pub const callback = @import("func/callback.zig");
pub const closure = @import("func/closure.zig");

pub const Callback = callback.Callback;
pub const Closure = closure.Closure;
