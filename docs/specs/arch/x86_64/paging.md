# x86_64 paging

Status: Approved.

`stdx.arch.x86_64.paging` owns the architectural data formats and read-only
walker for ordinary IA-32e paging. It covers CR3-backed 4-level and 5-level
translation, page-table entries, canonical linear-address checks, table/leaf
entry construction, reserved-bit validation, and deterministic page walks over a
caller-supplied physical-memory reader.

The primitive is an ISA data-format and algorithm surface. It is not an address
space manager: it does not allocate tables, install CR3, modify accessed/dirty
bits, invalidate TLBs, handle traps, or decide memory ownership policy.

## Owned scope

This spec owns:

- the `stdx.arch.x86_64.paging` namespace;
- `paging.Mode` for active 4-level vs 5-level ordinary paging;
- `paging.Level`, `paging.Index`, and `paging.Indices`;
- x86 paging address aliases: `LinearAddr`, `PhysAddr`, `Phys4K`, `Phys2M`,
  and `Phys1G`;
- `paging.linear` canonical-address and index helpers;
- `paging.table` page-table storage types, table-entry flags, table-entry
  construction, and table-frame extraction;
- `paging.leaf` mapped-page flags, leaf frame values, leaf-size helpers,
  and leaf-entry construction/extraction;
- `paging.Root` CR3 root decoding and encoding;
- `paging.Entry` raw-preserving page-table entry values, structural
  classification, and reserved-bit inspection;
- `paging.walk` access, mapping, fault, and result types;
- `paging.Walker(Reader)` read-only page-table walker;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- SLAT, EPT, or NPT. Future second-level translation families live under the
  deferred namespaces `stdx.arch.x86_64.paging.slat.ept` and
  `stdx.arch.x86_64.paging.slat.npt`;
- VMX or SVM invalidation instructions. `invept`, `invvpid`, and `invlpga`
  remain owned by their VMX/SVM specs;
- page-table allocation, growth, reclamation, or ownership;
- virtual-address-space layout policy;
- `map`, `unmap`, `protect`, copy-on-write, or region-management APIs;
- physical-memory-map ownership or address classification such as RAM,
  reserved, MMIO, DMA, encrypted, or shared/private memory;
- direct physical-address dereferencing. Walkers read entries only through the
  caller-provided `Reader`;
- reading the current CR3, writing CR3, or installing a page table;
- TLB invalidation, PCID lifetime, cross-CPU shootdown, or preemption policy;
- page-fault handler installation, trap recovery, or exception dispatch;
- accessed/dirty bit writeback or any mutating walker;
- PAT/MTRR final memory-type resolution. The walker reports raw paging cache
  attributes but does not compute the effective memory type;
- protection-key, shadow-stack, SGX, SMAP, SMEP, or CET permission checks;
- root promotion.

## Public namespace

Paging primitives live under the lower-case `stdx.arch.x86_64.paging`
namespace:

```zig
stdx.arch.x86_64.paging
stdx.arch.x86_64.paging.Mode
stdx.arch.x86_64.paging.Level
stdx.arch.x86_64.paging.Index
stdx.arch.x86_64.paging.Indices
stdx.arch.x86_64.paging.LinearAddr
stdx.arch.x86_64.paging.PhysAddr
stdx.arch.x86_64.paging.Phys4K
stdx.arch.x86_64.paging.Phys2M
stdx.arch.x86_64.paging.Phys1G
stdx.arch.x86_64.paging.linear
stdx.arch.x86_64.paging.table
stdx.arch.x86_64.paging.leaf
stdx.arch.x86_64.paging.Root
stdx.arch.x86_64.paging.Entry
stdx.arch.x86_64.paging.walk
stdx.arch.x86_64.paging.Walker
```

It is not root-promoted:

```zig
stdx.paging // not exported
stdx.arch.paging // not exported
stdx.arch.x86_64.Paging // not exported
```

Architecture code reaches paging only through:

