# x86_64 SVM ISA wrappers

Status: Approved.

`stdx.arch.x86_64.svm` owns thin, inline-asm-only wrappers for AMD SVM
(Secure Virtual Machine) instructions. Consumers reach every primitive through the lower-case `stdx.arch.x86_64.svm` namespace.

Every wrapper models exactly one instruction with the same "just the ISA,
no policy" contract as `docs/specs/arch/x86_64/base.md` and
`docs/specs/arch/x86_64/vmx.md`. Unlike VMX, SVM instructions do not use
`RFLAGS.CF`/`ZF` to report failure; faults surface as CPU exceptions
(`#UD`, `#GP`). Every wrapper's Zig signature is therefore infallible.

## Owned scope

This spec owns:

- `svm.PhysAddr` — strong physical-address value type;
- `svm.Vmcb` — 4 KiB `extern struct` VMCB region type, split into
  `control` and `state` byte arrays at the architectural offsets;
- wrappers `vmrun`, `vmload`, `vmsave`, `stgi`, `clgi`, `invlpga`,
  `skinit`;
- target gating and compile-out behavior consistent with `base.md` and `vmx.md`;
- privilege documentation and trap behavior;
- required tests (compile-only in the default host suite).

## Deferred scope and non-goals

This spec does not own:

- VMCB field layouts — the control area (offset 0x000–0x3FF) and state
  save area (offset 0x400–0xFFF) are exposed as byte arrays; consumers
  overlay their own typed structs;
- decoded VMEXIT reasons (`EXITCODE`), event-injection encoding, TLB
  control encoding, interrupt control (`V_TPR`/`V_INTR_*`) encoding,
  or nested paging (`nCR3`) programming policy;
- NPT paging structures and NPT permission encoding (future owner:
  `docs/specs/arch/x86_64/paging-slat-npt.md` /
  `stdx.arch.x86_64.paging.slat.npt`);
- ASID allocation policy;
- host save area type — the host save area referenced by
  `VM_HSAVE_PA` MSR has no architecturally normative fields
  (CPU-implementation-defined body); caller supplies a 4 KiB page;
- `VM_HSAVE_PA` MSR programming or any other MSR write — MSR access is
  handled by `docs/specs/arch/x86_64/base.md`'s `Msr` type;
- CR4/EFER programming (`EFER.SVME`), CR4 fixed-bit constraints;
- feature detection of SVM, NPT, ASID width, SKINIT, or DecodeAssists —
  deferred to `docs/specs/arch/x86_64/cpuid.md`;
- `vmmcall` — guest-side hypercall issued by guest code, not host code;
  add later if a consumer needs it;
- SEV, SEV-ES, or SEV-SNP extensions (VMSA structure, GHCB layout,
  encrypted guest register state);
- runtime execution on the host test suite — SVM instructions require
  CPL 0 with `EFER.SVME = 1`, which the host runner cannot provide;
- root promotion of any svm symbol.

## Public namespace

`stdx.arch.x86_64.svm` is the public SVM namespace:

```zig
stdx.arch.x86_64.svm
stdx.arch.x86_64.svm.PhysAddr
stdx.arch.x86_64.svm.Vmcb
```

None are root-promoted. Consumers reach SVM primitives only through the
`stdx.arch.x86_64.svm` path.

`svm.PhysAddr` and `stdx.arch.x86_64.vmx.PhysAddr` are distinct types.

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/svm.zig
test/arch/x86_64_svm_test.zig   ← separate test file
```

`src/arch/x86_64.zig` re-exports `pub const svm = @import("x86_64/svm.zig");`.

## Target gating

Same rule as `base.md` and `vmx.md`: `stdx.arch.x86_64`
compiles on any target. Any operation added by this spec that would emit
x86_64 inline assembly produces a compile error when referenced on a
non-x86_64 target.

Operations whose semantics do not depend on the instruction set —
`PhysAddr.fromInt`/`raw` and the `Vmcb` region type — compile on any
target so type layouts and constants remain portable.

## Approved API

```zig
pub const svm = struct {
    pub const PhysAddr = enum(u64) {
        _,

        pub fn fromInt(value: u64) PhysAddr;
        pub fn raw(self: PhysAddr) u64;
    };

    pub const Vmcb = extern struct {
        control: [1024]u8 align(4096),
        state: [3072]u8,

        pub const alignment: usize = 4096;
    };

    pub fn vmrun(vmcb: PhysAddr) void;
    pub fn vmload(vmcb: PhysAddr) void;
    pub fn vmsave(vmcb: PhysAddr) void;

    pub fn stgi() void;
    pub fn clgi() void;

    pub fn invlpga(virt_addr: u64, asid: u32) void;

    pub fn skinit(base: u32) noreturn;
};
```

## Semantics

### Error convention

SVM does not use the VMX `RFLAGS.CF`/`ZF` failure convention. Fault
conditions surface as CPU exceptions raised at instruction execution:

- `#UD` when SVM is unsupported (`CPUID.8000_0001:ECX[2]` clear) or when
  `EFER.SVME = 0`;
