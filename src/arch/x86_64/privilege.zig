const target = @import("target.zig");
const CS = @import("register/segment.zig").CS;

/// the RPL of the current CS selector is the architectural CPL.
pub fn currentLevel() u2 {
    comptime target.require();
    return CS.read().rpl;
}