```zig
const paging = stdx.arch.x86_64.paging;
```

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/paging.zig
test/arch/x86_64_paging_test.zig
```

`src/arch/x86_64.zig` re-exports:

```zig
pub const paging = @import("x86_64/paging.zig");
```

`src/arch/x86_64/paging.zig` owns the implementation. It contains no inline
assembly and compiles on every target.

## Address aliases

```zig
pub const LinearTag = opaque {};
pub const LinearAddr = stdx.addr.Address(LinearTag, u64);

pub const PhysAddr = stdx.addr.PhysAddr;

pub const Phys4K = stdx.addr.Page(PhysAddr, stdx.addr.pages._4kib);
pub const Phys2M = stdx.addr.Page(PhysAddr, stdx.addr.pages._2mib);
pub const Phys1G = stdx.addr.Page(PhysAddr, stdx.addr.pages._1gib);
```

`LinearAddr` is distinct from `stdx.addr.VirtAddr`. A walked x86 linear address
is an architectural 64-bit value and may describe guest or crash-dump state that
is unrelated to the host process pointer width.

`PhysAddr` is the physical-address vocabulary spoken by the supplied reader. For
host page-table walks it is host physical. For guest CR3 walks it is guest
physical relative to the reader backend.

## `Mode`

```zig
pub const Mode = enum {
    level4,
    level5,

    pub fn rootLevel(self: Mode) Level;
    pub fn linearBits(self: Mode) u8;
};
```

Semantics:

- `.level4` is ordinary 4-level IA-32e paging. Root level is `.pml4` and
  canonical linear width is 48 bits.
- `.level5` is ordinary 5-level paging. Root level is `.pml5` and canonical
  linear width is 57 bits.

`Mode` names the active paging mode, not the CPU's maximum supported linear
width. Callers decide the active mode from their own CR4/guest-state policy.

## `Level`

```zig
pub const Level = enum(u3) {
    pt = 1,
    pd = 2,
    pdpt = 3,
    pml4 = 4,
    pml5 = 5,

    pub fn indexShift(self: Level) u6;
    pub fn next(self: Level) ?Level;
};
```

`indexShift` returns the bit offset of the 9-bit paging-structure index for
that level:

| Level | `indexShift()` |
| --- | ---: |
| `.pt` | 12 |
| `.pd` | 21 |
| `.pdpt` | 30 |
| `.pml4` | 39 |
| `.pml5` | 48 |

`next` returns the next lower level, or `null` for `.pt`.

## `Index` and `Indices`

```zig
pub const Index = enum(u9) {
    _,

    pub fn fromInt(value: u9) Index;
    pub fn raw(self: Index) u9;
};

pub const Indices = struct {
    pml5: Index,
    pml4: Index,
    pdpt: Index,
    pd: Index,
    pt: Index,
    offset_4kib: u12,

    pub fn at(self: Indices, level: Level) Index;
};
```

`pml5` is zero for `.level4` addresses. `at(level)` returns the index belonging
to the requested level.

`offset_4kib` is always the low 12 bits of the linear address. Larger leaf
mappings use `leaf.offsetMask(level)` to derive their effective page offset.

## `linear` namespace

```zig
pub const linear = struct {
    pub const Error = error{NonCanonical};

    pub fn isCanonical(raw: u64, mode: Mode) bool;
    pub fn fromCanonical(raw: u64, mode: Mode) Error!LinearAddr;
    pub fn signExtend(raw: u64, mode: Mode) LinearAddr;
    pub fn indices(addr: LinearAddr, mode: Mode) Error!Indices;
};
```

`isCanonical(raw, mode)` returns whether `raw` is sign-extended from the active
mode's high implemented linear-address bit.

`fromCanonical(raw, mode)` validates the input and wraps it as `LinearAddr`.
It does not modify non-canonical values.

`signExtend(raw, mode)` sign-extends the low implemented linear-address bits and
returns a `LinearAddr`. It does not reject inputs with non-canonical high bits;
it constructs the canonical value implied by the low bits.

`indices(addr, mode)` rejects non-canonical addresses with `error.NonCanonical`
and then extracts every paging-structure index.

`canonicalize` is intentionally not part of the API because it is ambiguous
between validation and sign extension.

## `Config` and `Features`

```zig
pub const Features = struct {
    pcid: bool = false,
    no_execute: bool = false,
    page_1gib: bool = false,
    supervisor_write_protect: bool = true,
};