- `#GP` at CPL > 0 (SVM instructions are privileged);
- `#GP` on VMCB rule violations — misaligned VMCB physical address,
  reserved-bit violations in VMCB control fields, or state-save-area
  values that violate architectural constraints when consumed by
  `vmrun`;
- `#GP` on `skinit` when SKINIT is unsupported or `EFER.SVME = 0` in a
  configuration that requires it.

All exceptions are handled by the host's trap handler; the wrapper does
not model them via an error union. Every wrapper's Zig signature is
`void` (or `noreturn` for `skinit`).

### PhysAddr

`svm.PhysAddr` is an opaque physical-address value type covering the full
64-bit physical-address space.

- `PhysAddr.fromInt(value)` is infallible and compiles on any target.
- `PhysAddr.raw(self)` returns the exact `u64` and compiles on any target.
- The declaration is `enum(u64) { _ }` matching the strong-value pattern
  used by `Port`, `Msr`, and `stdx.arch.x86_64.vmx.PhysAddr`.

`PhysAddr` values passed to SVM wrappers must satisfy the CPU's
architectural alignment for the target instruction — 4 KiB alignment for
VMCB pointers passed to `vmrun` / `vmload` / `vmsave`. Misalignment
raises `#GP` and is caller policy.

SVM wrappers MUST take `PhysAddr` by value. The AMD SVM operand encoding
places the physical address in `RAX` (an `m64` register operand, not
memory-indirect).

### Vmcb

`svm.Vmcb` is a 4 KiB `extern struct`. Alignment is raised to 4096 via a
field-level `align(4096)` on `control`, and the type exposes
`pub const alignment: usize = 4096`. Its body is split at the architectural
boundary AMD APM Vol.2 §15.5 defines:

- `control: [1024]u8` at offset `0x000` — VMCB control area (intercept
  vectors, TLB control, guest ASID, VMEXIT information, event injection,
  interrupt shadow, nested paging control, `VMCB_STATE_SAVE_AREA_OFFSET`
  and adjacent fields);
- `state: [3072]u8` at offset `0x400` — VMCB state save area (guest
  register state, segment descriptors, control registers, RIP, RSP,
  RFLAGS).

Consumers overlay their own typed structs on either area. The stdx layer
owns only size, alignment, and the architectural split; field layouts
inside each area are downstream policy consistent with the "no VMCB
field catalog" deferred-scope entry.

Compile-time invariants held inside the type body:

- `@sizeOf(Vmcb) == 4096`, `@alignOf(Vmcb) == 4096`;
- `@offsetOf(Vmcb, "control") == 0x000`;
- `@offsetOf(Vmcb, "state") == 0x400`.

The field-level `align(4096)` on `control` provides the 4 KiB VMCB
alignment SVM requires.

`Vmcb` compiles on any target because it emits no inline assembly. Only
the wrappers that consume its physical-address pointer require x86_64.

### vmrun

`svm.vmrun(vmcb)` executes `vmrun`. The instruction enters guest
execution using the VMCB whose physical address is passed in `RAX`.

On `#VMEXIT`, the CPU restores host state from the host save area
identified by the `VM_HSAVE_PA` MSR (address `0xC001_0117`), then resumes
host execution at the instruction following the `vmrun` (AMD APM Vol.2
§15.5.1). The wrapper's Zig return type is `void`, not `noreturn`.

Preconditions the wrapper does not check (caller policy):

- `EFER.SVME = 1`;
- `VM_HSAVE_PA` programmed with a caller-owned 4 KiB host save area;
- VMCB is 4 KiB aligned and populated per APM Vol.2 §15.5;
- interrupts are handled per the caller's global-interrupt policy
  (`STGI`/`CLGI` bracket).

The wrapper uses a memory clobber. VMCB state written by the CPU on
`#VMEXIT` (exit code, exit info, updated guest state) is architecturally
visible to subsequent host code through ordinary loads; the compiler
must not reorder host memory operations across `vmrun`.

Typical host loop:

```zig
while (true) {
    prepareGuest(&vmcb);
    svm.vmrun(vmcb_phys);
    handleVmExit(&vmcb);
}
```

### vmload and vmsave

`svm.vmload(vmcb)` executes `vmload`. Loads a subset of processor state
from the VMCB state save area:

- `FS`, `GS`, `TR`, `LDTR` selectors, attributes, limits, and 64-bit
  bases;
- `KernelGSBase` (MSR `0xC000_0102`);
- `STAR`, `LSTAR`, `CSTAR`, `SF_MASK` (SYSCALL MSRs);
- `SYSENTER_CS`, `SYSENTER_ESP`, `SYSENTER_EIP`.

`svm.vmsave(vmcb)` executes `vmsave` and saves the same set from the
processor into the VMCB state save area.

Typical use pattern brackets `vmrun` to preserve host state that
`vmrun`/`#VMEXIT` do not automatically save:

```zig
svm.vmsave(host_save_phys);   // capture host-side state
svm.vmrun(guest_vmcb_phys);
svm.vmload(host_save_phys);   // restore host-side state
```

Both wrappers use a memory clobber.

### stgi and clgi

`svm.stgi()` executes `stgi` (Set Global Interrupt flag). `svm.clgi()`
executes `clgi` (Clear Global Interrupt flag). The Global Interrupt Flag
(GIF) gates interrupt delivery at a broader granularity than `EFLAGS.IF`
— when GIF is clear, the CPU blocks maskable interrupts, NMI, SMI,
INIT, and machine-check exceptions.

Both instructions require SVM to be enabled (`EFER.SVME = 1`) and are
privileged (CPL 0).

Both wrappers use a memory clobber to prevent the compiler from reordering
memory operations across the boundary.

Typical use:

```zig
svm.clgi();
// Sensitive host code — global interrupt delivery is disabled.
svm.stgi();
```

### invlpga

`svm.invlpga(virt_addr, asid)` executes `invlpga`. The instruction
invalidates one TLB entry for the linear address `virt_addr` in the
ASID (Address Space Identifier) `asid` on the current logical processor.

The wrapper's argument widths MUST be `u64` for `virt_addr` and `u32` for
`asid`, matching the architectural operand widths.

`invlpga` does not invalidate entries on other CPUs; cross-CPU shootdown
is caller policy. The wrapper uses a memory clobber to prevent the
compiler from reordering TLB-invalidation with surrounding memory
operations, matching the `cpu.tlb.invalidatePage` convention in
`docs/specs/arch/x86_64/cpu.md`.

The wrapper accepts a raw `u32` ASID. ASID allocation is caller policy.

### skinit

`svm.skinit(base)` executes `skinit`. The instruction initiates a
Secure Loader (SL) launch on AMD SKINIT-capable processors: it clears
processor state, performs a DEV-protected TPM measurement of the SL
image, and transfers control to the SL image at offset 0 from the
physical base address in `EAX`.

The `base` argument MUST be `u32`. SKINIT requires the SL image to reside
in the first 4 GiB of physical memory.

Preconditions the wrapper does not check (caller policy):

- SKINIT supported (`CPUID.8000_0001:ECX[12]`);
- SL image validly signed and formatted per the AMD SKINIT
  specification;
- interrupts disabled or handled per SL requirements.

The wrapper uses a memory clobber.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `PhysAddr.fromInt` | never | never | O(1) | value type | none | infallible |
| `PhysAddr.raw` | never | never | O(1) | value type | none | infallible |
| `vmrun` | never | never | O(guest execution) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `vmload` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `vmsave` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `stgi` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `clgi` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `invlpga` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `skinit` | never | never | (noreturn) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |

Every wrapper compiles to a fixed inline-asm fragment. No syscall, no
allocation, no lock, no target probing, no scheduler interaction.

The `vmrun` row's "O(guest execution)" bound reflects that the wrapper
does not return until the guest issues a `#VMEXIT`.

## Ordering contract

Following `base.md` and `vmx.md`:

- Every SVM wrapper uses a memory clobber. VMCB state, MSR-tracked host
  state, and TLB contents modified by the wrapped instruction are
  architecturally visible to subsequent host code through ordinary
  memory access; the compiler must not reorder host memory operations
  across a wrapper.
- Register clobbers follow each instruction's operand convention:
  `vmrun`/`vmload`/`vmsave` consume `RAX`; `invlpga` consumes `RAX`
  (linear address) and `RCX` (ASID); `skinit` consumes `EAX`. `stgi`
  and `clgi` have no register operands.
