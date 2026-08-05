# Panic-safe ring log

Status: Approved.

`stdx.diag.PanicLog` is a panic-safe and NMI-safe byte-ring log sink. Writers
emit length-prefixed byte messages under a single-writer seat CAS; contended
writers drop rather than block. A single reader drains published messages to
a `*std.Io.Writer` without blocking writers.

The primitive is intentionally minimal: byte storage, monotonic sequence
counter, seat CAS, overwrite-oldest byte-overflow policy, drop accounting.
It owns no formatting, no severity, no persistence, and no cross-CPU flush
ordering.

## Owned scope

This spec owns:

- `stdx.diag.PanicLog.Static(capacity_bytes)`;
- `stdx.diag.PanicLog.DrainState`;
- byte-ring storage with a monotonic 64-bit sequence counter;
- fixed 8-byte little-endian message header format;
- writer-seat try-CAS single-writer discipline with drop-on-contention;
- overwrite-oldest byte-overflow policy at whole-message granularity;
- monotonic `dropped_seq` accounting for both seat-contention drops and
  byte-overflow overwrites;
- single-reader drain to `*std.Io.Writer` with mid-drain resync on
  concurrent overwrite;
- atomic ordering discipline;
- NMI/IRQ safety contract for the writer path;
- `assertValid` and required tests.

## Deferred scope and non-goals

This spec does not own:

- formatted logging, `printf`-style APIs, or template rendering — the ring
  stores raw bytes only;
- severity levels, filtering, structured payloads, or tag catalogs;
- multi-CPU flush ordering or cross-CPU cache-maintenance policy —
  `stdx.barrier.*` is the composition point;
- log persistence, rotation, mirroring, or export beyond `drain`;
- multi-reader drain (one reader at any instant);
- `std.log` integration;
- wall-clock or monotonic-clock timestamps — the caller prepends its own
  timestamp into the payload if needed;
- message-boundary discovery for partially-drained ranges;
- a `Bounded` variant — panic sinks are static resources; a `Bounded`
  sibling waits for a concrete consumer;
- root promotion of `PanicLog`.

Structured tracing that requires multiple concurrent writers or high
throughput belongs to the deferred `docs/specs/diag/trace-ring.md`, not
here.

## Public namespace

`PanicLog` lives under `stdx.diag`:

```zig
stdx.diag.PanicLog
stdx.diag.PanicLog.Static
stdx.diag.PanicLog.DrainState
```

It is not root-promoted:

```zig
stdx.PanicLog       // not exported
stdx.diag.Static    // not exported
```

Source ownership:

```text
src/diag.zig
src/diag/panic_log.zig
test/diag/panic_log_test.zig
```

`src/diag.zig` re-exports:

```zig
pub const panic_log = @import("diag/panic_log.zig");

pub const PanicLog = panic_log.PanicLog;
```

`src/diag.zig` is a thin facade. It contains no logic beyond re-exporting
and aliasing.

## Approved API

```zig
pub const PanicLog = struct {
    pub fn Static(comptime capacity_bytes: usize) type;

    pub const DrainState = struct {
        next_seq: u64 = 1,
        dropped_snapshot: u64 = 0,

        pub fn init() DrainState;
    };
};
```

`Static(capacity_bytes)` returned type:

```zig
pub const Self = struct {
    bytes: [capacity_bytes]u8 = [_]u8{0} ** capacity_bytes,
    head: stdx.mem.CachePad(std.atomic.Value(usize)) = ...,
    tail: std.atomic.Value(usize) = ...,
    seat: std.atomic.Value(u8) = ...,
    seq: std.atomic.Value(u64) = ...,
    dropped_seq: std.atomic.Value(u64) = ...,

    pub const Error = error{
        WriterBusy,
        PayloadTooLarge,
        EmptyPayload,
    };

    pub const header_bytes: usize = 8;
    pub const capacity_bytes_const: usize = capacity_bytes;
    pub const max_payload_bytes: usize = capacity_bytes - header_bytes;

    pub fn init() Self;
    pub fn clear(self: *Self) void;

    pub fn write(self: *Self, payload: []const u8) Error!void;

    pub fn drain(
        self: *Self,
        reader_state: *DrainState,
        sink: *std.Io.Writer,
    ) std.Io.Writer.Error!void;

    pub fn dropped(self: *const Self) u64;
    pub fn published(self: *const Self) u64;
    pub fn isSeated(self: *const Self) bool;

    pub fn isValid(self: *const Self) bool;
    pub fn assertValid(self: *const Self) void;
};
```

