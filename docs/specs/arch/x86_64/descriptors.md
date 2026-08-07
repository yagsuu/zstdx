# x86_64 descriptor entries

Status: Approved.

`stdx.arch.x86_64.descriptors` defines the IA-32e segment, system, and interrupt-descriptor-table entry formats as pure value types.

## What this spec is

This specification owns:

- `stdx.arch.x86_64.descriptors`;
- 8-byte code and data segment descriptors used in a global descriptor table (GDT) or local descriptor table (LDT);
- 16-byte LDT and 64-bit task-state-segment (TSS) system descriptors used in a GDT;
- 16-byte interrupt and trap gates used in an interrupt descriptor table (IDT);
- exact architectural bit layouts, raw round trips, construction, field extraction, structural validation, and required tests.

## What this spec is not

This specification does not own:

- GDT, LDT, or IDT storage, table containers, slot allocation, mutation, publication, or replacement;
- `lgdt`, `lidt`, `lldt`, or `ltr` instruction wrappers;
- TSS storage or TSS field layouts;
- segment-selector allocation or validation against a descriptor table;
- interrupt stubs, handler calling conventions, vector allocation, privilege-transition policy, or exception recovery;
- synchronization for a live descriptor-table update;
- 16-bit, compatibility-mode, call-gate, task-gate, or 32-bit TSS descriptors;
- canonical-address validation or validation that a referenced segment selector names a present code segment.

## Terminology

A **raw limit** is the 20-bit value stored in a segment or system descriptor.

An **effective limit** is the inclusive byte limit after the granularity bit is applied. If granularity is clear, the effective limit equals the raw limit. If granularity is set, the effective limit is `(raw_limit << 12) | 0xfff`.

An **IST index** is the 3-bit IDT interrupt-stack-table field. Zero disables IST selection. Values 1 through 7 select the corresponding TSS IST entry.

## Public namespace and source ownership

Public paths:

```zig
stdx.arch.x86_64.descriptors
stdx.arch.x86_64.descriptors.Segment
stdx.arch.x86_64.descriptors.System
stdx.arch.x86_64.descriptors.Gate
stdx.arch.x86_64.descriptors.SegmentKind
stdx.arch.x86_64.descriptors.SystemKind
stdx.arch.x86_64.descriptors.GateKind
stdx.arch.x86_64.descriptors.PrivilegeLevel
stdx.arch.x86_64.descriptors.SegmentOptions
stdx.arch.x86_64.descriptors.SystemOptions
stdx.arch.x86_64.descriptors.GateOptions
stdx.arch.x86_64.descriptors.Error
```

Source and test ownership:

```text
src/arch/x86_64.zig
src/arch/x86_64/descriptors.zig
test/arch/x86_64/descriptors/all.zig
test/arch/x86_64/descriptors/descriptors_test.zig
```

`src/arch/x86_64.zig` re-exports the module:

```zig
pub const descriptors = @import("x86_64/descriptors.zig");
```

The facade contains no descriptor implementation logic. The descriptor declarations compile on every target. They emit no instructions and perform no target probing.

## Cross-spec relationships

This specification composes with `docs/specs/arch/x86_64/registers.md`. The register specification owns segment selectors and access to GDTR, IDTR, LDTR, and TR. This specification owns the entries in the tables that those registers reference.

This specification does not change `stdx.arch.x86_64.registers`.

## Data structures and representation

### Common enums

```zig
pub const PrivilegeLevel = enum(u2) {
    ring0 = 0,
    ring1 = 1,
    ring2 = 2,
    ring3 = 3,
};

pub const SegmentKind = enum(u4) {
    data_read_only = 0x0,
    data_read_only_accessed = 0x1,
    data_read_write = 0x2,
    data_read_write_accessed = 0x3,
    data_read_only_expand_down = 0x4,
    data_read_only_expand_down_accessed = 0x5,
    data_read_write_expand_down = 0x6,
    data_read_write_expand_down_accessed = 0x7,
    code_execute_only = 0x8,
    code_execute_only_accessed = 0x9,
    code_execute_read = 0xa,
    code_execute_read_accessed = 0xb,
    code_execute_only_conforming = 0xc,
    code_execute_only_conforming_accessed = 0xd,
    code_execute_read_conforming = 0xe,
    code_execute_read_conforming_accessed = 0xf,
};

pub const SystemKind = enum(u4) {
    ldt = 0x2,
    tss_available = 0x9,
    tss_busy = 0xb,
    _,
};

pub const GateKind = enum(u4) {
    interrupt = 0xe,
    trap = 0xf,
    _,
};
```

