# x86_64 register access

Status: Approved.

`stdx.arch.x86_64.registers` owns direct x86_64 register access, canonical packed register representations,
and register-specific decoding and validation. Each register namespace owns its value type, semantics, and
direct access instructions. The namespace does not capture complete machine state.

## Owned scope

This specification owns:

- `stdx.arch.x86_64.registers`;
- direct register namespaces: `registers.{cr0,cr2,cr3,cr4,cr8,xcr0,rflags,efer}`;
- segment namespaces: `registers.{cs,ds,es,fs,gs,ss,fs_base,gs_base}`;
- descriptor namespaces: `registers.{gdtr,idtr,tr,ldtr}`;
- debug namespaces: `registers.dr0..dr7`;
- CR3 low-bit, page-table-base, LAM, and no-flush semantics;
- CR4 paging-control and EFER execute-disable semantics;
- target gating, privilege and fault documentation, ordering contracts, and tests.

## Deferred scope and non-goals

This specification does not own:

- general-purpose register, instruction-pointer, XSAVE, FPU, vector, PMU, or generic MSR capture;
- a flat register-state structure, partial-state availability, or backend capture adapters;
- hidden segment state such as effective base, limit, attributes, or unusable state;
- descriptor-entry layouts, GDT/IDT/LDT/TSS builders, or allocation;
- CPU feature probing, paging translation, trap recovery, or system policy;
- interrupt, privilege, debug, VMX, or SVM policy.

## Public namespace

```zig
stdx.arch.x86_64.registers
stdx.arch.x86_64.registers.cr0
stdx.arch.x86_64.registers.cr3
stdx.arch.x86_64.registers.efer
stdx.arch.x86_64.registers.rflags
stdx.arch.x86_64.registers.cs
stdx.arch.x86_64.registers.gdtr
stdx.arch.x86_64.registers.dr0
```

## Source ownership

```text
src/arch/x86_64/registers.zig
src/arch/x86_64/register/control.zig
src/arch/x86_64/register/efer.zig
src/arch/x86_64/register/rflags.zig
src/arch/x86_64/register/segment.zig
src/arch/x86_64/register/descriptor.zig
src/arch/x86_64/register/debug.zig
test/arch/x86_64/registers/all.zig
test/arch/x86_64/registers/control_test.zig
test/arch/x86_64/registers/efer_test.zig
test/arch/x86_64/registers/rflags_test.zig
test/arch/x86_64/registers/segment_test.zig
test/arch/x86_64/registers/descriptor_test.zig
test/arch/x86_64/registers/debug_test.zig
```

`registers.zig` is a thin facade. It re-exports register namespaces. Each domain module owns its packed
layouts, register-specific semantics, and access instructions.

## Register representations

Every scalar register type is a `packed struct` with the register's exact backing width. Every architectural
bit has one field. Reserved and mode-dependent ranges use explicit `_reserved*` or raw storage fields.
`fromInt` preserves every input bit. `raw` returns every stored bit unchanged. Semantic methods validate or
decode a value without changing its raw representation.

The public type family is:

```zig
registers.cr0.CR0
registers.cr2.CR2
registers.cr3.CR3
registers.cr4.CR4
registers.cr8.CR8
registers.xcr0.XCR0
registers.rflags.RFLAGS
registers.efer.EFER

registers.cs.CS
registers.ds.DS
registers.es.ES
registers.fs.FS
registers.gs.GS
registers.ss.SS
registers.tr.TR
registers.ldtr.LDTR
registers.fs_base.FSBase
registers.gs_base.GSBase

registers.gdtr.GDTR
registers.idtr.IDTR

registers.dr0.DR0
registers.dr1.DR1
registers.dr2.DR2
registers.dr3.DR3
registers.dr4.DR4
registers.dr5.DR5
registers.dr6.DR6
registers.dr7.DR7
registers.dr7.Breakpoint
```