pub const Config = struct {
    mode: Mode,
    physical_bits: u8,
    features: Features = .{},

    pub const Error = error{InvalidPhysicalWidth};

    pub fn fromAddressSizes(
        mode: Mode,
        sizes: stdx.arch.x86_64.cpuid.AddressSizes,
        features: Features,
    ) Config;

    pub fn linearBits(self: Config) u8;
    pub fn validate(self: Config) Error!void;
    pub fn assertValid(self: Config) void;
};
```

`physical_bits` is the active physical-address width used for reserved-bit
validation. It must be in the inclusive range `[32, 52]`.

`features.pcid` controls CR3 low-bit decoding in `Root.fromCr3` and
`Root.toCr3`.

`features.no_execute` controls whether bit 63 is interpreted as execute-disable
or as a reserved bit.

`features.page_1gib` controls whether a `.pdpt` leaf is legal. A 1 GiB leaf when
this feature is false is a reserved-bit fault during walking.

`features.supervisor_write_protect` models CR0.WP for supervisor writes. When
false, supervisor writes do not fault solely because effective R/W is false.
User writes always require effective R/W.

Protection-key, shadow-stack, SGX, SMAP, and SMEP checks are not modeled by this
spec.

## `Root`

```zig
pub const Root = struct {
    frame: Phys4K.Frame,
    pcid: u12 = 0,
    write_through: bool = false,
    cache_disable: bool = false,

    pub const Error = error{
        ReservedBits,
        PhysicalAddressTooWide,
        InvalidPhysicalWidth,
    };

    pub fn fromCr3(raw: u64, config: Config) Error!Root;
    pub fn toCr3(self: Root, config: Config) Error!u64;
};
```

`frame` is the 4 KiB-aligned physical frame containing the root table.

When `config.features.pcid` is true, CR3 bits 11:0 are decoded as `pcid` and
`write_through` / `cache_disable` are false.

When `config.features.pcid` is false, CR3 bit 3 is `write_through`, bit 4 is
`cache_disable`, and the remaining low bits must be zero.

`fromCr3` and `toCr3` validate that the root physical address fits within
`config.physical_bits` and is 4 KiB aligned.

CR3 write-operand bit 63 for no-flush behavior is not part of `Root`; it is
write policy, not root identity. A future `RootWrite` value may model it if a
consumer needs it.

## `Entry`

```zig
pub const Entry = enum(u64) {
    _,

    pub const Error = error{
        NotPresent,
        WrongKind,
        ReservedBits,
        InvalidPhysicalWidth,
    };

    pub const Kind = enum {
        not_present,
        table,
        leaf,
    };

    pub const ReservedBits = struct {
        mask: u64,

        pub fn any(self: ReservedBits) bool;
    };

    pub fn empty() Entry;
    pub fn fromRaw(raw: u64) Entry;
    pub fn raw(self: Entry) u64;

    pub fn isPresent(self: Entry) bool;
    pub fn kind(self: Entry, level: Level) Kind;
    pub fn isLeaf(self: Entry, level: Level) bool;

    pub fn reservedBits(self: Entry, level: Level, config: Config) ReservedBits;
    pub fn hasReserved(self: Entry, level: Level, config: Config) bool;
};
```

`Entry` is raw-preserving. It does not use one packed struct because bit meaning
changes by level: bit 7 is a large-page selector at `.pd` and `.pdpt`, a PAT bit
at `.pt`, and reserved at `.pml4` / `.pml5`.

`kind(level)` is structural:

- returns `.not_present` when bit 0 is clear;
- returns `.leaf` for present `.pt` entries;
- returns `.leaf` for present `.pd` / `.pdpt` entries with bit 7 set;
- returns `.table` for other present entries.

`kind` does not validate reserved bits, physical-address width, or access
permissions.

`isLeaf(level)` is exact sugar for `kind(level) == .leaf`.

`reservedBits` returns a mask of set bits that would be architecturally reserved
for a present entry at `level` under `config`. It returns zero for not-present
entries because the walker reports not-present before reserved-bit faults.

Reserved-bit validation includes:

- physical address bits above `config.physical_bits`;
- bit 7 set at `.pml4` or `.pml5`;
- `.pdpt` leaf when `config.features.page_1gib` is false;
- large-page address bits below the leaf size;
- bit 63 set when `config.features.no_execute` is false.

## `table` namespace

```zig
pub const table = struct {
    pub const index_bits: u8 = 9;
    pub const index_mask: u64 = 0x1ff;
    pub const entry_count: usize = 512;
    pub const alignment: usize = stdx.addr.pages._4kib;

    pub const Flags = struct {
        present: bool = true,
        writable: bool = false,
        user: bool = false,
        write_through: bool = false,
        cache_disable: bool = false,
        accessed: bool = false,
        no_execute: bool = false,
        available_low: u3 = 0,
        available_high: u11 = 0,
    };

    pub fn Type(comptime level: Level) type;

    pub const Pml5 = Type(.pml5);
    pub const Pml4 = Type(.pml4);
    pub const Pdpt = Type(.pdpt);
    pub const Pd = Type(.pd);
    pub const Pt = Type(.pt);

    pub fn entry(frame: Phys4K.Frame, flags: Flags) Entry;
    pub fn frame(entry_value: Entry, level: Level, config: Config) Entry.Error!Phys4K.Frame;
};
```

`Type(level)` returns a 4 KiB extern table type with 512 `Entry` values:

```zig
pub fn Type(comptime level: Level) type {
    return extern struct {
        entries: [entry_count]Entry,

        pub const table_level = level;

        pub fn init() @This();
        pub fn get(self: *const @This(), index: Index) Entry;
        pub fn set(self: *@This(), index: Index, entry_value: Entry) void;
        pub fn clear(self: *@This(), index: Index) void;
    };
}
```

`init()` returns a table whose entries are all `Entry.empty()`.

`set` and `clear` are plain stores into caller-owned memory. They perform no
barriers, no atomic operations, no accessed/dirty maintenance, and no TLB
invalidation. Callers own synchronization and invalidation for reachable tables.

`table.entry(frame, flags)` constructs an entry pointing to another 4 KiB page
table.

`table.frame(entry_value, level, config)` validates that `entry_value` is
present, structurally a table at `level`, has no reserved bits under `config`,
and names a 4 KiB-aligned physical frame within `config.physical_bits`.

## `leaf` namespace

```zig
pub const leaf = struct {
    pub const Flags = struct {
        present: bool = true,
        writable: bool = false,
        user: bool = false,
        write_through: bool = false,
        cache_disable: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        global: bool = false,
        pat: bool = false,
        no_execute: bool = false,
        available_low: u3 = 0,
        available_high: u11 = 0,
    };

    pub const Frame = union(enum) {
        page4kib: Phys4K.Frame,
        page2mib: Phys2M.Frame,
        page1gib: Phys1G.Frame,

        pub fn level(self: Frame) Level;
        pub fn address(self: Frame) PhysAddr;
        pub fn addressInt(self: Frame) u64;
        pub fn sizeBytes(self: Frame) u64;
        pub fn offsetBits(self: Frame) u6;
        pub fn offsetMask(self: Frame) u64;
    };

    pub const Mapping = struct {
        level: Level,
        frame: Frame,
        entry_address: PhysAddr,
        entry: Entry,

        pub fn base(self: Mapping) PhysAddr;
        pub fn sizeBytes(self: Mapping) u64;
        pub fn offsetBits(self: Mapping) u6;
        pub fn offsetMask(self: Mapping) u64;
    };

    pub fn offsetBits(level: Level) ?u6;
    pub fn sizeBytes(level: Level) ?u64;
    pub fn offsetMask(level: Level) ?u64;

    pub fn entry(frame: Frame, flags: Flags) Entry;
    pub fn page4kib(frame: Phys4K.Frame, flags: Flags) Entry;
    pub fn page2mib(frame: Phys2M.Frame, flags: Flags) Entry;
    pub fn page1gib(frame: Phys1G.Frame, flags: Flags) Entry;

    pub fn frame(entry_value: Entry, level: Level, config: Config) Entry.Error!Frame;
};
```

`offsetBits(level)` returns:

| Level | `offsetBits` | `sizeBytes` |
| --- | ---: | ---: |
| `.pt` | 12 | 4 KiB |
| `.pd` | 21 | 2 MiB |
| `.pdpt` | 30 | 1 GiB |
| `.pml4` | null | null |
| `.pml5` | null | null |

`offsetMask(level)` is `(1 << offsetBits) - 1` when the level can be a leaf.

`leaf.entry(frame, flags)` dispatches to the size-specific constructor matching
`frame`.

`leaf.page4kib`, `leaf.page2mib`, and `leaf.page1gib` construct leaf entries for
known frame sizes. The typed frame argument enforces alignment before entry
construction.

`leaf.frame(entry_value, level, config)` validates that `entry_value` is present,
structurally a leaf at `level`, has no reserved bits under `config`, names a
physical base within `config.physical_bits`, and is aligned to the leaf size.

## `walk` namespace

```zig
pub const walk = struct {
    pub const Access = struct {
        operation: Operation,
        privilege: Privilege,

        pub const Operation = enum {
            read,
            write,
            execute,
        };

        pub const Privilege = enum {
            supervisor,
            user,
        };

        pub fn read(privilege: Privilege) Access;
        pub fn write(privilege: Privilege) Access;
        pub fn execute(privilege: Privilege) Access;
    };

    pub const Attributes = struct {
        writable: bool,
        user: bool,
        executable: bool,
        global: bool,
        write_through: bool,
        cache_disable: bool,
        pat: bool,
    };

    pub const Step = struct {
        level: Level,
        index: Index,
        entry_address: PhysAddr,
        entry: Entry,
    };

    pub const Mapping = struct {
        linear: LinearAddr,
        physical: PhysAddr,
        leaf: leaf.Mapping,
        attributes: Attributes,
    };

    pub const Fault = struct {
        reason: Reason,
        code: Code,
        step: Step,

        pub const Reason = enum {
            not_present,
            reserved_bits,
            write_to_read_only,
            user_to_supervisor,
            execute_disabled,
        };

        pub const Code = packed struct(u16) {
            present: bool,
            write: bool,
            user: bool,
            reserved: bool,
            instruction_fetch: bool,
            _reserved_5_15: u11 = 0,
        };
    };

    pub const Result = union(enum) {
        mapped: Mapping,
        fault: Fault,
    };
};
```

`Access.read(.user)`, `Access.write(.supervisor)`, and
`Access.execute(.user)` construct access descriptors without exposing raw page
fault bits to callers.

`Fault.Code` models the low architectural page-fault error-code bits this spec
checks. Protection-key, shadow-stack, and SGX bits are outside this spec and are
zero.

`Fault.step` identifies the entry that caused the fault.

`Mapping.physical` is the final translated physical address including the leaf
offset. `Mapping.leaf.base()` is the physical base of the mapped page.

## Reader interface

`Walker(Reader)` is comptime-duck-typed. `Reader` is the exact field type stored
inside the walker; callers usually pass a pointer type such as
`*DirectMapReader`.

Every conforming reader must expose `Error` and support this method-call shape:

```zig
pub const Error = error{...};

