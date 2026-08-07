# x86_64 VMX ISA wrappers

Status: Approved.

`stdx.arch.x86_64.vmx` owns inline-assembly wrappers for Intel VMX instructions.

## Owned scope

This spec owns:

- `vmx.Error` — the `RFLAGS`-derived error set common to every wrapper;
- `vmx.PhysAddr` — strong physical-address value type;
- `vmx.VmxonRegion` and `vmx.Vmcs` — 4 KiB `extern struct` region types
  exposing only the architectural region header (revision identifier for
  both, plus VMX-abort indicator for `Vmcs`); the remainder of each region
  is a reserved byte array accessible only via the ISA (`vmread`/`vmwrite`
  for VMCS body) and not through ordinary loads or stores;
- `vmx.InveptKind` and `vmx.InveptDescriptor` — 16-byte descriptor and
  invalidation-kind enum used by `invept`;
- `vmx.InvvpidKind` and `vmx.InvvpidDescriptor` — 16-byte descriptor and
  invalidation-kind enum used by `invvpid`;
- wrappers `vmxon`, `vmxoff`, `vmclear`, `vmptrld`, `vmptrst`, `vmlaunch`,
  `vmresume`, `vmread`, `vmwrite`, `invept`, `invvpid`;
- target gating and compile-out behavior consistent with `base.md`;
- privilege documentation and trap behavior;
- required tests (compile-only in the default host suite).

## Deferred scope and non-goals

This spec does not own:

- the VMCS field-encoding catalog — `vmread`/`vmwrite` take a raw `u32`
  encoding per Intel SDM Vol.3 Appendix B natural-index encoding; the
  catalog belongs to downstream hypervisor projects;
- decoded VMX exit reasons, decoded VM-instruction error codes, or bit
  layouts of any VMCS field;
- EPT paging-structure entries, EPT PTE layouts, and EPT permission encoding
  (future owner: `docs/specs/arch/x86_64/paging-slat-ept.md` /
  `stdx.arch.x86_64.paging.slat.ept`);
- VPID allocation policy;
- CR4/EFER programming, VMX enable/disable dance beyond the ISA
  instructions themselves;
- VMX revision-identifier probing via `IA32_VMX_BASIC` — MSR reads are
  handled by `docs/specs/arch/x86_64.md`'s `Msr` type;
- feature detection of VMX, EPT, VPID, INVEPT, or INVVPID — deferred to
  `docs/specs/arch/x86_64/cpuid.md`;
- host-state / guest-state initialization, VM-entry launch-controls
  policy, or VM-exit handler dispatch;
- SMX/`GETSEC` interactions, dual-monitor treatment, or SMM interactions;
- shadow-VMCS bitmap configuration (bit 31 of the VMCS revision-id word);
- runtime execution on the host test suite — VMX instructions require
  CPL 0 and CR4.VMXE = 1, which the host runner cannot provide;

## Public namespace

`stdx.arch.x86_64.vmx` is the public VMX namespace:

