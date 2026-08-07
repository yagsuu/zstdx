# Barrier IO/DMA

Status: Approved.

`stdx.barrier` provides compiler and CPU ordering operations for host accesses
that interact with MMIO registers or DMA-visible memory. The operations do not
perform an MMIO or DMA access.

## What this spec is

This specification defines the public `stdx.barrier.compiler`,
`stdx.barrier.mmio`, and `stdx.barrier.dma` operations. It defines their x86_64
instruction mappings, compiler-ordering effects, CPU-ordering effects,
non-x86_64 availability, and required tests.

## What this spec is not

This specification does not define:

- SMP thread-to-thread synchronization or the `stdx.barrier.smp.*` operations;
- MMIO access wrappers, which `docs/specs/io/mmio.md` owns;
- DMA-buffer ownership or DMA-memory allocation;
- cache-maintenance sequences, including `clflush`, `clwb`, and `clflushopt`;
- non-coherent-architecture coherency policy;
- aarch64 or riscv instruction mappings;
- Zig `@fence(order)` mappings;
- doorbell or polling-loop primitives; or
- protocol-specific aliases for these operations.

## Terminology

- **Caller memory** is memory that the caller reads or writes through ordinary
  host accesses.
- **DMA-visible memory** is caller-owned memory that a device can read or
  write through DMA.
- **Prior** and **subsequent** describe program order in the CPU that calls a
  barrier.
- **MMIO access** is a volatile access through `stdx.io.MMIO.Register`.

## Public namespace and source ownership

The public operations are under `stdx.barrier`:

```zig
stdx.barrier.compiler

stdx.barrier.mmio.release
stdx.barrier.mmio.acquire
stdx.barrier.mmio.releaseAcquire

stdx.barrier.dma.release
stdx.barrier.dma.acquire
stdx.barrier.dma.releaseAcquire
```

The owned source and test files are:

```text
src/barrier.zig
src/barrier/compiler.zig
src/barrier/mmio.zig
src/barrier/dma.zig
test/barrier/compiler_test.zig
test/barrier/mmio_test.zig
test/barrier/dma_test.zig
```

`src/barrier.zig` is a facade that re-exports these operations. It contains no
implementation logic.

## Cross-spec relationships

This specification depends on `docs/specs/barrier.md` for shared ordering
vocabulary and test limitations. It composes with `docs/specs/io/mmio.md`:
the caller performs an MMIO access through `stdx.io.MMIO.Register` and places
the applicable barrier in the caller's protocol.

The caller owns DMA-buffer lifetime, device protocol, notification, and cache
maintenance. These barriers do not make `Signal` notifications establish data
visibility. Ring, signal, and other concurrent primitives retain ownership of
their own publication and acquisition protocols.

## Global invariants

- Every operation is `pub inline fn` and is infallible.
- No operation allocates, waits, sleeps, blocks, yields, invokes a callback,
  accesses a scheduler, or accesses a hidden global.
- No operation reads or writes MMIO or DMA-visible memory.
- Each operation is reentrant. Concurrent callers need no serialization for
  the operation itself.
- No operation establishes a host-thread-to-host-thread happens-before edge.
  A caller that needs such an edge MUST use the synchronization primitive that
  owns its publication protocol.
- A barrier orders accesses by the calling CPU; it does not cause a device to
  start, stop, or acknowledge DMA.
- A barrier does not flush, invalidate, clean, or otherwise maintain a cache.
  When a device or platform requires cache maintenance, the caller MUST perform
  the required cache-maintenance sequence at the boundary required by that
  device or platform protocol.

## API

```zig
// src/barrier/compiler.zig
pub inline fn compiler() void;

// src/barrier/mmio.zig
pub inline fn release() void;
pub inline fn acquire() void;
pub inline fn releaseAcquire() void;

// src/barrier/dma.zig
pub inline fn release() void;
pub inline fn acquire() void;
pub inline fn releaseAcquire() void;
```

## `compiler`

### Contract

`compiler()` emits no ISA instruction. The compiler MUST NOT reorder any memory
access across the call. `compiler()` does not impose CPU or device ordering and
does not establish a happens-before edge.

### Implementation constraints

The implementation MUST lower `compiler()` to
`asm volatile ("" ::: .{ .memory = true })`, with no register operands and no
other clobbers. `compiler()` MUST compile on every target.

## `mmio.release`

### Contract

Before a caller performs a following MMIO store, the caller MUST call
`mmio.release()` after the caller's stores to the related caller memory. On
x86_64, the CPU orders those prior stores before subsequent stores from that
CPU. The compiler MUST NOT reorder memory accesses across the operation.

For a device to observe the ordered stores before the MMIO store, the caller's
device protocol MUST make the MMIO store the observation or notification point.
`mmio.release()` alone does not establish a device-to-host happens-before edge.

### Architecture mapping

On x86_64, `mmio.release()` MUST emit `sfence` through
`stdx.arch.x86_64.fence.sfence`.

## `mmio.acquire`

### Contract