pub fn readEntry(self: *Self, address: paging.PhysAddr) Error!paging.Entry;
```

When `Reader` is a pointer type, Zig pointer method-call syntax may satisfy the
contract through the pointee's `readEntry` method.

`address` is the physical byte address of the 8-byte page-table entry to load.
The reader owns how that address is interpreted: direct map, guest-physical
memory, emulator memory, crash dump, or test buffer.

The reader must return an `Entry` value whose raw bits match the architectural
little-endian entry stored at `address`. Endianness conversion, bounds checks,
and physical-memory availability are reader policy.

## `Walker(Reader)`

```zig
pub fn Walker(comptime Reader: type) type {
    return struct {
        config: Config,
        reader: Reader,

        pub const Error = Reader.Error || Entry.Error || error{
            NonCanonical,
        };

        pub fn init(config: Config, reader: Reader) @This();

        pub fn walk(
            self: *@This(),
            root: Root,
            linear_addr: LinearAddr,
            access: walk.Access,
        ) Error!walk.Result;

        pub fn walkRaw(
            self: *@This(),
            root: Root,
            raw_linear: u64,
            access: walk.Access,
        ) Error!walk.Result;
    };
}
```

`init` stores `config` and `reader` by value and asserts `config.assertValid()`
under debug checks.

`walk` validates `linear_addr` canonicality under `self.config.mode`; a
non-canonical linear address returns `error.NonCanonical`. It is not returned as
a page fault.

`walkRaw` wraps `raw_linear` and delegates to `walk`. It exists for common CR2,
VM-exit, emulator, debugger, and test call sites that naturally receive raw
integer linear addresses.

`walk` performs at most five reader calls. It does not allocate, wait, spin,
write entries, update accessed/dirty bits, issue fences, or invalidate TLBs.

## Walk semantics

For each level from `config.mode.rootLevel()` down:

1. Compute the level index from the linear address.
2. Compute the physical byte address of the table entry:
   `table_frame.addressInt() + index.raw() * @sizeOf(Entry)`.
3. Load the entry through `reader.readEntry`.
4. If `entry.isPresent()` is false, return `walk.Result{ .fault = ... }` with
   reason `.not_present`.
5. If `entry.hasReserved(level, config)` is true, return a fault with reason
   `.reserved_bits`.
6. Classify `entry.kind(level)`.
7. For `.table`, extract the next table frame through `table.frame` and continue
   to `level.next().?`.
8. For `.leaf`, extract the leaf frame through `leaf.frame`, combine its base
   with the linear-address offset selected by `leaf.offsetMask(level)`, compute
   effective attributes, check `access`, and return either `.mapped` or a
   permission fault.

Effective attributes:

- `writable` is the logical AND of the R/W bit across every present entry in the
  path through the leaf;
- `user` is the logical AND of the U/S bit across every present entry in the
  path through the leaf;
- `executable` is true when `config.features.no_execute` is false, or when no
  present entry in the path has bit 63 set;
- `global`, `pat`, `write_through`, and `cache_disable` are reported from the
  architectural bits that affect the selected leaf mapping. Final PAT/MTRR
  memory-type resolution is not performed.

Permission checks:

- user accesses fault with `.user_to_supervisor` when effective `user` is false;
- write accesses fault with `.write_to_read_only` when effective `writable` is
  false and either the access is user or `config.features.supervisor_write_protect`
  is true;
- execute accesses fault with `.execute_disabled` when effective `executable` is
  false.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Invalidation | Concurrency | Ordering |
| --- | --- | --- | --- | --- | --- | --- |
| `linear.isCanonical` | none | never | O(1) | none | value-only | none |
| `linear.fromCanonical` | none | never | O(1) | none | value-only | none |
| `linear.signExtend` | none | never | O(1) | none | value-only | none |
| `linear.indices` | none | never | O(1) | none | value-only | none |
| `Config.validate` | none | never | O(1) | none | value-only | none |
| `Root.fromCr3`, `Root.toCr3` | none | never | O(1) | none | value-only | none |
| `Entry.*` | none | never | O(1) | none | value-only | none |
| `table.Type(level).init` | none | never | O(entries) | all entries empty | caller-owned value | plain stores |
| `table.Type(level).get` | none | never | O(1) | none | caller-owned memory | plain load |
| `table.Type(level).set` | none | never | O(1) | stored entry | caller-owned memory | plain store |
| `table.Type(level).clear` | none | never | O(1) | cleared entry | caller-owned memory | plain store |
| `table.entry`, `leaf.entry`, `leaf.page*` | none | never | O(1) | none | value-only | none |
| `table.frame`, `leaf.frame` | none | never | O(1) | none | value-only | none |
| `Walker.init` | none | never | O(1) | none | caller-owned value | stores reader/config |
| `Walker.walk` | none | never by itself | O(5 reader calls) | none | reader-defined | reader-defined |
| `Walker.walkRaw` | none | never by itself | O(5 reader calls) | none | reader-defined | reader-defined |

`paging` performs no heap allocation, sleeping, blocking, scheduler calls,
atomics, inline assembly, hidden global access, or runtime target probing.

## Ordering and mutation contract

`paging` does not issue compiler fences, CPU fences, TLB invalidations, or cache
maintenance instructions.

`table.set` and `table.clear` are plain memory stores. If a caller modifies a
reachable paging structure, the caller owns every ordering and invalidation step
required by the execution environment.

`Walker` is read-only. It never sets accessed or dirty bits. It never writes a
page-table entry even when hardware would set A/D bits during a real walk.

## Error and fault distinction

Walker reader failures are Zig errors from `Reader.Error`.

Non-canonical linear addresses are `error.NonCanonical` because ordinary x86
execution raises `#GP` or `#SS`, not `#PF`, before a page walk.

