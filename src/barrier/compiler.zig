//! Compiler-only reorder barrier. See `docs/specs/barrier/dma.md`.

/// Uses empty inline assembly with a `memory` clobber. It emits no ISA
/// instruction but prevents the compiler from reordering memory accesses
/// across the call.
pub inline fn compiler() void {
    asm volatile ("" ::: .{ .memory = true });
}
