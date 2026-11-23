# `stdx.barrier`

`stdx.barrier` orders host memory accesses around device protocols.

## Ordering operations

`stdx.barrier.compiler()` constrains compiler reordering of memory accesses across
the call. It emits no hardware instruction and supplies no CPU or device ordering.

All MMIO and DMA operations also constrain compiler reordering across the call.
Prior and subsequent accesses refer to program order on the calling CPU.

| Operations | CPU ordering on x86_64 | Instruction |
| --- | --- | --- |
| `stdx.barrier.mmio.release()`, `stdx.barrier.dma.release()` | Prior stores before subsequent stores | `sfence` |
| `stdx.barrier.mmio.acquire()`, `stdx.barrier.dma.acquire()` | Prior loads before subsequent loads | `lfence` |
| `stdx.barrier.mmio.full()`, `stdx.barrier.dma.full()` | Prior loads and stores before subsequent loads and stores | `mfence` |

## Device protocols

| Operation | Placement |
| --- | --- |
| `stdx.barrier.mmio.release()` | After related host stores, before the notifying MMIO store |
| `stdx.barrier.mmio.acquire()` | After the MMIO availability load, before reading related memory |
| `stdx.barrier.dma.release()` | After DMA-visible data writes, before the publishing store |
| `stdx.barrier.dma.acquire()` | After the DMA-written availability load, before reading related data |
| `stdx.barrier.mmio.full()`, `stdx.barrier.dma.full()` | Between mixed accesses requiring both ordering directions |

The caller's device protocol MUST define the publication or availability state
and ensure that the device observes publication. The caller owns DMA mappings,
buffer lifetime, ownership transfers, and notification. DMA mappings MUST be
coherent, or the caller MUST perform required cache maintenance at ownership
boundaries. Obtain device completion before reusing or releasing device-owned
resources.

Use the owning synchronization primitive's publication and acquisition protocol
for shared host payloads.

## Availability and execution

`stdx.barrier.compiler()` is target-independent. MMIO and DMA operations require
an x86_64 target. Calling one on another target causes a compile error.
Importing `stdx.barrier` remains portable.

Operations are unprivileged, reentrant, and allocation-free. Hardware fences
can delay execution until their ordering requirements are satisfied.

## References

- [Barrier exports](../../src/barrier/module.zig)
- [Compiler barrier](../../src/barrier/compiler.zig)
- [MMIO barriers](../../src/barrier/mmio.zig)
- [DMA barriers](../../src/barrier/dma.zig)