`SegmentKind` preserves the complete architectural type nibble, including the accessed bit. `SystemKind` and `GateKind` are open enums so `fromRaw` can preserve unsupported type values. `validate` rejects unsupported type values.

### Options and errors

```zig
pub const SegmentOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    available: bool = false,
    long_mode: bool = false,
    default_operand_size: bool = false,
    granularity: bool = false,
};

pub const SystemOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    available: bool = false,
    granularity: bool = false,
};

pub const GateOptions = struct {
    privilege: PrivilegeLevel = .ring0,
    present: bool = true,
    ist: u3 = 0,
};

pub const Error = error{
    ReservedBits,
    InvalidSegmentMode,
    InvalidSystemKind,
    InvalidGateKind,
};
```

The integer widths prevent an out-of-range base, raw limit, selector, or IST index from reaching a constructor. Structural validation does not validate the referenced memory, TSS, selector, handler, or privilege policy.

### `Segment`

`Segment` is a `packed struct(u64)`. Its fields occupy these bit ranges:

| Bits | Field |
| ---: | --- |
| 15:0 | raw limit 15:0 |
| 31:16 | base 15:0 |
| 39:32 | base 23:16 |
| 43:40 | `SegmentKind` |
| 44 | descriptor class, fixed to one |
| 46:45 | descriptor privilege level |
| 47 | present |
| 51:48 | raw limit 19:16 |
| 52 | available |
| 53 | long mode |
| 54 | default operand size / stack width |
| 55 | granularity |
| 63:56 | base 31:24 |

```zig
pub const Segment = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    kind: SegmentKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    long_mode: bool,
    default_operand_size: bool,
    granularity: bool,
    base_high: u8,

    pub fn init(
        base: u32,
        raw_limit: u20,
        kind: SegmentKind,
        options: SegmentOptions,
    ) Error!Segment;

    pub fn fromRaw(value: u64) Segment;
    pub fn raw(self: Segment) u64;
    pub fn base(self: Segment) u32;
    pub fn rawLimit(self: Segment) u20;
    pub fn effectiveLimit(self: Segment) u32;
    pub fn validate(self: Segment) Error!void;
};
```

`init` splits `base` and `raw_limit` into the architectural fields, fixes the descriptor-class bit to one, applies `kind` and `options`, and calls `validate` before it returns.

`validate` returns `error.ReservedBits` when the descriptor-class bit is zero. It returns `error.InvalidSegmentMode` when `long_mode` is set for a data descriptor or when `long_mode` and `default_operand_size` are both set. All 16 `SegmentKind` values are structurally valid.

`fromRaw` preserves all 64 input bits without validation. `raw` returns all stored bits unchanged.

### `System`

`System` is a `packed struct(u128)`. It occupies two consecutive 8-byte GDT slots. Its fields occupy these bit ranges:

| Bits | Field |
| ---: | --- |
| 15:0 | raw limit 15:0 |
| 31:16 | base 15:0 |
| 39:32 | base 23:16 |
| 43:40 | `SystemKind` |
| 44 | descriptor class, fixed to zero |
| 46:45 | descriptor privilege level |
| 47 | present |
| 51:48 | raw limit 19:16 |
| 52 | available |
| 54:53 | reserved, fixed to zero |
| 55 | granularity |
| 63:56 | base 31:24 |
| 95:64 | base 63:32 |
| 127:96 | reserved, fixed to zero |

```zig
pub const System = packed struct(u128) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    kind: SystemKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    limit_high: u4,
    available: bool,
    _reserved_low: u2,
    granularity: bool,
    base_high: u8,
    base_upper: u32,
    _reserved_high: u32,

    pub fn init(
        base: u64,
        raw_limit: u20,
        kind: SystemKind,
        options: SystemOptions,
    ) Error!System;

    pub fn fromRaw(value: u128) System;
    pub fn raw(self: System) u128;
    pub fn base(self: System) u64;
    pub fn rawLimit(self: System) u20;
    pub fn effectiveLimit(self: System) u32;
    pub fn validate(self: System) Error!void;
};
```

`init` splits `base` and `raw_limit`, clears all reserved fields and the descriptor-class bit, applies `kind` and `options`, and calls `validate` before it returns.

`validate` returns `error.ReservedBits` when the descriptor-class bit or a reserved field is nonzero. It returns `error.InvalidSystemKind` unless `kind` is `.ldt`, `.tss_available`, or `.tss_busy`.

`fromRaw` preserves all 128 input bits without validation. `raw` returns all stored bits unchanged.

### `Gate`

`Gate` is a `packed struct(u128)`. Its fields occupy these bit ranges:

