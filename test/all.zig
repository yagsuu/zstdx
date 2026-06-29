//! Default host test suite aggregate. Spec: docs/specs/architecture.md.

comptime {
    _ = @import("core/options_test.zig");
    _ = @import("core/debug_test.zig");
    _ = @import("core/range_test.zig");
    _ = @import("bits/power_of_two_test.zig");
    _ = @import("bits/set_test.zig");
    _ = @import("mem/alignment_test.zig");
    _ = @import("mem/fixed_buffer_arena_test.zig");
}