There is no `Bounded` variant, no writer-iterator, no per-frame reader
introspection, no severity parameter, and no timestamp field. The header
carries `len` and `seq_low` and nothing else.

## Compile-time constraints on `Static`

`Static(capacity_bytes)` is a `@compileError` when:

- `capacity_bytes < 2 * header_bytes` (must hold at least two minimum
  messages; the boundary is not tight but rejects trivially useless
  configurations);
- `capacity_bytes > std.math.maxInt(u32)` (offsets and lengths use `u32`
  in the on-disk header format).

`capacity_bytes` need not be a power of two. Indexing uses branch-wrap
modulo `capacity_bytes`. Panic writes are slow paths; the mask-vs-branch
distinction is not observable.

## Message format

On the wire (in the byte ring):

```text
offset 0:  u32 len       (little-endian, payload length in bytes, excludes header)
offset 4:  u32 seq_low   (little-endian, low 32 bits of the monotonic seq at write time)
offset 8:  bytes         (exactly len bytes of payload)
```

`header_bytes = 8`. Both `u32` fields are stored via `stdx.layout.Le(u32)`
so a post-mortem memory dump analyzed by an external tool sees a stable
format regardless of the host writer's byte order.

Payload constraints:

- `len` in the header is in `1 .. max_payload_bytes`;
- `payload.len == 0` is rejected before any state change with
  `error.EmptyPayload`;
- `payload.len > max_payload_bytes` is rejected with
  `error.PayloadTooLarge`.

The header is written by the writer holding the seat; the seat's exclusion
guarantees no other writer touches the same bytes.

Payloads have no alignment requirement. Messages are byte-packed with no
inter-message padding. A message that would extend past `capacity_bytes`
wraps: the writer branches on wrap and issues two byte copies (prefix at
the tail of the buffer and suffix at the head). The header and payload
together form one logical frame across the wrap boundary.

The reader parses `len` first, computes the frame size as
`header_bytes + len`, and advances its cursor by that amount with wrap.

## Storage model

`Static(capacity_bytes)` owns inline byte storage plus four atomics and a
cache-padded head:

- `bytes`: the ring's byte storage.
- `head`: next-write byte offset in `[0, capacity_bytes)`, cache-padded to
  isolate it from the seat and the reader-observed counters.
- `tail`: the oldest byte offset still logically present in the ring. The
  writer advances `tail` when it needs to overwrite oldest messages.
- `seat`: 0 = seat free; 1 = seat held.
- `seq`: monotonic 64-bit publication counter. Incremented once per
  successful `write`.
- `dropped_seq`: monotonic 64-bit drop counter. Incremented once per
  `WriterBusy` drop and once per whole-message overwrite.

`head` is `stdx.mem.CachePad`ped because it is release-published by the
writer and acquire-loaded by the reader. `tail`, `seat`, `seq`, and
`dropped_seq` sit adjacent to reduce total footprint; the panic-write
critical section pays a single-line miss on entry and one on exit.

`init()` zeroes every field. `clear(self)` restores the same state without
releasing the storage. `clear` is safe only when no writer holds the seat
and no reader is mid-drain — it is intended for test fixtures.

## Writer semantics

`write(self, payload)`:

1. If `payload.len == 0` → `error.EmptyPayload`. No state change.
2. If `payload.len > max_payload_bytes` → `error.PayloadTooLarge`. No
   state change.
3. Attempt seat acquisition: single `cmpxchgStrong(seat, 0, 1, .acquire,
   .monotonic)`. On failure, atomically fetchAdd `dropped_seq` by 1 with
   release ordering and return `error.WriterBusy`.
4. With the seat held:
   1. Compute `needed = header_bytes + payload.len`.
   2. While the free bytes between `head` (relaxed) and `tail` (relaxed)
      are fewer than `needed`, parse the frame at `tail`, advance `tail`
      by `header_bytes + frame_len` (with wrap), and fetchAdd
      `dropped_seq` by 1 with release ordering. Every dropped frame is a
      whole message.
   3. Increment `seq` by 1 with release ordering; snapshot the new value
      as `new_seq`.
   4. Encode the header (`len = payload.len` and `seq_low = @truncate(new_seq)`)
      into the ring bytes at `head`, wrapping if the header straddles the
      end of the buffer.
   5. Copy the payload bytes into the ring, wrapping identically.
   6. Store `head` advanced by `needed` (with wrap) using release ordering.
   7. Release the seat: `store(seat, 0, .release)`.

