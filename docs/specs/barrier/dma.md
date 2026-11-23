# Compiler, MMIO, and DMA barriers

`stdx.barrier` orders host memory accesses around device protocols. Its operations
do not perform MMIO or DMA accesses.

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

Place `stdx.barrier.mmio.release()` after related host stores and before the MMIO
store that notifies the device. Place `stdx.barrier.mmio.acquire()` after the MMIO
load that proves related memory is available and before reading that memory.
Use `stdx.barrier.mmio.full()` between mixed accesses that require both directions.

Place `stdx.barrier.dma.release()` after writes to DMA-visible data and before the
store that publishes that data to the device. Place `stdx.barrier.dma.acquire()`
after loading DMA-written availability state and before reading the related data.
Use `stdx.barrier.dma.full()` between mixed DMA-memory accesses that require both
directions.

The caller's device protocol MUST define the publication or availability state
and ensure that the device observes publication. The caller owns DMA mappings,
buffer lifetime, ownership transfers, and notification. DMA mappings MUST be
coherent, or the caller MUST perform required cache maintenance at ownership
boundaries. Obtain device completion before reusing or releasing device-owned
resources.

These operations do not establish a host-thread synchronization edge by
themselves. Use the owning synchronization primitive's publication and acquisition
protocol for shared host payloads.

## Availability and execution

`stdx.barrier.compiler()` is target-independent. MMIO and DMA operations require
an x86_64 target. Calling one on another target causes a compile error from the
architecture backend; importing `stdx.barrier` alone remains portable.

Operations are unprivileged, reentrant, and allocation-free. Hardware fences
can delay execution until their ordering requirements are satisfied.

## References

- [Compiler barrier](../../../src/barrier/compiler.zig)
- [MMIO barriers](../../../src/barrier/mmio.zig)
- [DMA barriers](../../../src/barrier/dma.zig)
