# Barrier IO/DMA

Status: Approved.

`stdx.barrier` exposes ordering primitives for host-observable interactions
with device MMIO and DMA-visible memory. This spec approves seven operations
across three sub-namespaces:

- `stdx.barrier.compiler` — a compiler reorder barrier with no ISA emission;
- `stdx.barrier.mmio.release`, `stdx.barrier.mmio.acquire`,
  `stdx.barrier.mmio.releaseAcquire` — fences paired with MMIO writes and
  reads;
- `stdx.barrier.dma.release`, `stdx.barrier.dma.acquire`,
  `stdx.barrier.dma.releaseAcquire` — fences paired with DMA-visible writes
  and reads.

The seven operations compose with `stdx.io.Mmio.Register` and with any DMA
staging buffer owned by the caller. This spec does not own SMP thread-to-thread
memory barriers, cache-maintenance sequences, or arch-specific fence spelling
beyond the x86_64 mapping approved here.

## Owned scope

This spec owns:

- `stdx.barrier.compiler`;
- `stdx.barrier.mmio.release`, `mmio.acquire`, `mmio.releaseAcquire`;
- `stdx.barrier.dma.release`, `dma.acquire`, `dma.releaseAcquire`;
- the x86_64 instruction mapping for each op;
- inline-lowering requirements;
- composition rules with `stdx.io.Mmio` and DMA-visible caller memory;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- SMP thread-to-thread memory barriers under `stdx.barrier.smp.*`
  (`loadLoad`, `storeStore`, `loadStore`, `storeLoad`, `full`);
- cache-maintenance sequences (`clflush`/`clwb`/`clflushopt` loops around
  DMA-shared buffers);
- coherency-model policy on non-coherent architectures;
- aarch64 and riscv instruction mappings — those arrive with
  `docs/specs/arch/aarch64.md` and `docs/specs/arch/riscv.md`;
- Zig `@fence(order)` mapping;
- doorbell primitives — `stdx.io.Mmio.Doorbell` is a future spec;
- polling loop primitives — `stdx.io.PollUntil` is a future spec;
- protocol vocabulary aliases such as `doorbellRelease` — consumers alias
  locally when they want protocol-flavored names.

## Public namespace

Barrier primitives live under `stdx.barrier`:

```zig
stdx.barrier.compiler

stdx.barrier.mmio.release
stdx.barrier.mmio.acquire
stdx.barrier.mmio.releaseAcquire

stdx.barrier.dma.release
stdx.barrier.dma.acquire
stdx.barrier.dma.releaseAcquire
```

They are not root-promoted:

```zig
stdx.compiler // not exported
stdx.mmio // not exported
```

Source ownership:

```text
src/barrier.zig
src/barrier/compiler.zig
src/barrier/mmio.zig
src/barrier/dma.zig
test/barrier/compiler_test.zig
test/barrier/mmio_test.zig
test/barrier/dma_test.zig
```

`src/barrier.zig`:

```zig
//! Barrier primitives. Specs: docs/specs/barrier/overview.md and
//! docs/specs/barrier/dma.md.

pub const compiler = @import("barrier/compiler.zig").compiler;

pub const mmio = @import("barrier/mmio.zig");
pub const dma = @import("barrier/dma.zig");
```

