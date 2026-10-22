//! Runtime-erased callback and inline closure primitives. See `docs/specs/func/callback.md`.

pub const callback = @import("callback.zig");
pub const closure = @import("closure.zig");

pub const Callback = callback.Callback;
pub const Closure = closure.Closure;
