//! callbacks and inline closures

pub const callback = @import("callback.zig");
pub const closure = @import("closure.zig");

pub const Callback = callback.Callback;
pub const Closure = closure.Closure;

test {
    _ = @import("impl.zig").unit;
    _ = callback.unit;
    _ = closure.unit;
}