`CS`, `DS`, `ES`, `FS`, `GS`, `SS`, `TR`, and `LDTR` have the same selector field layout but are distinct
types. `GDTR` and `IDTR` have the same 10-byte pseudo-descriptor layout but are distinct types.

### Field and semantic ownership

`CR0`, `CR4`, `CR8`, `XCR0`, `RFLAGS`, `EFER`, `DR6`, and `DR7` expose architecturally named bit fields.
`CR2`, `FSBase`, `GSBase`, and `DR0` through `DR5` expose their raw architectural quantity as one named field.

`CR3` exposes fixed storage fields: `low_bits`, `page_table_base`, `lam_u57`, `lam_u48`, and `no_flush`.
The `CR3` type owns:

- its semantic error and result types;
- `low_bits` interpretation as a PCID when `CR4.PCIDE` is set;
- `low_bits` interpretation as PWT/PCD cache controls when `CR4.PCIDE` is clear;
- paging-root address extraction and `MAXPHYADDR` validation;
- rejection of nonzero reserved bits 60:52;
- `LAM_U48` and `LAM_U57` capability validation and user LAM-mode selection;
- the rule that `no_flush` is a write-operand qualifier and cannot appear in stored CR3 state.

`CR4` owns validation of `PCIDE`, `LA57`, and `LAM_SUP` against caller-supplied capability facts.
`CR4.supervisorLAM` returns `.disabled` when `LAM_SUP` is clear, `.u48` for 4-level paging, and `.u57` for
5-level paging.

`EFER` exposes the complete 64-bit extended-feature-enable register layout. `EFER.executeDisableEnabled`
validates `EFER.NXE` against caller-supplied execute-disable capability.

`Breakpoint` is a packed 4-bit value with `condition` in bits 0–1 and `length` in bits 2–3. `DR7` exposes
`br0`, `br1`, `br2`, and `br3` as `Breakpoint` values in bits 16–19, 20–23, 24–27, and 28–31.

Packed register values preserve raw state. Callers use the owning register's semantic methods before they
consume or write feature-dependent fields. Higher-level modules must not duplicate register bit decoding or
register validity rules.

### Initialization

Every register representation provides `init()`. The constructor returns the canonical default bit representation without validation or hardware access.

`init()` returns zero except:

- `CR0.init()` sets `extension_type`.
- `XCR0.init()` sets `x87`.
- `RFLAGS.init()` and `DR7.init()` set `fixed_one`.

`init()` does not produce a value that is safe to write in every CPU mode. Callers must still satisfy feature, privilege, reserved-bit, and cross-register constraints.

## API

```zig
pub const cr0 = struct { pub const CR0: type; pub fn read() CR0; pub fn write(value: CR0) void; };
pub const cr2 = struct { pub const CR2: type; pub fn read() CR2; pub fn write(value: CR2) void; };

pub const cr3 = struct {
    pub const AddressError: type;
    pub const Error: type;
    pub const LAMMode: type;
    pub const Cache: type;
    pub const Low: type;
    pub const PageTable: type;
    pub const CR3: type;

    pub fn read() CR3;
    pub fn write(value: CR3) void;
};

pub const cr4 = struct {
    pub const Error: type;
    pub const CR4: type;

    pub fn read() CR4;
    pub fn write(value: CR4) void;
};

pub const efer = struct {
    pub const Error: type;
    pub const EFER: type;

    pub fn read() EFER;
    pub fn write(value: EFER) void;
};

pub const cr8 = struct { pub const CR8: type; pub fn read() CR8; pub fn write(value: CR8) void; };
pub const xcr0 = struct { pub const XCR0: type; pub fn read() XCR0; pub fn write(value: XCR0) void; };
pub const rflags = struct { pub const RFLAGS: type; pub fn read() RFLAGS; pub fn write(value: RFLAGS) void; };

pub const cs = struct { pub const CS: type; pub fn read() CS; pub fn writeFarReturn(value: CS) void; };
pub const ds = struct { pub const DS: type; pub fn read() DS; pub fn write(value: DS) void; };
pub const es = struct { pub const ES: type; pub fn read() ES; pub fn write(value: ES) void; };
pub const fs = struct { pub const FS: type; pub fn read() FS; pub fn write(value: FS) void; };
pub const gs = struct { pub const GS: type; pub fn read() GS; pub fn write(value: GS) void; };
pub const ss = struct { pub const SS: type; pub fn read() SS; pub fn write(value: SS) void; };
pub const fs_base = struct { pub const FSBase: type; pub fn read() FSBase; pub fn write(value: FSBase) void; };
pub const gs_base = struct { pub const GSBase: type; pub fn read() GSBase; pub fn write(value: GSBase) void; pub fn swap() void; };

pub const gdtr = struct { pub const GDTR: type; pub fn read() GDTR; pub fn write(value: GDTR) void; };
pub const idtr = struct { pub const IDTR: type; pub fn read() IDTR; pub fn write(value: IDTR) void; };
pub const tr = struct { pub const TR: type; pub fn read() TR; pub fn write(value: TR) void; };
pub const ldtr = struct { pub const LDTR: type; pub fn read() LDTR; pub fn write(value: LDTR) void; };

pub const dr0 = struct { pub const DR0: type; pub fn read() DR0; pub fn write(value: DR0) void; };
// DR1 through DR7 follow the same pattern with their corresponding type.
```

