//! Default host test suite aggregate. Spec: docs/specs/architecture.md.

comptime {
    _ = @import("public_exports_test.zig");
    _ = @import("core/options_test.zig");
    _ = @import("core/debug_test.zig");
    _ = @import("core/range_test.zig");
    _ = @import("core/traits_test.zig");
    _ = @import("bits/power_of_two_test.zig");
    _ = @import("bits/set_test.zig");
    _ = @import("mem/alignment_test.zig");
    _ = @import("mem/fixed_buffer_arena_test.zig");
    _ = @import("addr/address_test.zig");
    _ = @import("addr/pages_test.zig");
    _ = @import("ranges/set_test.zig");
    _ = @import("ranges/map_test.zig");
    _ = @import("layout/endian_test.zig");
    _ = @import("bytes/unaligned_test.zig");
    _ = @import("bytes/access_test.zig");
    _ = @import("bytes/cursor_test.zig");
    _ = @import("collections/list_test.zig");
    _ = @import("collections/ring_test.zig");
    _ = @import("intrusive/list_test.zig");
    _ = @import("intrusive/queue_test.zig");
    _ = @import("intrusive/stack_test.zig");
}
