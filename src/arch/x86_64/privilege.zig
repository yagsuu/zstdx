const target = @import("target.zig");
const CS = @import("register/segment.zig").CS;

/// The current CS selector's RPL is the architectural CPL.
pub fn currentLevel() u2 {
    comptime target.require();
    return CS.read().rpl;
}
