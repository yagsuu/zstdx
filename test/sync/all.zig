comptime {
    _ = @import("signal_test.zig");
    _ = @import("spin_test.zig");
    _ = @import("atomic_cell_test.zig");
    _ = @import("raw_spin_lock_test.zig");
    _ = @import("once_test.zig");
    _ = @import("rendezvous_test.zig");
    _ = @import("latch_test.zig");
}