Page-walk failures after a canonical address and successful entry read are
returned as `walk.Result.fault`.

`walk.Result.fault` is data. It does not imply this library installed or handled
a CPU exception.

## Target gating

The paging module contains no inline assembly. It compiles on any target.

Code that reads CR3, writes CR3, invalidates TLBs, or interacts with VMX/SVM
state is owned by other x86_64 specs and may be target-gated there.

## Examples

Walk a raw CR2-like linear address through a caller-supplied reader:

```zig
const stdx = @import("stdx");
const x86 = stdx.arch.x86_64;
const paging = x86.paging;

const sizes = x86.cpuid.addressSizes();
const config = paging.Config.fromAddressSizes(.level4, sizes, .{
    .pcid = true,
    .no_execute = true,
    .page_1gib = true,
    .supervisor_write_protect = true,
});

const root = try paging.Root.fromCr3(raw_cr3, config);

var reader = DirectMapReader.init(physmap_base);
var walker = paging.Walker(*DirectMapReader).init(config, &reader);

switch (try walker.walkRaw(root, raw_linear, paging.walk.Access.read(.supervisor))) {
    .mapped => |mapping| {
        const phys = mapping.physical;
        const size = mapping.leaf.sizeBytes();
        _ = phys;
        _ = size;
    },
    .fault => |fault| {
        logFault(fault.code, fault.step.level, fault.step.entry.raw());
    },
}
```