`CR3` provides these nested semantic types and methods:

```zig
pub const TableBaseError = error{
    InvalidPhysicalAddressWidth,
    PhysicalAddressTooWide,
    ReservedBits,
};

pub const LowError = error{ReservedLowBits};
pub const LAMError = error{UnsupportedLAM};

pub fn tableBaseAddress(self: CR3, physical_address_bits: u8) TableBaseError!addr.PhysAddr;
pub fn low(self: CR3, pcid_enabled: bool) LowError!Low;
pub fn userLAM(self: CR3, lam_supported: bool) LAMError!LAMMode;
```

`CR3.TableBaseError`, `CR3.LowError`, `CR3.LAMError`, `CR3.LAMMode`, `CR3.Low`, and `CR3.Cache` are owned
by `CR3`. The `cr3` namespace does not duplicate these declarations.

`tableBaseAddress` accepts `physical_address_bits` in the inclusive range 32 through 52. It returns
`error.InvalidPhysicalAddressWidth` outside that range, `error.ReservedBits` when bits 60:52 are nonzero,
and `error.PhysicalAddressTooWide` when the stored paging-table base uses a bit at or above
`physical_address_bits`. The returned physical address is 4 KiB aligned because CR3 stores only address
bits 51:12.

`low` returns `.pcid = low_bits` when `pcid_enabled` is true. Otherwise, bits other than PWT at bit 3 and
PCD at bit 4 must be zero, and the method returns `.cache`. A violation returns
`error.ReservedLowBits`.

`userLAM` returns `.u57` when `lam_u57` is set, including when both LAM bits are set. It returns `.u48` when
only `lam_u48` is set and `.disabled` when both fields are clear. A selected LAM mode without LAM capability
returns `error.UnsupportedLAM`.

`no_flush` represents the bit 63 qualifier accepted by a CR3 write. A caller that interprets a value as
stored CR3 state must reject `no_flush == true`. A caller that writes CR3 must enforce the architectural
PCID and transition rules before it calls the raw `cr3.write` operation.

`CR4` provides these semantic methods:

```zig
pub const PCIDError = error{UnsupportedPCID};
pub const Level5Error = error{UnsupportedFiveLevelPaging};
pub const SupervisorLAMError = error{UnsupportedLAM};

pub fn pcidEnabled(self: CR4, pcid_supported: bool) PCIDError!bool;
pub fn level5Enabled(self: CR4, level5_supported: bool) Level5Error!bool;
pub fn supervisorLAM(
    self: CR4,
    lam_supported: bool,
) SupervisorLAMError!registers.cr3.CR3.LAMMode;
```