`src/barrier.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

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

Every operation is `pub inline fn`. Inlining is required so hot paths compile
to the single ISA instruction (or nothing, for `compiler`) plus its memory
clobber; a real function call at every barrier site is not acceptable for
NVMe-class submission paths.

## `compiler` semantics

`compiler()` emits no ISA instruction. It compiles down to
`asm volatile ("" ::: "memory")` — an empty inline assembly block with a
`"memory"` clobber that constrains only compiler reordering.

`compiler` is the primitive that all `mmio.*` and `dma.*` operations layer on
top of. It is exposed as a named primitive so that consumers who need only the
compiler-side effect (e.g. splitting a sequence of independent volatile
accesses across a phase boundary) have a discoverable spelling.

Required behavior:

- no ISA instruction emitted;
- compiler must not reorder any memory access across this call;
- inline lowering into the caller;
- compiles on every target.

## `mmio.release` semantics

`mmio.release()` orders prior stores to caller memory before a following MMIO
store reaches the device.

Consumer pattern:

```zig
build_sqe(&sqe);                       // stores to DMA-visible host memory
stdx.barrier.mmio.release();           // sfence on x86_64
sq_tail_reg.store(new_tail_index);     // MMIO store to a doorbell register
```

Required behavior on x86_64:

- emits `sfence`;
- prior stores complete before subsequent stores from the same CPU;
- compiler reordering across the fence is prohibited by the underlying
  inline-asm memory clobber.

`mmio.release` does not synchronize with other host CPUs beyond the ISA rules
for `sfence`. It does not flush caches. Cache-maintenance for non-coherent
DMA lives in a future `stdx.barrier.cache` spec.

## `mmio.acquire` semantics

`mmio.acquire()` orders a preceding MMIO load before following memory reads.

Consumer pattern:

```zig
while (true) {
    const csts = regs.csts.load();     // MMIO load of controller status
    stdx.barrier.mmio.acquire();       // lfence on x86_64
    if (csts_ready(csts)) break;
    stdx.arch.x86_64.Cpu.pause();
}
```

Required behavior on x86_64:

- emits `lfence`;
- prior loads complete before subsequent loads from the same CPU;
- compiler reordering across the fence is prohibited by the memory clobber.

`mmio.acquire` does not synchronize with other host CPUs beyond the ISA rules
for `lfence`.

## `mmio.releaseAcquire` semantics

`mmio.releaseAcquire()` orders prior stores before subsequent MMIO accesses
and prior MMIO accesses before subsequent memory reads.

Consumer pattern:

```zig
regs.some_register.store(new_value);
stdx.barrier.mmio.releaseAcquire();    // mfence on x86_64
const observed = other_reg.load();
```

Required behavior on x86_64:

- emits `mfence`;
- prior stores and loads complete before subsequent stores and loads from the
  same CPU;
- compiler reordering across the fence is prohibited by the memory clobber.

This op exists for the mixed direction — a store followed by a load in the same
device-interaction sequence — where neither `release` nor `acquire` alone is
sufficient. Consumers who only need one direction use the cheaper `release` or
`acquire`.

## `dma.release` semantics

`dma.release()` orders prior stores to caller memory before a following store
that the device will observe via DMA.

Consumer pattern:

```zig
build_sgl_chain(&sgl);                 // populate SGL descriptors
stdx.barrier.dma.release();            // sfence on x86_64
sgl.head.next = new_segment;           // last store is the linkage the device races on
```

Required behavior on x86_64:

- emits `sfence`;
- prior stores complete before subsequent stores from the same CPU;
- compiler reordering across the fence is prohibited by the memory clobber.

The x86_64 mapping is identical to `mmio.release`. The two operations are
distinct APIs because their semantic contracts and consumer sites differ; a
future non-x86_64 arch may lower them differently (`dsb oshst` vs `dsb oshst`
with distinct scopes on aarch64, for example).

## `dma.acquire` semantics

`dma.acquire()` orders a preceding load of DMA-written data before subsequent
loads from related caller memory.

Consumer pattern:

```zig
const phase = cqe.status.native();     // DMA-loaded CQE status (phase tag)
if (phase_matches(phase, expected_phase)) {
    stdx.barrier.dma.acquire();        // lfence on x86_64
    const result = cqe.result.native();
    // ... safe to consume the rest of the CQE
}
```

Required behavior on x86_64:

- emits `lfence`;
- prior loads complete before subsequent loads from the same CPU;
- compiler reordering across the fence is prohibited by the memory clobber.

## `dma.releaseAcquire` semantics

`dma.releaseAcquire()` orders prior DMA-visible stores before subsequent
DMA-visible loads on the same CPU.

Required behavior on x86_64:

- emits `mfence`;
- prior stores and loads complete before subsequent stores and loads from the
  same CPU;
- compiler reordering across the fence is prohibited by the memory clobber.

This op exists for the mixed direction on DMA-visible memory: a caller store
followed by an ordering-dependent load of DMA-updated state.

## Per-target instruction table

| Op | x86_64 | aarch64 | riscv64 |
| --- | --- | --- | --- |
| `compiler()` | `asm volatile ("" ::: "memory")` | same | same |
| `mmio.release()` | `sfence` | future | future |
| `mmio.acquire()` | `lfence` | future | future |
| `mmio.releaseAcquire()` | `mfence` | future | future |
| `dma.release()` | `sfence` | future | future |
| `dma.acquire()` | `lfence` | future | future |
| `dma.releaseAcquire()` | `mfence` | future | future |

Only x86_64 is normative in this spec. Referencing any `mmio.*` or `dma.*`
operation on a non-x86_64 target produces a `@compileError` with a message
naming the missing arch spec.

`compiler()` compiles on every target.

## Composition rules

Consumers combine barriers with volatile MMIO access and with caller-owned
DMA-visible memory:

```zig
// Submission path.
build_sqe(&sqe);                       // stores to DMA-visible SQE buffer
stdx.barrier.mmio.release();
sq_tail_reg.store(new_tail_index);

