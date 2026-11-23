# `stdx.barrier`

| Operation | Contract |
| --- | --- |
| `stdx.barrier.compiler()` | Constrains compiler reordering of memory accesses across the call. |
| `stdx.barrier.mmio.*()` | Orders accesses for MMIO protocols; see [ordering operations](barrier/dma.md). |
| `stdx.barrier.dma.*()` | Orders accesses for DMA protocols; see [ordering operations](barrier/dma.md). |

Use the owning synchronization primitive for host-thread publication and
acquisition. Device protocols define notification and completion requirements.

## References

- [Barrier exports](../../src/barrier/module.zig)