Each method returns the decoded control when it is disabled or supported. An enabled unsupported control
returns `error.UnsupportedPCID`, `error.UnsupportedFiveLevelPaging`, or `error.UnsupportedLAM`, respectively.

`EFER` provides:

```zig
pub fn executeDisableEnabled(self: EFER, execute_disable_supported: bool) Error!bool;
```

The method returns the `execute_disable_enable` field when it is clear or supported. An enabled unsupported
control returns `error.UnsupportedExecuteDisable`.

The descriptor-register wrappers use distinct operand types and map to instructions as follows:

| Typed operation | Instruction |
| --- | --- |
| `gdtr.write(value: GDTR)` | `lgdt` |
| `gdtr.read() GDTR` | `sgdt` |
| `idtr.write(value: IDTR)` | `lidt` |
| `idtr.read() IDTR` | `sidt` |
| `tr.write(value: TR)` | `ltr` |
| `tr.read() TR` | `str` |
| `ldtr.write(value: LDTR)` | `lldt` |
| `ldtr.read() LDTR` | `sldt` |

`GDTR` and `IDTR` are distinct 10-byte pseudo-descriptor types. `TR` and `LDTR` are distinct 16-bit selector types. A wrapper MUST NOT accept the operand type of another descriptor register.

## Behavior contract

Direct register-access operations are fixed instruction wrappers. No direct operation allocates, blocks,
sleeps, spins, probes CPU features, installs a handler, validates a register value, or recovers from a trap.
Semantic methods are pure, bounded validation and decoding operations.

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `cr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` or `#UD` |
| `cr*.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |
| `efer.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` |
| `efer.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `rflags.read` | never | never | O(1) | reentrant | none | infallible |
| `rflags.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `{cs,ds,es,fs,gs,ss,fs_base,gs_base}.read` | never | never | O(1) | reentrant | none | infallible |
| `{cs,ds,es,fs,gs,ss,fs_base,gs_base}.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |
| `gs_base.swap` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `{gdtr,idtr,tr,ldtr}.read` | never | never | O(1) | reentrant | none | infallible |
| `{gdtr,idtr,tr,ldtr}.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `dr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` or `#UD` |
| `dr*.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |
| register semantic methods | never | never | O(1) | reentrant | none | explicit error sets |

## Target gating and faults

The module imports on every target. An operation that emits x86_64 assembly produces a compile error when
referenced on another target. Layout-only register types compile on every target.

Privileged access may raise CPU exceptions. Control, debug, descriptor-load, segment-write, and EFER
operations can raise `#GP`. `xcr0`, FSGSBASE access, and debug-register access can also raise `#UD` when
their architectural requirements are absent. Trap recovery is caller policy.

## Testing

Representation tests MUST verify exact backing widths, `fromInt`/`raw` round trips, named-field placement, selector type separation, and the documented `GDTR` and `IDTR` size, alignment, and offsets. Semantic tests MUST cover CR3 physical-width bounds, reserved bits, low-bit decoding, LAM precedence and capability failures; CR4 capability validation; and EFER execute-disable validation. Compile-time signature tests MUST reject incompatible descriptor-register operand types. An x86_64 compile fixture MUST generate code for `lgdt`, `sgdt`, `lidt`, `sidt`, `ltr`, `str`, `lldt`, and `sldt` through their typed wrappers. Other compile-time tests MUST instantiate each privileged wrapper on x86_64 and verify non-x86_64 use-site target gating. Host-safe runtime tests MUST verify that `rflags.read()` reports architectural RFLAGS bit 1 set. These tests prove raw-representation preservation, validation errors, ABI layouts, type safety, target gating, and host-safe access behavior.

## Sources

The packed layouts follow the Intel 64 and IA-32 Architectures Software Developer's Manual and AMD64 Architecture Programmer's Manual, Volume 2. This specification MUST be revised when either architecture assigns a represented reserved field.