Build table entries in caller-owned memory:

```zig
var pml4: paging.table.Pml4 align(paging.table.alignment) = .init();
var pdpt: paging.table.Pdpt align(paging.table.alignment) = .init();

pml4.set(
    paging.Index.fromInt(0),
    paging.table.entry(pdpt_frame, .{ .writable = true }),
);

pdpt.set(
    paging.Index.fromInt(0),
    paging.leaf.page1gib(frame_1gib, .{
        .writable = true,
        .global = true,
    }),
);
```

Dump an entry by level:

```zig
switch (entry.kind(level)) {
    .not_present => log.info("not present raw=0x{x}", .{entry.raw()}),
    .table => {
        const frame = paging.table.frame(entry, level, config) catch |err| {
            log.warn("bad table entry: {s} raw=0x{x}", .{ @errorName(err), entry.raw() });
            return;
        };
        log.info("table frame=0x{x}", .{frame.addressInt()});
    },
    .leaf => {
        const frame = paging.leaf.frame(entry, level, config) catch |err| {
            log.warn("bad leaf entry: {s} raw=0x{x}", .{ @errorName(err), entry.raw() });
            return;
        };
        log.info("leaf size={d} base=0x{x}", .{ frame.sizeBytes(), frame.addressInt() });
    },
}
```