```zig
stdx.arch.x86_64.vmx
stdx.arch.x86_64.vmx.Error
stdx.arch.x86_64.vmx.PhysAddr
stdx.arch.x86_64.vmx.VmxonRegion
stdx.arch.x86_64.vmx.Vmcs
stdx.arch.x86_64.vmx.InveptKind
stdx.arch.x86_64.vmx.InveptDescriptor
stdx.arch.x86_64.vmx.InvvpidKind
stdx.arch.x86_64.vmx.InvvpidDescriptor
```

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/vmx.zig
test/arch/x86_64_vmx_test.zig   ← separate test file
```

`src/arch/x86_64.zig` re-exports `pub const vmx = @import("x86_64/vmx.zig");`.

## Target gating

Same rule as `base.md`: `stdx.arch.x86_64` compiles on
any target. Any operation added by this spec that would emit x86_64 inline
assembly produces a compile error when referenced on a non-x86_64 target.

Operations whose semantics do not depend on the instruction set —
`PhysAddr.fromInt`/`raw`, the `VmxonRegion` and `Vmcs` region types, the
`InveptDescriptor` / `InvvpidDescriptor` layouts, and the `InveptKind` /
`InvvpidKind` enums — compile on any target so type layouts and constants
remain portable.

## API

```zig
pub const vmx = struct {
    pub const Error = error{ VMfailInvalid, VMfailValid };

    pub const PhysAddr = enum(u64) {
        _,

        pub fn fromInt(value: u64) PhysAddr;
        pub fn raw(self: PhysAddr) u64;
    };

    pub const VmxonRegion = extern struct {
        revision_id: u32 align(4096) = 0,
        _reserved: [4092]u8 = @splat(0),

        pub const alignment: usize = 4096;
    };

    pub const Vmcs = extern struct {
        revision_id: u32 align(4096) = 0,
        abort_indicator: u32 = 0,
        _reserved: [4088]u8 = @splat(0),

        pub const alignment: usize = 4096;
    };

    pub const InveptKind = enum(u64) {
        single_context = 1,
        global = 2,
        _,
    };

    pub const InveptDescriptor = extern struct {
        eptp: u64 align(16),
        _reserved: u64 = 0,

        pub const alignment: usize = 16;
    };

    pub const InvvpidKind = enum(u64) {
        individual_address = 0,
        single_context = 1,
        all_contexts = 2,
        single_context_retaining_globals = 3,
        _,
    };

    pub const InvvpidDescriptor = extern struct {
        vpid: u16 align(16),
        _reserved_low: u16 = 0,
        _reserved_high: u32 = 0,
        linear_address: u64 = 0,

        pub const alignment: usize = 16;
    };

    pub fn vmxon(region: *const PhysAddr) Error!void;
    pub fn vmxoff() Error!void;

    pub fn vmclear(vmcs: *const PhysAddr) Error!void;
    pub fn vmptrld(vmcs: *const PhysAddr) Error!void;
    pub fn vmptrst(out: *PhysAddr) Error!void;

    pub fn vmlaunch() Error!noreturn;
    pub fn vmresume() Error!noreturn;

    pub fn vmread(encoding: u32) Error!u64;
    pub fn vmwrite(encoding: u32, value: u64) Error!void;

    pub fn invept(kind: InveptKind, descriptor: *const InveptDescriptor) Error!void;
    pub fn invvpid(kind: InvvpidKind, descriptor: *const InvvpidDescriptor) Error!void;
};
```

## Semantics

### Error mapping

Every wrapper executes exactly one VMX instruction (or one of `vmlaunch` /
`vmresume`) and immediately inspects `RFLAGS.CF` and `RFLAGS.ZF`. Intel SDM
Vol.3 §30.2 defines three mutually exclusive outcomes:

| Outcome | `RFLAGS.CF` | `RFLAGS.ZF` | Mapped result |
| --- | --- | --- | --- |
| VMsucceed | 0 | 0 | success |
| VMfailInvalid | 1 | 0 | `Error.VMfailInvalid` |
| VMfailValid | 0 | 1 | `Error.VMfailValid` |

A `CF=1, ZF=1` combination MUST be reported as `VMfailInvalid`. The wrapper
does not rely on the architectural guarantee that the two flags are never
both set.

`Error.VMfailInvalid` corresponds to failure without a current VMCS
(SDM: current VMCS is `FFFFFFFFFFFFFFFF`, or the region pointer is
malformed).

`Error.VMfailValid` corresponds to failure with a current VMCS and a
specific error code recorded in VMCS field `0x4400`
(SDM Vol.3 Table 30-1). The wrapper does not read this field; callers who
need the code invoke `vmx.vmread(0x4400)` after receiving
`Error.VMfailValid`.

Traps distinct from `VMfail*` (`#GP` at CPL > 0, `#UD` when VMX is not
supported or `CR4.VMXE = 0`) are architectural CPU exceptions and are not
modeled by `Error`. See `## Trap and privilege behavior` below.

### PhysAddr

`vmx.PhysAddr` is an opaque physical-address value type covering the full
64-bit physical-address space.

- `PhysAddr.fromInt(value)` is infallible and compiles on any target.
- `PhysAddr.raw(self)` returns the exact `u64` and compiles on any target.
- The declaration is `enum(u64) { _ }` matching the strong-value pattern
  used by `Port` and `Msr` in `base.md`.

`PhysAddr` values passed to VMX wrappers must satisfy the CPU's
architectural alignment for the target instruction — 4 KiB alignment for
VMXON regions and VMCS regions. Misalignment produces a `VMfailInvalid`
outcome for `vmxon`/`vmclear`/`vmptrld` and is caller policy.

### VmxonRegion and Vmcs

`VmxonRegion` and `Vmcs` are 4 KiB `extern struct` region types. Alignment
is raised to 4096 via a field-level `align(4096)` on the first field, and
each type exposes `pub const alignment: usize = 4096`. Both cover the
architectural region header defined by SDM Vol.3 §24.11; the remainder
is `_reserved: [N]u8 = @splat(0)`.

