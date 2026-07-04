# x86_64 architecture extensions

Status: Approved.

`stdx.arch.x86_64` extensions cover ISA instructions that were deferred
from `docs/specs/arch/x86_64/base.md`. Every entry is one or two
instructions with the same "just the ISA, no policy" contract that base
uses.

The namespace extends the existing `stdx.arch.x86_64` module. There is
no separate submodule surface; consumers reach these primitives at the
same paths they reach base primitives.

## Owned scope

This spec owns:

- `Cpu.Tsc` — `rdtsc` and `rdtscp` wrappers, plus the `rdtscp` result
  shape carrying both the TSC and the `IA32_TSC_AUX` value the CPU
  returns in one instruction;
- `Cpu.Tlb` — `invlpg` and `invpcid` wrappers, plus the `invpcid`
  descriptor and kind enum;
- `DebugRegister.Dr0..Dr7` — raw read/write access to the CPU debug
  registers;
- `Descriptor.Ldtr` — `lldt` and `sldt` wrappers;
- amendments to `docs/specs/arch/x86_64/base.md` that this spec removes
  disown lines from;
- target gating, compile-out behavior, and privilege documentation for
  every operation;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- feature detection of `invpcid`, `rdtscp`, or debug-extension state via
  CPUID — that is owned by `docs/specs/arch/x86_64/cpuid.md`;
- timestamp-counter calibration — downstream project on top of
  `Cpu.Tsc.read` and a reference clock;
- debug-register policy (which conditions to break on, how to compose
  with `#DB` exception handlers, DR-write serialization vs adjacent
  instructions);
- descriptor bit-layouts (`SegmentDescriptor`, `InterruptGate`,
  `TssDescriptor`) — deferred until a second downstream consumer beyond
  a hypervisor needs the shared layout;
- LDT builders, GDT builders, or IDT builders — matches base's disown
  of the equivalent for `TaskRegister`;
- `wbinvd` / `invd` — already covered by `base.md`'s `Cache`;
- `xsave` / `xrstor` — separate extension if a consumer needs them;
- `rdpid` — `rdtscp` covers the TSC-AUX read path today;
- strong `stdx.addr.VirtAddr` argument coercion — architecture layer
  imports only `core`, matching `docs/specs/architecture.md`'s
  dependency direction.

## Public namespace

Additive to the existing `stdx.arch.x86_64` namespace:

```zig
stdx.arch.x86_64.Cpu.Tsc
stdx.arch.x86_64.Cpu.Tsc.Reading
stdx.arch.x86_64.Cpu.Tlb
stdx.arch.x86_64.Cpu.Tlb.InvpcidKind
stdx.arch.x86_64.Cpu.Tlb.InvpcidDescriptor
stdx.arch.x86_64.DebugRegister
stdx.arch.x86_64.DebugRegister.Dr0
stdx.arch.x86_64.DebugRegister.Dr1
stdx.arch.x86_64.DebugRegister.Dr2
stdx.arch.x86_64.DebugRegister.Dr3
stdx.arch.x86_64.DebugRegister.Dr4
stdx.arch.x86_64.DebugRegister.Dr5
stdx.arch.x86_64.DebugRegister.Dr6
stdx.arch.x86_64.DebugRegister.Dr7
stdx.arch.x86_64.Descriptor.Ldtr
```

None are root-promoted.

## Source ownership

```text
src/arch/x86_64.zig                     ← extends the existing file in place
test/arch/x86_64_extensions_test.zig    ← separate test file
```

The source file is not split. `base.md` and this spec share private
inline-asm helpers; splitting into `src/arch/x86_64/{base,extensions}.zig`
is deferred until at least three files (`base`, `extensions`, `vmx`) live
in the directory, at which point a split proposal amends this spec and
migrates all three at once.

## Target gating

Same rule as base: `stdx.arch.x86_64` compiles on any target. Any
operation added by this spec that would emit x86_64 inline assembly
produces a compile error when referenced on a non-x86_64 target, matching
`base.md`'s target gating.

Operations whose semantics do not depend on the instruction set — the
`InvpcidDescriptor` type layout, the `InvpcidKind` enum, the `Reading`
struct — compile on any target.

## Approved API

### Cpu.Tsc