## Required tests

Required unit/model tests:

- `Mode.level4.rootLevel() == .pml4` and `linearBits() == 48`;
- `Mode.level5.rootLevel() == .pml5` and `linearBits() == 57`;
- `Level.indexShift` returns 12, 21, 30, 39, and 48 for PT through PML5;
- `linear.isCanonical` accepts low and high canonical 48-bit addresses;
- `linear.isCanonical` rejects non-canonical 48-bit addresses;
- `linear.isCanonical` accepts valid 57-bit canonical addresses in `.level5`;
- `linear.fromCanonical` returns `error.NonCanonical` for non-canonical input;
- `linear.signExtend` sign-extends from the active high implemented bit;
- `linear.indices` extracts every index for known 4-level and 5-level addresses;
- `Config.validate` rejects physical widths below 32 and above 52;
- `Root.fromCr3` decodes PCID and non-PCID low bits correctly;
- `Root.fromCr3` rejects reserved low bits in non-PCID mode;
- `Root.fromCr3` rejects roots above `physical_bits`;
- `Root.toCr3` round-trips valid roots in PCID and non-PCID modes;
- `Entry.fromRaw` / `raw` round-trip arbitrary `u64` values;
- `Entry.kind` distinguishes not-present, table, and leaf forms at every level;
- `Entry.reservedBits` ignores not-present entries;
- `Entry.reservedBits` catches bit 7 set at PML4/PML5;
- `Entry.reservedBits` catches NX when `features.no_execute == false`;
- `Entry.reservedBits` catches physical address bits above `physical_bits`;
- `Entry.reservedBits` catches misaligned 2 MiB and 1 GiB leaf bases;
- `Entry.reservedBits` catches 1 GiB leaves when `features.page_1gib == false`;
- `table.Pml4`, `table.Pdpt`, `table.Pd`, and `table.Pt` are exactly 4096
  bytes and contain 512 entries;
