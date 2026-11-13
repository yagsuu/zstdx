//! delegates, inline closures, and borrowed interfaces

pub const delegate = @import("delegate.zig");
pub const closure = @import("closure.zig");
pub const interface = @import("interface.zig");

pub const Delegate = delegate.Delegate;
pub const Closure = closure.Closure;
pub const Interface = interface.Interface;

test {
    _ = @import("thunk.zig").unit;
    _ = delegate.unit;
    _ = closure.unit;
    _ = interface.unit;
}