```zig
pub const Cpu = struct {
    // ... existing base members: halt, pause, breakpoint ...

    pub const Tsc = struct {
        pub const Reading = struct {
            tsc: u64,
            aux: u32,
        };

        pub fn read() u64;
        pub fn readSerializing() Reading;
    };

    pub const Tlb = struct {
        pub const InvpcidKind = enum(u2) {
            individual_address = 0,
            single_context = 1,
            all_including_globals = 2,
            all_excluding_globals = 3,
        };

        pub const InvpcidDescriptor = extern struct {
            pcid: u16,
            _reserved_pcid_high: u16 = 0,
            _reserved: u32 = 0,
            linear_address: u64,

            pub const alignment: usize = 16;
        } align(16);

        pub fn invalidatePage(addr: usize) void;
        pub fn invalidatePcid(
            kind: InvpcidKind,
            descriptor: *const InvpcidDescriptor,
        ) void;
    };
};
```

### DebugRegister

```zig
pub const DebugRegister = struct {
    pub const Dr0 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr1 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr2 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr3 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr4 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr5 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr6 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const Dr7 = struct { pub fn read() u64; pub fn write(value: u64) void; };
};
```

### Descriptor.Ldtr

```zig
pub const Descriptor = struct {
    // ... existing base members: Pointer, Gdt, Idt, TaskRegister ...

    pub const Ldtr = struct {
        pub fn load(selector: u16) void;
        pub fn store() u16;
    };
};
```

## Semantics

### Cpu.Tsc

`Cpu.Tsc.read()` executes `rdtsc` and returns the 64-bit combined
`edx:eax` value. Unprivileged unless `Cr4.TSD` is set by the host OS or
hypervisor, in which case `rdtsc` at CPL > 0 raises `#GP`. This spec does
not consult `Cr4.TSD`; the caller is responsible for the enable state.

`Cpu.Tsc.readSerializing()` executes `rdtscp` and returns a `Reading`
with the combined `edx:eax` in `tsc` and the low 32 bits of
`IA32_TSC_AUX` in `aux`. `rdtscp` is architecturally a partially
serializing instruction: it waits for all previous instructions to
complete before reading the counter, but does not prevent later
instructions from beginning. Callers who need full serialization pair
`rdtscp` with a subsequent `lfence`.

`readSerializing` requires CPUID leaf `0x80000001` `EDX[27]` (`RDTSCP`).
This spec does not probe the flag; callers who care check it themselves.
Executing `rdtscp` on a CPU without the feature raises `#UD`.

The AUX register is programmed by the host OS or hypervisor via
`wrmsr(IA32_TSC_AUX, ...)`. Its meaning (typically a packed
processor/core identifier) is caller policy.

### Cpu.Tlb

`Cpu.Tlb.invalidatePage(addr)` executes `invlpg [addr]`. The `addr`
argument is the linear address of a page containing an entry to
invalidate; the CPU invalidates the single TLB entry for that address on
the current logical processor. `invlpg` does not invalidate entries on
other CPUs; cross-CPU shootdown is caller policy.

`invalidatePage` is privileged (CPL 0). Calling at CPL > 0 raises `#GP`.

`Cpu.Tlb.invalidatePcid(kind, descriptor)` executes `invpcid` with the
supplied kind and descriptor pointer.

`InvpcidKind` values:

| Kind | Effect |
| --- | --- |
| `individual_address` | Invalidate one TLB entry for `linear_address` in the process with `pcid`. Bits 63..12 of `linear_address` matter; low 12 bits ignored. |
| `single_context` | Invalidate all TLB entries for the process with `pcid`, excluding global pages. |
| `all_including_globals` | Invalidate all TLB entries for all PCIDs, including global pages. |
| `all_excluding_globals` | Invalidate all TLB entries for all PCIDs, excluding global pages. |

The descriptor is 16 bytes. `InvpcidDescriptor` is an `extern struct` with
strict layout:

- `pcid: u16` at offset 0;
- reserved 48 bits at offsets 2..8 zeroed by the type default;
- `linear_address: u64` at offset 8.

The `invpcid` instruction requires 16-byte alignment on the descriptor.
`InvpcidDescriptor` is declared with an explicit `align(16)` so that both
`@alignOf(InvpcidDescriptor) == 16` and every value on the stack, in a
static, or as a struct field naturally satisfies the instruction's operand
alignment; the natural extern-struct alignment on this field layout is only
`@alignOf(u64) == 8`.

The `_reserved_pcid_high: u16` and `_reserved: u32` fields default to zero
and callers should not populate them; Intel documents any non-zero reserved
bits as producing `#GP`.