- SVM wrappers do not consume `RFLAGS` in the Zig signature. Unlike VMX
  wrappers, SVM instructions do not report failure through `RFLAGS`, so
  the wrapper does not carry a `cc` clobber for status extraction; the
  compiler may still track its own `RFLAGS` usage per standard inline-asm
  rules.

The wrappers emit no architectural fence. Guest / host state ordering
around `vmrun` is handled by the microarchitecture on VM entry and exit;
memory ordering between host CPU code and any DMA agent is caller policy
(see `docs/specs/barrier/dma.md`).

## Trap and privilege behavior

Every SVM instruction is privileged (CPL 0). Traps distinct from any
error-union return:

- `#GP` at CPL > 0 on every wrapper.
- `#UD` when SVM is unsupported (`CPUID.8000_0001:ECX[2]` clear) or
  `EFER.SVME = 0`.
- `#GP` on `vmrun` / `vmload` / `vmsave` when the VMCB physical address
  is misaligned or the VMCB violates architectural constraints
  (reserved-bit violations, illegal segment attributes, illegal control
  register values, etc.).
- `#UD` on `skinit` when SKINIT is unsupported
  (`CPUID.8000_0001:ECX[12]` clear).

Trap recovery is owned by the host OS, firmware, or hypervisor. The
wrappers do not install handlers or catch faults. Wrapping SVM
instructions inside interrupt-off regions is caller policy.

## Amendments

None.

## Examples

Prepare and enter a guest, dispatch on VM exit:

```zig
const stdx = @import("stdx");
const x86 = stdx.arch.x86_64;
const svm = x86.svm;

// Caller-owned VMCB (typically page-aligned in a page allocator).
var vmcb: svm.Vmcb = std.mem.zeroes(svm.Vmcb);
const vmcb_phys: svm.PhysAddr = .fromInt(physicalAddressOf(&vmcb));

// Program VMCB control and state areas via overlays owned by the
// consumer (not by stdx). See AMD APM Vol.2 §15.5 for layouts.
consumerProgramVmcb(&vmcb, guest_state);

while (true) {
    svm.vmrun(vmcb_phys);           // returns after #VMEXIT
    const exit_code = consumerReadExitCode(&vmcb);
    if (consumerHandleVmExit(&vmcb, exit_code)) break;
}
```

Bracket sensitive host code with GIF clear:

```zig
svm.clgi();
// Global interrupt delivery is masked here.
performSensitiveHostOperation();
svm.stgi();
```

Preserve host state around a `vmrun`:

```zig
const host_save_phys: svm.PhysAddr = .fromInt(physicalAddressOf(host_save_area));

svm.vmsave(host_save_phys);
svm.vmrun(vmcb_phys);
svm.vmload(host_save_phys);
```

Invalidate one TLB entry in a guest ASID:

```zig
svm.invlpga(guest_linear_addr, guest_asid);
```

Launch a Secure Loader image (typically from an initial boot loader):

```zig
svm.skinit(sl_image_physical_base);
// unreachable — control transfers to the SL image.
```

## Required tests

Tests live in `test/arch/x86_64_svm_test.zig`. Every test is compile-only
in the default host suite. Runtime execution requires CPL 0 with
`EFER.SVME = 1`, which the host runner cannot provide; a privileged
runner is outside this spec's scope.

Required tests:

- `PhysAddr.fromInt`/`raw` round-trip for `0`, a non-zero mid value, and
  `std.math.maxInt(u64)`; the round-trip compiles on any target;
- `@sizeOf(svm.Vmcb) == 4096`, `@alignOf(svm.Vmcb) == 4096`,
  `svm.Vmcb.alignment == 4096`;
- `@offsetOf(svm.Vmcb, "control") == 0x000`;
- `@offsetOf(svm.Vmcb, "state") == 0x400`;
- `svm.Vmcb` compiles on any target (portable value type);
- On x86_64, every wrapper instantiates with the declared signature:
  - `svm.vmrun(svm.PhysAddr) void`;
  - `svm.vmload(svm.PhysAddr) void`;
  - `svm.vmsave(svm.PhysAddr) void`;
  - `svm.stgi() void`;
  - `svm.clgi() void`;
  - `svm.invlpga(u64, u32) void`;
  - `svm.skinit(u32) noreturn`;
- Non-x86_64 build: importing `stdx.arch.x86_64` compiles; every
  asm-emitting wrapper produces a compile error only when referenced,
  matching `base.md`/`vmx.md` gating.

The default host test suite must not execute any SVM instruction.

## Open questions

None.