After a caller performs an MMIO load, the caller MUST call `mmio.acquire()`
before the caller reads related caller memory. On x86_64, the CPU orders prior
loads before subsequent loads from that CPU. The compiler MUST NOT reorder
memory accesses across the operation.

The caller's device protocol MUST define when the MMIO value proves that the
device has made the related memory available. `mmio.acquire()` alone does not
establish a device-to-host happens-before edge.

### Architecture mapping

On x86_64, `mmio.acquire()` MUST emit `lfence` through
`stdx.arch.x86_64.fence.lfence`.

## `mmio.releaseAcquire`

### Contract

For a mixed MMIO sequence, a caller MUST call `mmio.releaseAcquire()` between
the ordering-dependent prior accesses and subsequent accesses. On x86_64, the
CPU orders prior loads and stores before subsequent loads and stores from that
CPU. The compiler MUST NOT reorder memory accesses across the operation.

`mmio.release()` and `mmio.acquire()` provide the individual ordering
directions. `mmio.releaseAcquire()` does not establish a host-thread or device
happens-before edge by itself.

### Architecture mapping

On x86_64, `mmio.releaseAcquire()` MUST emit `mfence` through
`stdx.arch.x86_64.fence.mfence`.

## `dma.release`

### Contract

Before a caller publishes a DMA-visible store that a device can observe, the
caller MUST call `dma.release()` after the caller stores the related
DMA-visible data. On x86_64, the CPU orders those prior stores before
subsequent stores from that CPU. The compiler MUST NOT reorder memory accesses
across the operation.

The caller's device protocol MUST identify the publication store and MUST
ensure that the device observes it. `dma.release()` does not establish a
host-thread-to-device happens-before edge by itself.

### Architecture mapping

On x86_64, `dma.release()` MUST emit `sfence` through
`stdx.arch.x86_64.fence.sfence`.

## `dma.acquire`

### Contract

After a caller loads DMA-written state that proves related DMA-visible memory
is available, the caller MUST call `dma.acquire()` before the caller reads that
related memory. On x86_64, the CPU orders prior loads before subsequent loads
from that CPU. The compiler MUST NOT reorder memory accesses across the
operation.

The caller's device protocol MUST define which loaded state proves
availability. `dma.acquire()` does not establish a device-to-host
happens-before edge by itself.

### Architecture mapping

On x86_64, `dma.acquire()` MUST emit `lfence` through
`stdx.arch.x86_64.fence.lfence`.

## `dma.releaseAcquire`

### Contract

For a mixed DMA-memory sequence, a caller MUST call `dma.releaseAcquire()`
between the ordering-dependent prior accesses and subsequent accesses. On
x86_64, the CPU orders prior loads and stores before subsequent loads and
stores from that CPU. The compiler MUST NOT reorder memory accesses across the
operation.

`dma.release()` and `dma.acquire()` provide the individual ordering directions.
`dma.releaseAcquire()` does not establish a host-thread or device
happens-before edge by itself.

### Architecture mapping

On x86_64, `dma.releaseAcquire()` MUST emit `mfence` through
`stdx.arch.x86_64.fence.mfence`.

## Target availability and fault behavior

`compiler()` compiles on every target.

On a non-x86_64 target, instantiating any `mmio.*` or `dma.*` operation MUST
produce `@compileError`. The compile-error message MUST state that the
`stdx.barrier.mmio` or `stdx.barrier.dma` target is unsupported and requires an
architecture specification beyond `arch/x86_64`. Importing `stdx.barrier` alone
MUST remain portable.

No operation returns an error.

## Implementation constraints

The implementation MUST:

- expose each operation as `pub inline fn`;
- lower each x86_64 MMIO and DMA operation through the corresponding
  `stdx.arch.x86_64.fence` operation, whose inline assembly has a `memory`
  clobber;
- gate each non-x86_64 MMIO and DMA operation with `@compileError`;
- avoid runtime target probing; and
- avoid scheduler, kernel, or userspace waiting APIs.

## Testing

The test suite MUST verify the public function type of each operation and that
every operation compiles on x86_64. This compile-time method proves the API
surface and required inline call convention, not hardware ordering.

The test suite MUST invoke each x86_64 operation once in a target-gated
execution test and verify that it returns without a trap. This method proves
that the selected instruction is legal at user privilege on the test target. It
does not prove CPU, device, or DMA ordering.

The target matrix MUST verify that `compiler()` compiles on every supported
target. When a non-x86_64 target is available, the test suite MUST use a
compile-fail test to verify that instantiating each `mmio.*` and `dma.*`
operation produces `@compileError` while importing `stdx.barrier` alone remains
valid. This method proves the availability boundary and portable-import
requirement.

The test suite MUST use compile-time mapping checks to verify that x86_64
`release`, `acquire`, and `releaseAcquire` operations lower through `sfence`,
`lfence`, and `mfence`, respectively. The checks MUST inspect the chosen
lowering or its emitted code; referential equivalence alone does not prove an
instruction mapping. This method proves the architecture-mapping contract
without claiming to prove the hardware ordering guarantee.