| Bits | Field |
| ---: | --- |
| 15:0 | handler offset 15:0 |
| 31:16 | segment selector |
| 34:32 | IST index |
| 39:35 | reserved, fixed to zero |
| 43:40 | `GateKind` |
| 44 | descriptor class, fixed to zero |
| 46:45 | descriptor privilege level |
| 47 | present |
| 63:48 | handler offset 31:16 |
| 95:64 | handler offset 63:32 |
| 127:96 | reserved, fixed to zero |

```zig
pub const Gate = packed struct(u128) {
    offset_low: u16,
    segment_selector: u16,
    ist: u3,
    _reserved_low: u5,
    kind: GateKind,
    descriptor_class: bool,
    privilege: PrivilegeLevel,
    present: bool,
    offset_middle: u16,
    offset_high: u32,
    _reserved_high: u32,

    pub fn init(
        offset: u64,
        selector: u16,
        kind: GateKind,
        options: GateOptions,
    ) Error!Gate;

    pub fn fromRaw(value: u128) Gate;
    pub fn raw(self: Gate) u128;
    pub fn offset(self: Gate) u64;
    pub fn selector(self: Gate) u16;
    pub fn validate(self: Gate) Error!void;
};
```

`init` splits `offset`, clears the descriptor-class bit and all reserved fields, applies `selector`, `kind`, and `options`, and calls `validate` before it returns. The `u3` type accepts all architectural IST encodings and cannot represent an out-of-range IST value.

`validate` returns `error.ReservedBits` when the descriptor-class bit or a reserved field is nonzero. It returns `error.InvalidGateKind` unless `kind` is `.interrupt` or `.trap`.

`fromRaw` preserves all 128 input bits without validation. `raw` returns all stored bits unchanged.

## Global invariants

- `@bitSizeOf(Segment) == 64` and `@sizeOf(Segment) == 8`.
- `@bitSizeOf(System) == 128` and `@sizeOf(System) == 16`.
- `@bitSizeOf(Gate) == 128` and `@sizeOf(Gate) == 16`.
- Every named field starts at its documented architectural bit offset.
- `fromRaw` and `raw` preserve every bit, including invalid and reserved encodings.
- A successful `init` result passes `validate`.
- `validate` does not modify the value.
- No operation allocates, waits, blocks, spins, performs I/O, accesses CPU state, invokes a callback, or mutates hidden state.
- Values own no table storage and borrow no memory.
- Copying a value does not invalidate either copy.
- Operations are value-only, reentrant, wait-free, and O(1).
- Operations impose no memory-ordering or synchronization effect.

## Implementation constraints

The implementation MUST use exact-width packed representations with explicit fields for every architectural bit. Reserved and fixed-class fields MUST remain represented so `fromRaw` can preserve them and `validate` can inspect them.

The implementation MUST place compile-time bit-size, byte-size, and important bit-offset assertions next to each representation. It MUST NOT use host pointers, inline assembly, target probing, allocation, or table storage.

The implementation MUST use `u128` only as the scalar backing and raw representation of each 16-byte descriptor. The API MUST expose split-field access through the documented construction and extraction methods so callers do not depend on host structure offsets.

## Testing

Compile-time layout tests MUST verify each documented bit size, byte size, and bit offset. Tests MUST verify that the module and every layout-only declaration compile on non-x86_64 targets.

Raw-representation tests MUST verify zero, all-bit, and non-trivial `fromRaw`/`raw` round trips for `Segment`, `System`, and `Gate`.

Known-encoding tests MUST use independent architectural constants for:

- one 64-bit code segment;
- one writable data segment;
- one LDT system descriptor;
- available and busy 64-bit TSS system descriptors;
- interrupt and trap gates.

Construction and extraction tests MUST cover:

- split and recombined 32-bit segment bases;
- split and recombined 64-bit system bases;
- split and recombined 64-bit gate offsets;
- raw limits zero and `0xfffff`;
- effective-limit results with byte and 4 KiB granularity;
- privilege levels 0 through 3;
- IST encodings 0 through 7;
- each `SegmentKind`, supported `SystemKind`, and supported `GateKind`.

Validation tests MUST cover every error variant. They MUST independently exercise fixed-class bits, each reserved range, unsupported system and gate kinds, a data descriptor with long mode set, and a descriptor with both long mode and default operand size set.

Tests MUST verify that `Segment`, `System`, and `Gate` are distinct types. Tests MUST NOT execute privileged instructions or install a descriptor table.

## Sources

The layouts follow the Intel 64 and IA-32 Architectures Software Developer's Manual, Volume 3A, sections for segment descriptors, system-segment descriptors, and IDT gates, and the AMD64 Architecture Programmer's Manual, Volume 2. This specification MUST be revised when either architecture assigns a represented reserved field or changes an accepted encoding.