The bounded try-CAS is one attempt. Panic paths never spin, never yield,
and never wait. A preempted holder stalls the ring only for other writers
that arrive during the preemption; those writers all drop.

Reservation atomicity: the seat is held for the entire header-write plus
payload-copy plus head-update sequence. A writer that panics mid-write
without releasing the seat permanently seats the ring. Recovery is caller
policy (typically a system reset following the panic).

## Reader semantics

`drain(self, reader_state, sink)`:

The reader is a single logical instance. Concurrent calls to `drain` on
the same `PanicLog` are outside contract.

Loop:

1. `seq_now = seq.load(.acquire)`.
2. `dropped_now = dropped_seq.load(.acquire)`.
3. If `dropped_now != reader_state.dropped_snapshot`:
   - `delta = dropped_now - reader_state.dropped_snapshot`;
   - `try sink.print("... {} messages dropped ...\n", .{delta})`;
   - `reader_state.dropped_snapshot = dropped_now`;
   - `reader_state.next_seq = oldestSurvivingSeq(self)`;
   - continue outer loop.
4. If `reader_state.next_seq > seq_now`, return.
5. Compute the byte offset of the frame carrying `reader_state.next_seq`
   from `tail` (with wrap traversal). Read `len` (relaxed) at that offset,
   emit `header_bytes + len` bytes to the sink starting at
   `offset + header_bytes` (with wrap handling), advance
   `reader_state.next_seq` by 1.
6. If `dropped_seq` (acquire) advanced during step 5, discard progress in
   the current outer iteration and continue outer loop.
7. Otherwise, if `reader_state.next_seq <= seq_now`, continue step 5.
   Otherwise return.

`oldestSurvivingSeq(self)` reads the frame at `tail` (with acquire) and
reconstructs its 64-bit sequence value from `seq_low` using the current
`seq` snapshot: the high 32 bits are inferred as the bits of
`seq.load(.acquire)` that would place the reconstructed value in
`(seq - u32.max, seq]`. This is well-defined because at most 2^32 messages
can be in flight in the ring at once — a physical impossibility given
`max_payload_bytes >= 0` implies the ring holds at most
`capacity_bytes / (header_bytes + 1)` messages, far below 2^32.

The reader never blocks writers. It only issues atomic loads of `head`,
`tail`, `seq`, and `dropped_seq`; the ring bytes are read directly under
the seat's exclusion guarantee for the writer side and the release/acquire
ordering on `head` and `dropped_seq`.

Torn-frame defense: the writer stores `head` after copying the frame, so
the reader observes `head` covering only fully-published frames. A
`dropped_seq` advance mid-drain means the writer has overwritten frames
the reader was still reading; the reader restarts the drain iteration.

## Drop marker format

The reader emits the following bytes to `sink` when it detects a drop
delta:

```text
... N messages dropped ...\n
```

where `N` is the delta as a decimal integer. This is a deterministic
ASCII line, terminated by a single `\n`. The marker is emitted once per
drain iteration that observes a delta, regardless of the magnitude of the
delta.

Callers who need a different marker format wrap `drain` at a higher layer
and translate. This spec does not accept a marker-format parameter.

## Atomic ordering

- `seat`: acquire on successful CAS from 0 to 1; release on store to 0.
- `head`: release stores by the writer; acquire loads by the reader.
- `tail`: released before `head` update on overwrite; acquired by the
  reader before frame parse.
- `seq`, `dropped_seq`: release stores by the writer; acquire loads by
  the reader.

The writer's release-store of `head` synchronizes with the reader's
acquire-load of `head`, giving the reader visibility of the header and
payload bytes written under the seat.

No ISA-level fences beyond what Zig atomics emit. Cross-CPU visibility
(e.g. a panic on CPU A drained from CPU B) is a caller concern via
`stdx.barrier.*`.

## Execution context and NMI safety

Writer path:

- Seat CAS is a single `u8` atomic — atomic on every supported target.
  Safe from IRQ, NMI, MCE, and nested interrupt preemption.
- If a writer is preempted between seat acquisition and seat release,
  subsequent writers on any CPU observe `seat == 1` and drop
  (`error.WriterBusy`, `dropped_seq += 1`).
- If a writer is preempted mid-payload-copy, the reader cannot observe
  the partial frame because `head` has not been advanced. The writer's
  release-store of `head` synchronizes the reader's visibility.