The VMCS body MUST NOT be accessed through ordinary loads or stores (SDM
Vol.3 §24.2). The `_reserved` byte array is opaque; its layout is
CPU-implementation-defined.

`VmxonRegion` fields:

- `revision_id: u32 = 0` at offset 0 — low 31 bits are the VMCS revision
  identifier read from `IA32_VMX_BASIC[30:0]`. SDM requires bit 31 to be
  zero on VMXON regions; callers MUST preserve this.
- `_reserved: [4092]u8 = @splat(0)` at offset 4 — VMXON body.

`Vmcs` fields:

- `revision_id: u32 = 0` at offset 0 — low 31 bits are the VMCS revision
  identifier (MUST match `IA32_VMX_BASIC[30:0]`). Bit 31 is the shadow-VMCS
  indicator. The wrapper MUST preserve `revision_id` unchanged; shadow-VMCS
  bit selection is caller policy.
- `abort_indicator: u32 = 0` at offset 4 — set by the CPU on VMX abort
  (SDM Vol.3 §27.7). Callers MAY clear this field after handling a VMX
  abort using ordinary stores (SDM Vol.3 §24.2 exception clause). Software
  reads this field with ordinary loads.
- `_reserved: [4088]u8 = @splat(0)` at offset 8 — VMCS data area,
  accessible only via `vmread` / `vmwrite`.

Compile-time invariants held inside the type bodies:

- `@sizeOf(VmxonRegion) == 4096`, `@alignOf(VmxonRegion) == 4096`;
- `@sizeOf(Vmcs) == 4096`, `@alignOf(Vmcs) == 4096`;
- `@offsetOf(VmxonRegion, "revision_id") == 0`;
- `@offsetOf(VmxonRegion, "_reserved") == 4`;
- `@offsetOf(Vmcs, "revision_id") == 0`;
- `@offsetOf(Vmcs, "abort_indicator") == 4`;
- `@offsetOf(Vmcs, "_reserved") == 8`.

`VmxonRegion`, `Vmcs`, `InveptDescriptor`, `InvvpidDescriptor`, `InveptKind`,
and `InvvpidKind` MUST compile on any target. Only wrappers that emit
inline assembly are gated to x86_64.

### InveptKind and InveptDescriptor

`InveptKind` is an open `enum(u64)` naming the two architecturally defined
INVEPT invalidation types (SDM Vol.3 §30.3):

- `single_context = 1` — invalidate mappings for the EP4TA in the
  descriptor's `eptp`;
- `global = 2` — invalidate all EPT-derived mappings on the logical
  processor.

Kinds 0 and 3 are architecturally reserved and produce `VMfailInvalid`.
The `_` tag keeps the enum open.

`InveptDescriptor` is a 16-byte `extern struct`. Alignment is raised to 16
via `align(16)` on `eptp`, and the type exposes
`pub const alignment: usize = 16`:

- `eptp: u64` at offset 0 — extended-page-table pointer whose bit layout
  is a caller-owned EPT policy;
- `_reserved: u64 = 0` at offset 8 — SDM requires reserved bits to be
  zero; non-zero values produce `VMfailInvalid`.

Compile-time invariants held inside the type body:

- `@sizeOf(InveptDescriptor) == 16`, `@alignOf(InveptDescriptor) == 16`;
- `@offsetOf(InveptDescriptor, "eptp") == 0`;
- `@offsetOf(InveptDescriptor, "_reserved") == 8`.

`InveptKind.global` ignores the `eptp` field; callers still pass a valid
zero-initialized descriptor.

### InvvpidKind and InvvpidDescriptor

`InvvpidKind` is an open `enum(u64)` naming the four architecturally
defined INVVPID invalidation types (SDM Vol.3 §30.3):

- `individual_address = 0` — invalidate the mapping for `linear_address`
  in the VPID from `vpid`;
- `single_context = 1` — invalidate all mappings for the VPID;
- `all_contexts = 2` — invalidate all VPID-tagged mappings on the logical
  processor;
- `single_context_retaining_globals = 3` — invalidate all mappings for
  the VPID except global mappings.

Kinds 4 and higher are architecturally reserved and produce `VMfailInvalid`.

`InvvpidDescriptor` is a 16-byte `extern struct`. Alignment is raised to
16 via `align(16)` on `vpid`, and the type exposes
`pub const alignment: usize = 16`:

