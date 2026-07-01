//! Compiler-only reorder barrier. See docs/specs/barrier/dma.md.

/// Empty inline assembly with a `memory` clobber. Emits no ISA instruction but
/// prevents the compiler from reordering memory accesses across the call.
pub inline fn compiler() void {
    asm volatile ("" ::: .{ .memory = true });
}
