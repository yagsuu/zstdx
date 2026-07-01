//! Default host test suite aggregate. Spec: docs/specs/architecture.md.

comptime {
    _ = @import("sync/signal_test.zig");
    _ = @import("concurrent/mpsc_ring_test.zig");
    _ = @import("core/options_test.zig");
    _ = @import("core/debug_test.zig");
    _ = @import("core/range_test.zig");
    _ = @import("core/traits_test.zig");
    _ = @import("bits/power_of_two_test.zig");
    _ = @import("bits/set_test.zig");
    _ = @import("mem/alignment_test.zig");
    _ = @import("mem/arena_test.zig");
    _ = @import("mem/pool_test.zig");
    _ = @import("mem/bitmap_test.zig");
    _ = @import("algo/allocation_test.zig");
    _ = @import("tags/tag_test.zig");
    _ = @import("tags/allocator_test.zig");
    _ = @import("arch/x86_64_test.zig");
    _ = @import("diag/diagnostic_test.zig");
    _ = @import("addr/address_test.zig");
    _ = @import("addr/pages_test.zig");
    _ = @import("ranges/set_test.zig");
    _ = @import("ranges/map_test.zig");
    _ = @import("graph/forest_test.zig");
    _ = @import("layout/endian_test.zig");
    _ = @import("bytes/unaligned_test.zig");
    _ = @import("bytes/access_test.zig");
    _ = @import("bytes/cursor_test.zig");
    _ = @import("collections/list_test.zig");
    _ = @import("collections/ring_test.zig");
    _ = @import("intrusive/list_test.zig");
    _ = @import("intrusive/queue_test.zig");
    _ = @import("intrusive/stack_test.zig");
    _ = @import("barrier/compiler_test.zig");
    _ = @import("barrier/mmio_test.zig");
    _ = @import("barrier/dma_test.zig");
    _ = @import("io/mmio_test.zig");
    _ = @import("time/monotonic_test.zig");
}