- `vpid: u16` at offset 0 — virtual-processor identifier;
- `_reserved_low: u16 = 0` at offset 2;
- `_reserved_high: u32 = 0` at offset 4;
- `linear_address: u64 = 0` at offset 8 — meaningful only for
  `individual_address`; ignored by other kinds.

Compile-time invariants held inside the type body:

- `@sizeOf(InvvpidDescriptor) == 16`, `@alignOf(InvvpidDescriptor) == 16`;
- `@offsetOf(InvvpidDescriptor, "vpid") == 0`;
- `@offsetOf(InvvpidDescriptor, "_reserved_low") == 2`;
- `@offsetOf(InvvpidDescriptor, "_reserved_high") == 4`;
- `@offsetOf(InvvpidDescriptor, "linear_address") == 8`.

Non-zero reserved bits produce `VMfailInvalid` per SDM.

### vmxon and vmxoff

`vmx.vmxon(region)` executes `vmxon [region]` where `region` is a
`*const PhysAddr`. SDM Vol.3 §30.3 defines the operand as an `m64`
physical-pointer operand: the CPU dereferences `region` as an ordinary
memory read to obtain the 64-bit physical address of the VMXON region.

Preconditions the wrapper does not check (caller policy):

- `CR4.VMXE = 1`;
- `CR0.NE = 1` (and other CR0/CR4 fixed-bit constraints from
  `IA32_VMX_CR0_FIXED0`/`FIXED1` and `IA32_VMX_CR4_FIXED0`/`FIXED1`);
- the physical address is 4 KiB aligned;
- the VMXON region's `revision_id` matches `IA32_VMX_BASIC[30:0]` with
  bit 31 clear;
- `IA32_FEATURE_CONTROL[VMXON_OUTSIDE_SMX]` (or the equivalent SMX bit)
  is enabled.

`vmx.vmxoff()` executes `vmxoff`. Preconditions the wrapper does not
check: the processor is in VMX root operation.

Both wrappers return `Error!void` mapped from `RFLAGS`.

### vmclear, vmptrld, and vmptrst

`vmx.vmclear(vmcs)` executes `vmclear [vmcs]` with `vmcs` a
`*const PhysAddr`. Marks the VMCS as inactive and clear on the logical
processor. Required before the first `vmptrld` for a freshly-initialized
VMCS.

`vmx.vmptrld(vmcs)` executes `vmptrld [vmcs]` with `vmcs` a
`*const PhysAddr`. Loads the VMCS pointer; the referenced region becomes
the current VMCS on the logical processor.

`vmx.vmptrst(out)` executes `vmptrst [out]` with `out` a `*PhysAddr`. The
CPU writes the current VMCS pointer into `*out`. When no VMCS is current
the CPU stores the sentinel `0xFFFFFFFFFFFFFFFF`; callers may detect the
sentinel by comparing `out.raw() == std.math.maxInt(u64)`.

All three wrappers return `Error!void` mapped from `RFLAGS`.

### vmlaunch and vmresume

`vmx.vmlaunch()` executes `vmlaunch`. Used on the first VM entry after a
`vmptrld` on a VMCS whose launch state is `clear`. `vmx.vmresume()`
executes `vmresume`. Used on subsequent VM entries against a VMCS whose
launch state is `launched`.

Both return type is `Error!noreturn`. On success the CPU transfers
control to the guest at the RIP programmed in `HOST_RIP` upon a subsequent
VM exit; the wrapper does not return to its caller through the success
path. Only the `RFLAGS`-visible failure paths return, and they return an
error before entry. Consumers that treat the fallthrough as unreachable
should still `catch |err| switch (err) { ... }` because the wrapper types
the success branch as `noreturn`, not `void`.

Programming `HOST_RIP` (VMCS encoding `0x6C16`) and `HOST_RSP`
(`0x6C14`) is caller policy performed via `vmx.vmwrite`. The wrapper
does not install a host trampoline.

### vmread and vmwrite

