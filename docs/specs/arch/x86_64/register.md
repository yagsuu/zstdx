# x86_64 register access

Status: Approved.

`stdx.arch.x86_64.register` owns thin raw access wrappers for architectural x86_64 register families: control registers, debug registers, segment registers and bases, descriptor-table registers, and RFLAGS. The namespace names hardware register state only; semantic operations built on top of that state live elsewhere (`interrupts`, `privilege`, `cpu`, `paging`, VMX/SVM specs).

Every operation is a direct ISA wrapper. This spec owns no policy for trap handling, descriptor contents, page-table formats, debug conditions, task setup, interrupt routing, or scheduler integration.

## Owned scope

This spec owns:

- `stdx.arch.x86_64.register`;
- `register.control.{cr0,cr2,cr3,cr4,cr8,xcr0}` read/write families;
- `register.rflags.read` and `register.rflags.write`;
- `register.segment.{cs,ds,es,fs,gs,ss}` selector access;
- `register.segment.{fs_base,gs_base}` base access and `swapGs`;
- `register.descriptor.Pointer` pseudo-descriptor layout;
- `register.descriptor.{gdtr,idtr,tr,ldtr}` load/store families;
- `register.debug.dr0..dr7` read/write families;
- target gating, privilege/trap documentation, ordering contracts, and required tests.

## Deferred scope and non-goals

This spec does not own:

- bitfield layouts for CR0, CR3, CR4, XCR0, RFLAGS, DR6, or DR7;
- descriptor-entry layouts such as segment, interrupt-gate, TSS, LDT, GDT, or IDT entries;
- GDT/IDT/LDT/TSS builders or allocation;
- debug-register policy or `#DB` exception handling;
- page-fault handling, CR2 recovery, CR3 installation policy, PCID lifetime, or TLB invalidation;
- interrupt enable/disable helpers (`stdx.arch.x86_64.interrupts` owns semantic IF control);
- current privilege helpers (`stdx.arch.x86_64.privilege` owns CPL interpretation);
- VMX/SVM control-state policy;
- root promotion.

## Public namespace

```zig
stdx.arch.x86_64.register
stdx.arch.x86_64.register.control
stdx.arch.x86_64.register.control.cr0
stdx.arch.x86_64.register.control.cr2
stdx.arch.x86_64.register.control.cr3
stdx.arch.x86_64.register.control.cr4
stdx.arch.x86_64.register.control.cr8
stdx.arch.x86_64.register.control.xcr0
stdx.arch.x86_64.register.rflags
stdx.arch.x86_64.register.segment
stdx.arch.x86_64.register.segment.cs
stdx.arch.x86_64.register.segment.ds
stdx.arch.x86_64.register.segment.es
stdx.arch.x86_64.register.segment.fs
stdx.arch.x86_64.register.segment.gs
stdx.arch.x86_64.register.segment.ss
stdx.arch.x86_64.register.segment.fs_base
stdx.arch.x86_64.register.segment.gs_base
stdx.arch.x86_64.register.descriptor
stdx.arch.x86_64.register.descriptor.Pointer
stdx.arch.x86_64.register.descriptor.gdtr
stdx.arch.x86_64.register.descriptor.idtr
stdx.arch.x86_64.register.descriptor.tr
stdx.arch.x86_64.register.descriptor.ldtr
stdx.arch.x86_64.register.debug
stdx.arch.x86_64.register.debug.dr0
stdx.arch.x86_64.register.debug.dr1
stdx.arch.x86_64.register.debug.dr2
stdx.arch.x86_64.register.debug.dr3
stdx.arch.x86_64.register.debug.dr4
stdx.arch.x86_64.register.debug.dr5
stdx.arch.x86_64.register.debug.dr6
stdx.arch.x86_64.register.debug.dr7
```