- Two writers on separate CPUs cannot interleave bytes into the ring:
  only one holds the seat at any instant.

Reader path:

- Single-owner and not NMI-safe by contract. Callers who need to drain
  from an interrupt or panic context must not — the reader assumes it
  can be preempted only by writers that are safe against reader
  preemption (which they are, because the writer never observes the
  reader).

Preemption of the writer by a panic-time reader is outside contract and
callers must not do it.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Static(...)` | never | never | comptime | type factory | none | `@compileError` on invalid `capacity_bytes` |
| `init` / `clear` | never | never | O(`capacity_bytes`) | single-owner (pre-publication) | release | infallible |
| `write` | never | never | O(payload.len + overwrites) | single-writer at any instant; NMI-safe drop | acquire/release on seat, head, tail, seq, dropped_seq | `WriterBusy` / `PayloadTooLarge` / `EmptyPayload` |
| `drain` | never | never | O(bytes drained + sink cost) | single reader; never blocks writers | acquire loads | sink errors propagate unchanged |
| `dropped` / `published` / `isSeated` | never | never | O(1) | any reader | acquire | infallible |
| `isValid` / `assertValid` | never | never | O(`capacity_bytes`) | single owner (quiescent) | acquire | infallible / traps on invalid |

`PanicLog` performs no heap allocation, no locking beyond the seat CAS,
no formatting inside the sink, no scheduler interaction, and no syscall.
The writer path is safe from any execution context including NMI, MCE,
and machine-check-abort with drop-on-contention semantics. The reader is
single-owner and not NMI-safe.

## Debug assertion behavior

`assertValid` runs unconditionally when called and checks:

- `head.value.raw() < capacity_bytes`;
- `tail.raw() < capacity_bytes`;
- `seat.raw() ∈ {0, 1}`;
- `dropped_seq.raw() <= seq.raw()` (dropped never exceeds published);
- if `seat.raw() == 0`, walking from `tail` to `head` parses cleanly
  into whole frames (loose sanity — meaningful only when the ring is
  quiescent).

`isValid` returns the boolean form. Neither method touches the seat and
neither is safe from a writer racing against it — callers who need
runtime invariant checks quiesce the ring first (e.g. via `clear`
followed by a targeted probe).

## std.Io lane

`PanicLog` serves both lanes declared in the spec queue:

1. Composes inside a downstream `std.Io`-based diagnostic sink where the
   drain destination is an `Io.Writer` handled by the runtime. The
   panic-safe write path is still available directly.
2. Serves freestanding consumers — kernel panic handlers, hypervisor
   VM-exit fault paths, firmware pre-runtime failure logs, NMI/MCE
   handlers — where `std.Io` is not available.

Distinct from `docs/specs/diag/diagnostic.md`: `Diagnostics` is scoped
error-path context with an arena; it uses `errdefer` and cannot be
called from NMI. Distinct from the deferred
`docs/specs/diag/trace-ring.md`: tracing targets multi-writer high
throughput, not panic-safety.

## Examples

Kernel panic sink:

```zig
const stdx = @import("stdx");

var panic_log: stdx.diag.PanicLog.Static(4096) = .init();

pub fn onPanic(msg: []const u8) noreturn {
    panic_log.write(msg) catch {};  // drop on contention — panic never blocks
    while (true) asm volatile ("hlt");
}

pub fn onNmi(msg: []const u8) void {
    panic_log.write(msg) catch {};
}

fn dumpToConsole(sink: *std.Io.Writer) !void {
    var state = stdx.diag.PanicLog.DrainState.init();
    try panic_log.drain(&state, sink);
}
```

Hypervisor VM-exit fault log:

```zig
var vm_faults: stdx.diag.PanicLog.Static(64 * 1024) = .init();