- `table.Type(level).init` fills every entry with `Entry.empty()`;
- `table.get`, `set`, and `clear` operate on the selected index only;
- `table.entry` and `table.frame` round-trip a `Phys4K.Frame`;
- `leaf.page4kib`, `leaf.page2mib`, `leaf.page1gib`, and `leaf.frame`
  round-trip typed frames;
- `leaf.offsetBits`, `sizeBytes`, and `offsetMask` match 4 KiB, 2 MiB, and
  1 GiB leaves;
- `leaf.Frame` and `leaf.Mapping` methods report base, size, offset bits, and
  offset mask correctly;
- `Walker.walkRaw` translates a 4 KiB mapping;
- `Walker.walkRaw` translates a 2 MiB mapping;
- `Walker.walkRaw` translates a 1 GiB mapping when enabled;
- `Walker.walkRaw` returns `error.NonCanonical` for non-canonical input;
- `Walker.walkRaw` returns not-present faults at each level;
- `Walker.walkRaw` returns reserved-bit faults;
- `Walker.walkRaw` returns write faults for read-only mappings;
- `Walker.walkRaw` returns user faults for supervisor mappings;
- `Walker.walkRaw` returns execute faults for NX mappings;
- `Walker.walkRaw` honors `supervisor_write_protect == false` for supervisor
  writes;
- reader errors propagate as Zig errors and are not converted to page faults;
- the module imports and layout-only declarations compile on non-x86_64 targets.

## Amendments

None.