Kinds 2 and 3 ignore both `pcid` and `linear_address` in the descriptor;
callers still pass a valid descriptor (usually zero-initialized).

`invalidatePcid` requires CPUID `structured_extended_features` leaf 7
subleaf 0 `EBX[10]` (`INVPCID`) and, for use at CPL 0 by an OS with
paging enabled, `CR4.PCIDE`. This spec does not probe those; callers
who care check first.

`invalidatePcid` is privileged (CPL 0). Calling at CPL > 0 raises `#GP`.
`#UD` if `INVPCID` is not supported.

### DebugRegister

`DebugRegister.Dr0.read()` through `Dr7.read()` execute `mov rNN, drN`
and return the raw `u64`. `write(value)` executes `mov drN, rNN`.

All debug-register operations are privileged (CPL 0). Calling at
CPL > 0 raises `#GP`.

Dr4 and Dr5 alias Dr6 and Dr7 when `CR4.DE = 0` (Debugging Extensions
disabled). When `CR4.DE = 1`, `mov` to or from Dr4/Dr5 raises `#UD`. The
alias policy is caller-owned; this spec exposes Dr4/Dr5 raw. Callers
managing `CR4.DE` decide the access rules.

Dr6 status bits are architecturally sticky: the CPU sets bits on
exception entry but does not clear them on exit. Callers who consume
Dr6 write `0` back after handling. This spec does not clear Dr6
implicitly.

Dr7 controls breakpoint enables, conditions, and lengths. Bit
semantics are Intel SDM Vol.3 Chapter 17; this spec does not own the
layout.

### Descriptor.Ldtr

`Descriptor.Ldtr.load(selector)` executes `lldt selector`.
Privileged (CPL 0). `#GP` if the selector is invalid, points to a
non-LDT descriptor, or the descriptor is not present.

`Descriptor.Ldtr.store()` executes `sldt` and returns the
current LDT selector. Unprivileged on architectures where `sldt` is
accessible at CPL > 0, but that is a CPU/OS policy decision the caller
owns.

This spec does not own LDT entry layouts, LDT descriptor selection, or
LDT lifecycle management.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `Cpu.Tsc.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` on CPL check |
| `Cpu.Tsc.readSerializing` | never | never | O(1) | reentrant | partial serialization on prior instructions | infallible; may `#GP`/`#UD` |
| `Cpu.Tlb.invalidatePage` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `Cpu.Tlb.invalidatePcid` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `DebugRegister.Dr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP`/`#UD` |
| `DebugRegister.Dr*.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `Descriptor.Ldtr.load` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `Descriptor.Ldtr.store` | never | never | O(1) | reentrant | none | infallible |

All operations either compile to a fixed inline-asm fragment or a fixed
sequence of them. No syscall, no allocation, no lock, no target probing.

## Ordering contract

Following base:

- `Cpu.Tsc.read` (`rdtsc`) uses register clobbers on `eax`/`edx`; no
  memory clobber. `rdtsc` is not serializing.
- `Cpu.Tsc.readSerializing` (`rdtscp`) uses register clobbers on
  `eax`/`ecx`/`edx`; no memory clobber. The architectural partial-
  serialization is a property of the instruction, not of the wrapper.
- `Cpu.Tlb.invalidatePage` and `Cpu.Tlb.invalidatePcid` use a memory
  clobber to prevent the compiler from reordering TLB invalidations
  with surrounding memory operations.
- `DebugRegister.*.write` uses a memory clobber; `.read` uses a register
  clobber on the destination.
- `Descriptor.Ldtr.load` uses a memory clobber;
  `.store` uses a register clobber on the destination.

## Trap and privilege behavior

Additions to `docs/specs/arch/x86_64/base.md`'s trap table:

- `Cpu.Tsc.read`: `#GP` at CPL > 0 when `Cr4.TSD` is set.
- `Cpu.Tsc.readSerializing`: `#GP` at CPL > 0 when `Cr4.TSD` is set;
  `#UD` when `RDTSCP` is unsupported.
- `Cpu.Tlb.invalidatePage`, `Cpu.Tlb.invalidatePcid`,
  `DebugRegister.Dr*.read`/`.write`,
  `Descriptor.Ldtr.load`: `#GP` at CPL > 0.
- `Cpu.Tlb.invalidatePcid`: `#UD` when `INVPCID` is unsupported.
- `DebugRegister.Dr4.read`/`.write`, `DebugRegister.Dr5.read`/`.write`:
  `#UD` when `CR4.DE = 1`; otherwise alias Dr6/Dr7.