fn onFatalVmExit(cpu_id: u8, reason: u32, rip: u64) void {
    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "cpu {} fatal exit reason=0x{x} rip=0x{x}", .{
        cpu_id, reason, rip,
    }) catch return;
    vm_faults.write(msg) catch {};
}
```

## Required tests

Tests live in `test/diag/panic_log_test.zig`. Deterministic ordering
tests use a scripted single-writer sequence. Contention tests use a
test-only hook that forces `seat.cmpxchgStrong` to fail.

### `Static(...)` factory

- `Static(64)` compiles.
- `Static(15)` (< 2 · header_bytes) is a compile error.
- `Static(0)` is a compile error.
- `Static(std.math.maxInt(u32) + 1)` is a compile error.
- `Static(64).capacity_bytes_const == 64`,
  `Static(64).header_bytes == 8`,
  `Static(64).max_payload_bytes == 56`.

### `init` / `clear`

- Fresh `init()` yields `published() == 0`, `dropped() == 0`,
  `isSeated() == false`, `isValid() == true`.
- `clear` after a write sequence resets `head`, `tail`, `seq`, and
  `dropped_seq`; a subsequent `drain` emits nothing.

### `write` — happy path

- Sequential writes of `"a"`, `"bb"`, `"ccc"` succeed;
  `published() == 3`, `dropped() == 0`.
- Byte inspection at offset 0 sees `[len=1 LE u32][seq_low=1 LE u32][byte 'a']`;
  next frame at offset 9 sees `[len=2 ...][seq_low=2 ...][bytes 'b','b']`;
  next frame at offset 19 sees `[len=3 ...][seq_low=3 ...][bytes 'c','c','c']`.
- A write of exactly `max_payload_bytes` bytes succeeds; `dropped() == 0`
  when the ring was empty; `published() == 1`.

### `write` — error surface

- `write("")` returns `error.EmptyPayload`; no field changes.
- A write of `max_payload_bytes + 1` bytes returns `error.PayloadTooLarge`;
  no field changes.
- With the test-only CAS-failure hook, `write("x")` returns
  `error.WriterBusy` and `dropped()` becomes `1`; `published()` unchanged.

### Byte-overflow — overwrite-oldest at whole-message granularity

- `Static(32)` with `header_bytes == 8` → `max_payload_bytes == 24`.
- Write four 4-byte payloads (each frame is 12 bytes). The 4th write must
  drop the 1st frame; `dropped()` becomes 1.
- After the 4th write, drain observes the drop marker `... 1 messages
  dropped ...\n` followed by the payloads of frames 2, 3, 4 in order.
- Wrap correctness: byte inspection confirms the 4th frame occupies
  offsets `24..32` and `0..4` (i.e. it wraps across the buffer end).

### `drain` — sequential

- Write 3 messages; `drain` to a byte-collecting sink emits the three
  payloads concatenated in write order; no drop marker.
- Second `drain` with no writes in between emits nothing.
- `DrainState.next_seq` after drain equals `4`.

### `drain` — dropped messages via seat contention

- Force N consecutive `error.WriterBusy` drops, then a successful write.
- `drain` emits `... N messages dropped ...\n` followed by the successful
  payload.
- `DrainState.dropped_snapshot` after drain equals `N`.

### `drain` — mid-drain overwrite resync

- Model test with a fake writer that increments `dropped_seq` mid-drain
  (simulating an overwrite that races the reader).
- Reader detects the delta, emits the drop marker, resets `next_seq` to
  `oldestSurvivingSeq`, and resyncs.

### Seat CAS discipline

- Two-writer test using a test-only "pause between CAS success and seat
  release" hook: writer A pauses; writer B's `write` returns
  `error.WriterBusy`; `dropped()` becomes 1.
- Release writer A → seat freed → writer B's next `write` succeeds.

### NMI-preemption model

- Simulate writer A preempted between CAS success and payload copy; call
  writer B (representing the NMI writer). Writer B observes `seat == 1`
  and drops. Return to writer A, complete. `drain` emits A's payload;
  `dropped()` reflects B's drop.

### `dropped` / `published` / `isSeated`

- Direct queries reflect state after each of the above scenarios.
- `published()` increases by 1 per successful write.
- `dropped()` increases by 1 per `WriterBusy` drop and by N per overflow
  that overwrites N whole messages.
- `isSeated()` returns `true` only while a writer holds the seat.

### `assertValid` / `isValid`

- Fresh state is valid.
- After 100 writes and 10 drains, state remains valid.
- Test-only mutation of `head` to `capacity_bytes + 1` makes `isValid`
  return `false` and `assertValid` trap.
- `dropped_seq > seq` (test-only mutation) fails `isValid`.

### Compile-only

- `@sizeOf(Static(64))` is at least `64 + @sizeOf(stdx.mem.CachePad(std.atomic.Value(usize)))`
  and no more than that plus the un-padded atomics.
- `@alignOf(Static(64))` at least matches `stdx.mem.CachePad`'s alignment.
- Non-x86 build compiles the module.

## Open questions

None.
