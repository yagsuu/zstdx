# x86_64 register access

Status: Approved.

`stdx.arch.x86_64.registers` owns direct x86_64 register access and the canonical packed representation of each supported architectural register. Each register namespace owns its value type and its direct instructions. The namespace does not capture complete machine state.

## Owned scope

This specification owns:

- `stdx.arch.x86_64.registers`;
- direct register namespaces: `registers.{cr0,cr2,cr3,cr4,cr8,xcr0,rflags}`;
- segment namespaces: `registers.{cs,ds,es,fs,gs,ss,fs_base,gs_base}`;
- descriptor namespaces: `registers.{gdtr,idtr,tr,ldtr}`;
- debug namespaces: `registers.dr0..dr7`;
- target gating, privilege and fault documentation, ordering contracts, and tests.

## Deferred scope and non-goals

This specification does not own:

- general-purpose register, instruction-pointer, XSAVE, FPU, vector, PMU, or generic MSR capture;
- a flat register-state structure, partial-state availability, or backend capture adapters;
- hidden segment state such as effective base, limit, attributes, or unusable state;
- descriptor-entry layouts, GDT/IDT/LDT/TSS builders, or allocation;
- validation, normalization, feature probing, or trap recovery;
- CR3 paging-mode, PCID, physical-width, or reserved-bit policy; `paging` owns that interpretation;
- interrupt, privilege, debug, VMX, or SVM policy.

## Public namespace

```zig
stdx.arch.x86_64.registers
stdx.arch.x86_64.registers.cr0
stdx.arch.x86_64.registers.rflags
stdx.arch.x86_64.registers.cs
stdx.arch.x86_64.registers.gdtr
stdx.arch.x86_64.registers.dr0
```

No register name is root-promoted.

## Source ownership

```text
src/arch/x86_64/registers.zig
src/arch/x86_64/register/control.zig
src/arch/x86_64/register/rflags.zig
src/arch/x86_64/register/segment.zig
src/arch/x86_64/register/descriptor.zig
src/arch/x86_64/register/debug.zig
test/arch/x86_64_test.zig
```

`registers.zig` is a thin facade. It re-exports direct register namespaces. Each domain module owns its packed layouts and instructions.

## Register representations

Every scalar register type is a `packed struct` with the register's exact backing width. Every architectural bit has one field. Reserved and mode-dependent ranges use explicit `_reserved*` or raw storage fields. `fromInt` preserves every input bit. `raw` returns every stored bit unchanged.

The public type family is:

```zig
registers.cr0.CR0
registers.cr2.CR2
registers.cr3.CR3
registers.cr4.CR4
registers.cr8.CR8
registers.xcr0.XCR0
registers.rflags.RFLAGS

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

`CS`, `DS`, `ES`, `FS`, `GS`, `SS`, `TR`, and `LDTR` have the same selector field layout but are distinct types. `GDTR` and `IDTR` have the same 10-byte pseudo-descriptor layout but are distinct types.

### Field ownership

`CR0`, `CR4`, `CR8`, `XCR0`, `RFLAGS`, `DR6`, and `DR7` expose architecturally named bit fields. `CR2`, `FSBase`, `GSBase`, and `DR0` through `DR5` expose their raw architectural quantity as one named field.

`CR3` exposes fixed storage fields: `low_bits`, `page_table_base`, `lam_u57`, `lam_u48`, and `no_flush`. The low field is PCID or page-cache-control state according to paging configuration. Consumers must use `paging` to interpret or construct a valid CR3 value.

`Breakpoint` is a packed 4-bit value with `condition` in bits 0–1 and `length` in bits 2–3. `DR7` exposes `br0`, `br1`, `br2`, and `br3` as `Breakpoint` values in bits 16–19, 20–23, 24–27, and 28–31.

The packed shape documents bit placement. It does not make a value legal to write. Feature, mode, privilege, reserved-bit, and cross-register constraints remain the responsibility of the owning semantic module or caller.

### Initialization

Every register representation provides `init()`. The constructor returns the canonical default bit representation without validation or hardware access.

`init()` returns zero except:

- `CR0.init()` sets `extension_type`.
- `XCR0.init()` sets `x87`.
- `RFLAGS.init()` and `DR7.init()` set `fixed_one`.

`init()` does not produce a value that is safe to write in every CPU mode. Callers must still satisfy feature, privilege, reserved-bit, and cross-register constraints.

## Approved API

```zig
pub const cr0 = struct { pub const CR0: type; pub fn read() CR0; pub fn write(value: CR0) void; };
pub const cr2 = struct { pub const CR2: type; pub fn read() CR2; pub fn write(value: CR2) void; };
pub const cr3 = struct { pub const CR3: type; pub fn read() CR3; pub fn write(value: CR3) void; };
pub const cr4 = struct { pub const CR4: type; pub fn read() CR4; pub fn write(value: CR4) void; };
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

`gdtr.read` and `idtr.read` emit `sgdt` and `sidt`. `gdtr.write` and `idtr.write` emit `lgdt` and `lidt`.

## Behavior contract

Every operation is a fixed instruction wrapper. No operation allocates, blocks, sleeps, spins, probes CPU features, installs a handler, validates a register value, or recovers from a trap.

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `cr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` or `#UD` |
| `cr*.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |
| `rflags.read` | never | never | O(1) | reentrant | none | infallible |
| `rflags.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `{cs,ds,es,fs,gs,ss,fs_base,gs_base}.read` | never | never | O(1) | reentrant | none | infallible |
| `{cs,ds,es,fs,gs,ss,fs_base,gs_base}.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |
| `gs_base.swap` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `{gdtr,idtr,tr,ldtr}.read` | never | never | O(1) | reentrant | none | infallible |
| `{gdtr,idtr,tr,ldtr}.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` |
| `dr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP` or `#UD` |
| `dr*.write` | never | never | O(1) | reentrant | memory clobber | infallible; may `#GP` or `#UD` |

## Target gating and faults

The module imports on every target. An operation that emits x86_64 assembly produces a compile error when referenced on another target. Layout-only register types compile on every target.

Privileged access may raise CPU exceptions. Control, debug, descriptor-load, and segment-write operations can raise `#GP`. `xcr0`, FSGSBASE access, and debug-register access can also raise `#UD` when their architectural requirements are absent. Trap recovery is caller policy.

## Required tests

Tests must cover:

- exact backing width and `fromInt`/`raw` round trips for every scalar type;
- named-field placement for CR0, CR4, CR8, XCR0, RFLAGS, DR6, and DR7;
- selector field placement and type separation;
- GDTR and IDTR size 10, alignment 2, `limit` offset 0, and `base` offset 2;
- incompatible register-type signatures for every accessor family;
- compile-only instantiation of every privileged wrapper;
- host-safe `rflags.read()` with architectural RFLAGS bit 1 set.

## Sources

The packed layouts follow the Intel 64 and IA-32 Architectures Software Developer's Manual and AMD64 Architecture Programmer's Manual, Volume 2. The specification must be revised when either architecture assigns a represented reserved field.
