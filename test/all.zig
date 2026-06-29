//! Default host test suite aggregate. Spec: docs/specs/architecture.md.

comptime {
    _ = @import("core/options_test.zig");
    _ = @import("core/debug_test.zig");
    _ = @import("core/range_test.zig");
}