No names are root-promoted. The PascalCase historical namespaces
`ControlRegister`, `Rflags`, `Segment`, `Descriptor`, and `DebugRegister` are not exported.

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/register.zig
src/arch/x86_64/register/control.zig
src/arch/x86_64/register/rflags.zig
src/arch/x86_64/register/segment.zig
src/arch/x86_64/register/descriptor.zig
src/arch/x86_64/register/debug.zig
test/arch/x86_64_register_test.zig
```

`src/arch/x86_64.zig` re-exports:

```zig
pub const register = @import("x86_64/register.zig");
```

`register.zig` re-exports lower-level register-family modules:

```zig
pub const control = @import("register/control.zig");
pub const rflags = @import("register/rflags.zig");
pub const segment = @import("register/segment.zig");
pub const descriptor = @import("register/descriptor.zig");
pub const debug = @import("register/debug.zig");
```

## Target gating

The module may be imported on any target. Operations that emit x86_64 inline assembly produce a compile error when referenced on non-x86_64 targets. Layout-only declarations such as `descriptor.Pointer` compile on every target.

## Approved API

### Control registers

```zig
pub const control = struct {
    pub const cr0 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const cr2 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const cr3 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const cr4 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const cr8 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const xcr0 = struct { pub fn read() u64; pub fn write(value: u64) void; };
};
```

`cr0`, `cr3`, `cr4`, and `cr8` use `mov rNN, crX` / `mov crX, rNN`. `cr2` writes are architecturally legal and are used by exception injection or recovery paths; this spec owns only raw access. `xcr0` uses `xgetbv`/`xsetbv` with `ecx = 0`.

### RFLAGS

```zig
pub const rflags = struct {
    pub fn read() u64;
    pub fn write(value: u64) void;
};
```

`read` uses `pushfq; pop rNN`. `write` uses `push rNN; popfq`. Raw bit meaning remains caller policy.

### Segment registers

```zig
pub const segment = struct {
    pub const cs = struct { pub fn read() u16; pub fn writeFarReturn(selector: u16) void; };
    pub const ds = struct { pub fn read() u16; pub fn write(selector: u16) void; };
    pub const es = struct { pub fn read() u16; pub fn write(selector: u16) void; };
    pub const fs = struct { pub fn read() u16; pub fn write(selector: u16) void; };
    pub const gs = struct { pub fn read() u16; pub fn write(selector: u16) void; };
    pub const ss = struct { pub fn read() u16; pub fn write(selector: u16) void; };

    pub const fs_base = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const gs_base = struct { pub fn read() u64; pub fn write(value: u64) void; };

    pub fn swapGs() void;
};
```

Segment selector methods move raw selector values only. Descriptor validity, privilege checks, far-control-transfer setup, and fault recovery are host policy.

### Descriptor-table registers

```zig
pub const descriptor = struct {
    pub const Pointer = extern struct {
        limit: u16,
        base: u64 align(2),

        pub const alignment: usize = 2;
    };

    pub const gdtr = struct { pub fn load(ptr: *const Pointer) void; pub fn store(ptr: *Pointer) void; };
    pub const idtr = struct { pub fn load(ptr: *const Pointer) void; pub fn store(ptr: *Pointer) void; };
    pub const tr = struct { pub fn load(selector: u16) void; pub fn store() u16; };
    pub const ldtr = struct { pub fn load(selector: u16) void; pub fn store() u16; };
};
```

`Pointer` is exactly 10 bytes with `limit` at offset 0 and `base` at offset 2. `gdtr` and `idtr` wrap `lgdt`/`sgdt` and `lidt`/`sidt`. `tr` wraps `ltr`/`str`. `ldtr` wraps `lldt`/`sldt`.

### Debug registers

```zig
pub const debug = struct {
    pub const dr0 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr1 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr2 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr3 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr4 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr5 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr6 = struct { pub fn read() u64; pub fn write(value: u64) void; };
    pub const dr7 = struct { pub fn read() u64; pub fn write(value: u64) void; };
};
```

DR4/DR5 alias or fault behavior follows architectural DE/CR4 rules; wrappers expose raw instruction access and do not normalize the result.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `control.cr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP`/`#UD` |
| `control.cr*.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `control.xcr0.read` | never | never | O(1) | reentrant | none | infallible; may `#GP`/`#UD` |
| `control.xcr0.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `rflags.read` | never | never | O(1) | reentrant | none | infallible |
| `rflags.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `segment.*.read` | never | never | O(1) | reentrant | none | infallible |
| `segment.*.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `segment.{fs_base,gs_base}.read` | never | never | O(1) | reentrant | none | infallible; may `#GP`/`#UD` |
| `segment.{fs_base,gs_base}.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |
| `segment.swapGs` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `descriptor.gdtr/idtr.load` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `descriptor.gdtr/idtr.store` | never | never | O(1) | reentrant | writes pointer | infallible |
| `descriptor.tr/ldtr.load` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `descriptor.tr/ldtr.store` | never | never | O(1) | reentrant | none | infallible |
| `debug.dr*.read` | never | never | O(1) | reentrant | none | infallible; may `#GP`/`#UD` |
| `debug.dr*.write` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |

All operations are fixed instruction wrappers. No operation allocates, blocks, sleeps, spins, probes runtime CPU features, installs handlers, or recovers from traps.

## Trap and privilege behavior

Privileged register access may raise CPU exceptions:

- control register access: `#GP` at insufficient privilege or when operand bits violate architectural constraints; `xcr0` may `#UD` when unsupported;
- segment writes and descriptor loads: `#GP` for invalid selectors or privilege violations;
- debug register access: `#GP` at insufficient privilege and `#UD`/alias behavior according to CR4.DE and CPU mode;
- `swapGs`: `#GP` outside the architectural conditions for use;
- `rflags.write`: architectural masking and privilege behavior are determined by the CPU.

Trap recovery is caller policy.

## Examples

```zig
const x86 = stdx.arch.x86_64;

const raw_cr3 = x86.register.control.cr3.read();
x86.register.control.cr3.write(raw_cr3);

const flags = x86.register.rflags.read();
_ = flags;

const idtr: x86.register.descriptor.Pointer = .{ .limit = limit, .base = base };
x86.register.descriptor.idtr.load(&idtr);

x86.register.segment.gs_base.write(per_cpu_base);
x86.register.debug.dr0.write(watch_address);
```

## Required tests

Required tests:

- Compile-only: every register read/write wrapper instantiates on x86_64;
- compile-only: non-x86_64 imports do not emit inline assembly until a gated operation is referenced;
- layout: `@sizeOf(register.descriptor.Pointer) == 10`;
- layout: `@alignOf(register.descriptor.Pointer) == 2`;
- layout: `@offsetOf(register.descriptor.Pointer, "limit") == 0` and `base == 2`;
- runtime host-safe: `rflags.read()` returns a value with architectural bit 1 set when `x86_64.supported`;
- runtime host-safe: selector reads that are unprivileged instantiate and return raw `u16` values where the host permits execution.

## Amendments

This spec supersedes the register-related portions previously owned by `base.md` and `extensions.md`.