// Completion path.
const phase = cqe.status.native();
if (phase_matches(phase, expected_phase)) {
    stdx.barrier.dma.acquire();
    const result = cqe.result.native();
    // ...
}
```

Barriers do not replace `stdx.io.Mmio.Register.load`/`store`. Barriers do not
imply MMIO or DMA access. The primitives are independent and callers compose
them.

Barriers do not participate in `Signal`'s data-visibility protocol. Ring and
signal ordering remains owned by their respective specs.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- |
| `compiler` | never | never | O(1) | pure | compiler-only reorder barrier; no ISA emission |
| `mmio.release` | never | never | O(1) | pure | release before following MMIO store; `sfence` on x86_64 |
| `mmio.acquire` | never | never | O(1) | pure | acquire after preceding MMIO load; `lfence` on x86_64 |
| `mmio.releaseAcquire` | never | never | O(1) | pure | mixed direction across MMIO; `mfence` on x86_64 |
| `dma.release` | never | never | O(1) | pure | release before DMA-visible store; `sfence` on x86_64 |
| `dma.acquire` | never | never | O(1) | pure | acquire after DMA-visible load; `lfence` on x86_64 |
| `dma.releaseAcquire` | never | never | O(1) | pure | mixed direction across DMA memory; `mfence` on x86_64 |

Every operation is infallible, reentrant, and adds zero allocation, sleeping,
blocking, hidden global access, or scheduler interaction.

## Error behavior

No operation returns an error.

Referencing any `mmio.*` or `dma.*` operation on a non-x86_64 target produces
`@compileError` with a message that names the required arch spec (for example,
`"stdx.barrier.mmio.release: unsupported target; requires docs/specs/arch/aarch64.md"`).

`compiler()` compiles on every target and never errors.

## Implementation constraints

Implementation must:

- expose every op as `pub inline fn`;
- lower `compiler()` to `asm volatile ("" ::: "memory")` with no other clobbers
  and no register operands;
- lower each x86_64 `mmio.*` and `dma.*` op through the corresponding
  `stdx.arch.x86_64.Fence` operation, which carries the `"memory"` clobber;
- gate non-x86_64 bodies with `@compileError` referencing the missing arch
  spec so that mere imports of `stdx.barrier` stay portable;
- never introduce runtime target probing;
- never call scheduler, kernel, or userspace waiting APIs;
- never allocate;
- never touch device memory itself.

## Planned use

NVMe-class driver paths use:

- `mmio.release()` before every submission-queue tail doorbell store;
- `mmio.acquire()` in controller-enable → controller-ready handshakes and
  fatal-status polling;
- `dma.acquire()` after every DMA-written completion-entry phase-tag read;
- `dma.release()` before publishing linked scatter/gather segment chains;
- `mmio.releaseAcquire()` and `dma.releaseAcquire()` for mixed-direction
  sequences.

Similar patterns arise wherever a driver programs MMIO registers paired with
DMA-visible payloads, polls status bits, or races MSI-X mask/unmask against
interrupt delivery.

## Required tests

Following `docs/specs/barrier/overview.md` §"Required tests for future APIs",
tests must not claim to prove CPU or DMA ordering. They exercise API shape,
target gating, and lowering.

### API shape (compile-only)

- `stdx.barrier.compiler` is `pub inline fn`;
- `stdx.barrier.mmio.release`, `mmio.acquire`, `mmio.releaseAcquire` are
  `pub inline fn`;
- `stdx.barrier.dma.release`, `dma.acquire`, `dma.releaseAcquire` are
  `pub inline fn`;
- calling every op compiles in every optimize mode on x86_64;
- calling `compiler` compiles on every target.

### x86_64 execution

- `compiler()` executes once and returns;
- `mmio.release()` executes once and returns;
- `mmio.acquire()` executes once and returns;
- `mmio.releaseAcquire()` executes once and returns;
- `dma.release()` executes once and returns;
- `dma.acquire()` executes once and returns;
- `dma.releaseAcquire()` executes once and returns.

Execution tests demonstrate that the emitted instructions are legal at user
privilege and do not trap. They do not prove ordering.

### Instruction mapping (compile-only)

On x86_64:

- `mmio.release` and `dma.release` reference `stdx.arch.x86_64.Fence.sfence`;
- `mmio.acquire` and `dma.acquire` reference `stdx.arch.x86_64.Fence.lfence`;
- `mmio.releaseAcquire` and `dma.releaseAcquire` reference
  `stdx.arch.x86_64.Fence.mfence`.

Implementations satisfy this test by lowering each barrier through the
corresponding `stdx.arch.x86_64.Fence.*` function; the test asserts referential
equivalence at compile time rather than inspecting emitted bytes.

### Target gating

- on a non-x86_64 test target (if added to the matrix), referencing any
  `mmio.*` or `dma.*` op produces `@compileError`;
- `compiler()` still compiles.

## Open questions

None.
