comptime {
    _ = @import("target_test.zig");
    _ = @import("port_test.zig");
    _ = @import("msr_test.zig");
    _ = @import("interrupts_test.zig");
    _ = @import("privilege_test.zig");
    _ = @import("fence_test.zig");
    _ = @import("cache_test.zig");
}
