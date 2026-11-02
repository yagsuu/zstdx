pub const mmio = @import("mmio.zig");
pub const poll = @import("poll.zig");

pub const Mmio = mmio.Mmio;

test {
    _ = mmio.unit;
    _ = poll.unit;
}
