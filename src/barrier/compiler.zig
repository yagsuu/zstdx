/// constrains compiler reordering of memory accesses; emits no hardware fence.
pub inline fn compiler() void {
    asm volatile ("" ::: .{ .memory = true });
}