`vmx.vmread(encoding)` executes `vmread` with `encoding` in a
general-purpose register (SDM natural width, passed as `u64` zero-extended
from the wrapper's `u32` argument). Returns the field value as `u64`.

`vmx.vmwrite(encoding, value)` executes `vmwrite` with `encoding` and
`value` in general-purpose registers. Returns `void` on success.

`encoding` is the raw 32-bit field encoding per SDM Vol.3 Appendix B
natural-index encoding. This spec does not maintain a typed field catalog.
Field encodings whose architectural width is less than 64 bits (16-bit or
32-bit fields) are still exchanged as `u64`; the CPU zero-extends reads
and ignores upper bits on writes per SDM.

`vmx.vmread` returns `Error!u64`; `vmx.vmwrite` returns `Error!void`. Both
outcomes are mapped from `RFLAGS`. On `vmx.vmread` failure the returned
value is unspecified.

### invept and invvpid

`vmx.invept(kind, descriptor)` executes `invept kind, [descriptor]` where
`kind` is passed in a general-purpose register (from
`@intFromEnum(kind)`) and `descriptor` is a `*const InveptDescriptor`
memory operand. Invalidates EPT-derived mappings per the kind.

`vmx.invvpid(kind, descriptor)` executes `invvpid kind, [descriptor]`
analogously against VPID-tagged mappings.

Both wrappers return `Error!void` mapped from `RFLAGS`. Cross-CPU
invalidation is caller policy — `invept` and `invvpid` act only on the
issuing logical processor. IPI-based shootdown is a downstream concern.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `PhysAddr.fromInt` | never | never | O(1) | value type | none | infallible |
| `PhysAddr.raw` | never | never | O(1) | value type | none | infallible |
| `vmxon` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `vmxoff` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `vmclear` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `vmptrld` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `vmptrst` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `vmlaunch` | never | never | O(1) | reentrant | full memory clobber | `Error!noreturn` from `RFLAGS`; may `#GP`/`#UD` |
| `vmresume` | never | never | O(1) | reentrant | full memory clobber | `Error!noreturn` from `RFLAGS`; may `#GP`/`#UD` |
| `vmread` | never | never | O(1) | reentrant | full memory clobber | `Error!u64` from `RFLAGS`; may `#GP`/`#UD` |
| `vmwrite` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `invept` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |
| `invvpid` | never | never | O(1) | reentrant | full memory clobber | `Error!void` from `RFLAGS`; may `#GP`/`#UD` |

Every wrapper compiles to a fixed inline-asm fragment. No syscall, no
allocation, no lock, no target probing, no scheduler interaction.

## Ordering contract

Following `base.md`:

- Every VMX wrapper uses a memory clobber. VMX instructions read from and
  write to VMCS state that is architecturally visible to subsequent VM
  entries, VM exits, and (for VMXON) all subsequent VMX operations; the
  compiler must not reorder ordinary memory operations across a wrapper.
- Every VMX wrapper uses a `cc` clobber (or otherwise consumes `RFLAGS`)
  because the wrapper reads `RFLAGS.CF`/`ZF` immediately after the
  instruction to produce the `Error` return.
- Register clobbers follow the instruction's operand convention (e.g.
  `vmread`/`vmwrite` clobber the destination register).

The wrappers do not emit any architectural fence. Ordering between guest
state and host state around VM entries and exits is caller policy; the
architecture handles the microarchitectural ordering across VM entries.

## Trap and privilege behavior

Every VMX instruction is privileged (CPL 0). Traps distinct from
`VMfail*` reported via `Error`:

- `#GP` at CPL > 0 on every VMX wrapper.
- `#UD` when VMX is unsupported (`CPUID.1:ECX[5]` clear), `CR4.VMXE = 0`
  on instructions that require VMX operation, or when the processor is
  outside VMX operation for `vmxoff` / `vmclear` / `vmptrld` / `vmptrst`
  / `vmlaunch` / `vmresume` / `vmread` / `vmwrite` / `invept` / `invvpid`.
- `#UD` on `invept` when EPT is unsupported
  (`IA32_VMX_EPT_VPID_CAP[0]` clear).
- `#UD` on `invvpid` when VPID is unsupported
  (`IA32_VMX_EPT_VPID_CAP[32]` clear).
- Architectural traps on `vmread`/`vmwrite` when executed without a
  current VMCS return `VMfailInvalid` (not `#UD`).

Trap recovery is owned by the host OS, firmware, or hypervisor. The
wrappers do not install handlers or catch faults.


## Testing

Compile-time tests MUST verify the exact `Error` tags; `PhysAddr` round trips; the 4 KiB size, 4 KiB alignment, and field offsets of `VmxonRegion` and `Vmcs`; the 16-byte size, 16-byte alignment, and field offsets of both invalidation descriptors; and the exact open-enum values for invalidation kinds. Portable-layout tests MUST compile value types on every target. x86_64 compile tests MUST instantiate every wrapper with its declared signature. Non-x86_64 tests MUST verify facade import succeeds and each assembly wrapper fails only when referenced. These tests prove error representation, ABI layout, public signatures, and target gating; the default host suite MUST NOT execute VMX instructions because execution requires CPL 0 and VMX operation.