Trap recovery is owned by the host OS, firmware, or hypervisor.

## Amendments to base.md

Applied together with this spec landing:

1. Remove the `invlpg` disown clause from the trap table:

   The line
   `` `ControlRegister.Cr3.write`: may invalidate TLB entries per
   architectural rules. This spec does not own TLB invalidation policy
   (`invlpg`, broadcast invalidation, or PCID-aware flushing); callers
   handle those separately. ``
   becomes
   `` `ControlRegister.Cr3.write`: may invalidate TLB entries per
   architectural rules. Per-address invalidation (`invlpg`,
   `invpcid`) is provided by
   `docs/specs/arch/x86_64/extensions.md`; broadcast invalidation
   remains caller policy. ``

2. Add a "See also" line in the `Cpu` block:
   `` See also `Cpu.Tsc` and `Cpu.Tlb` in
   `docs/specs/arch/x86_64/extensions.md`. ``

3. Add a "See also" line in the `Descriptor` block:
   `` See also `Descriptor.Ldtr` in
   `docs/specs/arch/x86_64/extensions.md`. ``

No other base content is renamed, moved, or removed.

## Examples

Read the TSC bracketing a code region:

```zig
const stdx = @import("stdx");
const x86 = stdx.arch.x86_64;

const before = x86.Cpu.Tsc.read();
work();
const after = x86.Cpu.Tsc.read();
const elapsed = after -% before;
```

Serialized TSC read with CPU identity:

```zig
const r = x86.Cpu.Tsc.readSerializing();
const cpu_id = @as(u12, @truncate(r.aux));
```

Per-address TLB flush after modifying a page-table entry:

```zig
pte.* = new_entry;
x86.Fence.sfence();
x86.Cpu.Tlb.invalidatePage(virtual_address);
```

PCID-scoped flush (single context, excluding globals):

```zig
const desc: x86.Cpu.Tlb.InvpcidDescriptor = .{
    .pcid = current_pcid,
    .linear_address = 0,
};
x86.Cpu.Tlb.invalidatePcid(.single_context, &desc);
```

Install a code watchpoint on Dr0 (kernel-mode; caller owns Dr7 layout):

```zig
x86.DebugRegister.Dr0.write(watch_addr);
x86.DebugRegister.Dr7.write(new_dr7);
```

## Required tests

Tests live in `test/arch/x86_64_extensions_test.zig`.

Required tests:

- Compile-only: `Cpu.Tsc.read`, `Cpu.Tsc.readSerializing`,
  `Cpu.Tlb.invalidatePage`, `Cpu.Tlb.invalidatePcid`,
  `DebugRegister.Dr0..Dr7.read`/`.write`,
  `Descriptor.Ldtr.load`/`.store` all instantiate on
  x86_64;
- Compile-only: `@sizeOf(Cpu.Tlb.InvpcidDescriptor) == 16` and
  `@alignOf(Cpu.Tlb.InvpcidDescriptor) == 16`;
- Compile-only: `@offsetOf(Cpu.Tlb.InvpcidDescriptor, "pcid") == 0`,
  `@offsetOf(Cpu.Tlb.InvpcidDescriptor, "linear_address") == 8`;
- Compile-only: `Cpu.Tsc.Reading` field types are `u64` and `u32`;
- Compile-only: `Cpu.Tlb.InvpcidKind` has exactly four tags with the
  documented backing values;
- Compile-only: `DebugRegister` exposes `Dr0..Dr7` (eight sub-types);
- Runtime, host-safe: `Cpu.Tsc.read()` returns a value not less than a
  previously captured `Cpu.Tsc.read()` on the same logical CPU;
- Runtime, host-safe: `Cpu.Tsc.readSerializing()` returns a `Reading`
  where `tsc >= previous_read`; the AUX field is any `u32`;
- Runtime, host-privileged (NOT run in default host suite):
  `Descriptor.Ldtr.store()` returns whatever the host OS
  installed (typically `0` on Linux user mode); test is compile-only
  in the default suite and manual only under a privileged runner;
- Non-x86_64 build: the module compiles; every asm-emitting operation
  produces a compile error only when referenced.

The default host test suite must not execute any privileged instruction.
Dr* read/write, `invlpg`, `invpcid`, and `lldt` tests are compile-only in
the default suite.

## Open questions

None.
