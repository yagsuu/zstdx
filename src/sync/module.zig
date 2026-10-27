//! synchronization primitives

pub const latch = @import("latch.zig");
pub const once = @import("once.zig");
pub const raw_spin_lock = @import("raw_spin_lock.zig");
pub const rendezvous = @import("rendezvous.zig");
pub const signal = @import("signal.zig");
pub const spin = @import("backend/spin.zig");

pub const Latch = latch.Latch;
pub const Once = once.Once;
pub const RawSpinLock = raw_spin_lock.RawSpinLock;
pub const Rendezvous = rendezvous.Rendezvous;
pub const Signal = signal.Signal;

test {
    _ = signal.unit;
    _ = once.unit;
    _ = latch.unit;
    _ = raw_spin_lock.unit;
    _ = rendezvous.unit;
}
