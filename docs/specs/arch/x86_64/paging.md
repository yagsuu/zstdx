# x86_64 paging

Status: Approved.

`stdx.arch.x86_64.paging` owns architectural data formats, exact producer types,
and a read-only walker for ordinary IA-32e paging. It covers 4-level and 5-level
paging geometry, canonical linear addresses, caller-owned paging-structure
memory, typed entry construction, reserved-bit validation, and deterministic
translation through a caller-supplied physical-memory reader.

The paging surface is an ISA data-format and algorithm primitive. It is not an
address-space manager. It does not allocate paging structures, install CR3,
modify accessed or dirty bits, invalidate TLB entries, handle traps, or select
memory-ownership policy.

## Owned scope

This spec owns:

- the `stdx.arch.x86_64.paging` namespace;
- `Mode` for active 4-level or 5-level ordinary paging;
- `Level`, `Index`, and `Indices` for paging geometry;
- `LinearAddress` for architectural 64-bit linear addresses;
- `PhysicalAddressWidth` for validated x86 physical-address widths;
- `PML5`, `PML4`, `PDPT`, `PD`, and `PT` as exact producer types;
- one exact nested `Entry` and `Memory` type under each producer type;
- `PagingStructureEntry` as the level-unqualified raw reader boundary;
- `TableEntryFlags` and `PageFlags` for typed construction;
- `PageFrame`, `PageAttributes`, and walk results;
- `walk.Access`, `walk.EffectivePermissions`, `walk.Step`,
  `walk.MappedPage`, `walk.Fault`, and `walk.Result`;
- `Walker(Reader)` with explicit and current-CPU construction;
- required tests.

## Deferred scope and non-goals

This spec does not own:

- page-table allocation, growth, reclamation, or ownership;
- virtual-address-space layout policy;
- `map`, `unmap`, `protect`, copy-on-write, or region-management APIs;
- physical-memory-map ownership or address classification;
- direct physical-address dereferencing outside a caller-supplied reader;
- CR3 installation or page-table activation;
- PCID lifetime or TLB tagging policy;
- TLB invalidation or cross-CPU shootdown;
- compiler fences, CPU fences, or cache maintenance for entry publication;
- accessed or dirty-bit writeback;
- page-fault handler installation or trap dispatch;
- segmentation, Intel LAM, AMD UAI, or other address preprocessing;
- final PAT/MTRR memory-type resolution;
- protection keys, SMEP, SMAP, CET, SGX, or shadow-stack checks;
- EPT, NPT, or another second-level translation family.

Second-level translation families are outside this specification.

## Public namespace

Paging is available only through the lower-case architecture namespace:

```zig
const paging = stdx.arch.x86_64.paging;
```

The public declarations are:

```zig
paging.Mode
paging.Level
paging.Index
paging.Indices
paging.LinearAddress
paging.PhysicalAddressWidth

paging.PhysAddr
paging.Phys4K
paging.Phys2M
paging.Phys1G

paging.PML5
paging.PML4
paging.PDPT
paging.PD
paging.PT

paging.PagingStructureEntry
paging.TableEntryFlags
paging.PageFlags
paging.PageFrame
paging.PageAttributes

paging.walk.Access
paging.walk.EffectivePermissions
paging.walk.Step
paging.walk.MappedPage
paging.walk.Fault
paging.walk.Result

paging.Walker
```

The public surface does not contain a level-erased producer type, a generic
producer memory type, or a public entry decoder.

## Source and test ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/paging.zig
src/arch/x86_64/paging/address.zig
src/arch/x86_64/paging/table.zig
src/arch/x86_64/paging/walk.zig

test/arch/x86_64/paging/address_test.zig
test/arch/x86_64/paging/table_test.zig
test/arch/x86_64/paging/walk_test.zig
```

`src/arch/x86_64.zig` re-exports:

```zig
pub const paging = @import("x86_64/paging.zig");
```

`paging.zig` is an alias-only facade.

`paging/address.zig` owns `Mode`, `LinearAddress`, and physical page aliases.

`paging/table.zig` owns paging geometry, physical-address widths, exact producer
types, exact entry and memory types, construction flags, page frames, and
private entry interpretation.

`paging/walk.zig` owns the reader contract, walker state, requested access,
effective permissions, translation results, and faults.

`address_test.zig`, `table_test.zig`, and `walk_test.zig` test the declarations
owned by their matching source files. `test/all.zig` imports all three test files
directly. No flat or umbrella paging test file is part of the approved layout.

## Physical address aliases

```zig
pub const PhysAddr = stdx.addr.PhysAddr;

pub const Phys4K = stdx.addr.Page(
    PhysAddr,
    stdx.addr.pages._4kib,
);
pub const Phys2M = stdx.addr.Page(
    PhysAddr,
    stdx.addr.pages._2mib,
);
pub const Phys1G = stdx.addr.Page(
    PhysAddr,
    stdx.addr.pages._1gib,
);
```

`PhysAddr` names the physical-address domain used by the supplied reader. It can
represent host physical memory, guest physical memory, emulator memory, or an
offline memory image. The reader defines the meaning of the address.

## `Mode`

```zig
pub const Mode = enum {
    level4,
    level5,

    pub fn rootLevel(self: Mode) Level;
    pub fn linearBits(self: Mode) u8;
};
```

`.level4` uses a PML4 root and 48 canonical linear-address bits. `.level5` uses
a PML5 root and 57 canonical linear-address bits.

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
    pub fn pageOffsetBits(self: Level) ?u6;
    pub fn pageSizeBytes(self: Level) ?u64;
    pub fn pageOffsetMask(self: Level) ?u64;
};
```

`indexShift` returns the bit offset of the 9-bit index:

| Level | Shift |
| --- | ---: |
| `.pt` | 12 |
| `.pd` | 21 |
| `.pdpt` | 30 |
| `.pml4` | 39 |
| `.pml5` | 48 |

`next` returns the next lower level. It returns `null` for `.pt`.

The page geometry operations return values for `.pt`, `.pd`, and `.pdpt`. They
return `null` for `.pml4` and `.pml5`.

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

    pub fn at(self: Indices, level: Level) Index;
};
```

`Indices.pml5` is zero for `.level4`. `at` returns the index for the selected
level.

## `LinearAddress`

```zig
pub const LinearAddress = enum(u64) {
    _,

    pub const Error = error{NonCanonical};

    pub fn fromInt(raw_address: u64) LinearAddress;
    pub fn raw(self: LinearAddress) u64;
    pub fn fromCanonical(
        raw_address: u64,
        mode: Mode,
    ) Error!LinearAddress;
    pub fn signExtend(
        raw_address: u64,
        mode: Mode,
    ) LinearAddress;
    pub fn isCanonical(
        self: LinearAddress,
        mode: Mode,
    ) bool;
    pub fn indices(
        self: LinearAddress,
        mode: Mode,
    ) Indices;
};
```

`LinearAddress` is an architectural 64-bit value. It is distinct from
`stdx.addr.VirtAddr` and can represent guest or offline state unrelated to the
host process pointer width.

`fromInt` preserves all input bits. `fromCanonical` returns
`error.NonCanonical` when the value is not sign-extended from the active high
implemented linear-address bit. `signExtend` transforms the low implemented
bits without first validating the high bits.

`indices` requires a canonical address for the selected mode. It asserts this
precondition under safety checks.

The API does not contain `canonicalize`. That name does not distinguish
validation from sign extension.

## `PhysicalAddressWidth`

```zig
pub const PhysicalAddressWidth = enum(u8) {
    bits_32 = 32,
    bits_36 = 36,
    bits_39 = 39,
    bits_40 = 40,
    bits_46 = 46,
    bits_48 = 48,
    bits_52 = 52,

    pub const Error = error{
        UnsupportedPhysicalAddressWidth,
    };

    pub fn fromBits(
        physical_address_bits: u8,
    ) Error!PhysicalAddressWidth;
    pub fn bits(self: PhysicalAddressWidth) u6;
};
```

The type contains the physical-address widths supported by this paging
primitive. Raw CPUID fields remain integers until `fromBits` validates them.
Normalized paging state uses `PhysicalAddressWidth`.

## Exact paging-structure producer types

The producer surface uses the five enum-backed strong types `PML5`, `PML4`,
`PDPT`, `PD`, and `PT`.

Each type owns `InitError`, `Entry`, and `Memory`. Each `InitError` is:

```zig
pub const InitError = error{
    PhysicalAddressTooWide,
};
```

Each type owns these operations:

```zig
pub fn init(
    base_frame: Phys4K.Frame,
) InitError!Producer;
pub fn base(self: Producer) Phys4K.Frame;
pub fn entryAddress(
    self: Producer,
    index: Index,
) PhysAddr;
```

`Producer` denotes the applicable exact producer type. `init` returns
`error.PhysicalAddressTooWide` when bit 52 or a higher bit is set in
`base_frame`. The returned producer stores the validated frame address.

`base` returns the frame supplied to `init`.

`entryAddress` returns `base().address() + index * 8`. The result stays within
the 4096-byte paging structure.

The exact `Entry` and `Memory` declarations are specified in their owning
sections below.

The exact types expose only architecturally valid construction operations:

| Type | Operation | Exact parameter | Return |
| --- | --- | --- | --- |
| `PML5` | `tableEntry` | `child: PML4`, `flags: TableEntryFlags` | `PML5.Entry` |
| `PML4` | `tableEntry` | `child: PDPT`, `flags: TableEntryFlags` | `PML4.Entry` |
| `PDPT` | `tableEntry` | `child: PD`, `flags: TableEntryFlags` | `PDPT.Entry` |
| `PDPT` | `pageEntry` | `frame: Phys1G.Frame`, `flags: PageFlags` | `PDPT.PageEntryError!PDPT.Entry` |
| `PD` | `tableEntry` | `child: PT`, `flags: TableEntryFlags` | `PD.Entry` |
| `PD` | `pageEntry` | `frame: Phys2M.Frame`, `flags: PageFlags` | `PD.PageEntryError!PD.Entry` |
| `PT` | `pageEntry` | `frame: Phys4K.Frame`, `flags: PageFlags` | `PT.PageEntryError!PT.Entry` |

`PDPT`, `PD`, and `PT` each own:

```zig
pub const PageEntryError = error{
    PhysicalAddressTooWide,
};
```

A page-entry operation returns `error.PhysicalAddressTooWide` when bit 52 or a
higher bit is set in the mapped frame address.

The exact child and frame parameter types make invalid level transitions
unrepresentable. Entry construction does not return a runtime level-validation
error.

Entry construction does not receive a memory pointer. It returns a complete
entry value before the caller publishes the value.

## Exact nested `Entry` types

These types are distinct:

```zig
PML5.Entry
PML4.Entry
PDPT.Entry
PD.Entry
PT.Entry
```

Each exact entry type has this API:

```zig
pub const Entry = enum(u64) {
    _,

    pub const TagType = PML5;
    pub const Raw = u64;
    pub const NonPresentError = error{Present};

    pub fn empty() Entry;
    pub fn nonPresent(
        raw_entry: Raw,
    ) NonPresentError!Entry;
    pub fn raw(self: Entry) Raw;
};
```

The snippet shows `PML5.Entry`. Each other exact entry type sets `TagType` to
its owning producer type. `Raw` is `u64` for every exact entry type.

`empty` returns an entry with every bit clear.

`nonPresent` requires bit 0 to be clear. It returns `error.Present` when bit 0
is set. For a non-present entry, the remaining bits are caller-owned metadata.

The exact entry types do not expose unrestricted `fromRaw`. Present entries are
created only by `tableEntry` and `pageEntry`.

## Exact nested `Memory` types

These types are distinct:

```zig
PML5.Memory
PML4.Memory
PDPT.Memory
PD.Memory
PT.Memory
```

Each `Memory` type is the exact hardware-visible memory layout for its owning
paging-structure type:

```zig
pub const Memory = extern struct {
    entries: [512]Entry align(4096),

    pub fn init() Memory;
    pub fn get(
        self: *const Memory,
        index: Index,
    ) Entry;
    pub fn set(
        self: *Memory,
        index: Index,
        entry: Entry,
    ) void;
    pub fn clear(
        self: *Memory,
        index: Index,
    ) void;
};
```

Each `Memory` type is exactly 4096 bytes and has 4096-byte alignment. `init`
sets all 512 entries to `Entry.empty()`.

`get`, `set`, and `clear` access only the selected index. `clear` stores
`Entry.empty()`.

A `Memory` value does not own a physical frame. The caller establishes and
maintains the relationship between a producer type's `base()` result and a
pointer to the matching `Memory` type. The paging library does not allocate,
map, retain, or release that memory.

Copying a `Memory` value copies 4096 bytes. Operations other than initialization
use pointers.

The exact entry parameter prevents cross-level insertion. For example,
`PT.Memory.set` accepts only `PT.Entry`.

## Level-unqualified raw entries

```zig
pub const PagingStructureEntry = packed struct(u64) {
    present: bool,
    writable: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size_or_pat: bool,
    global_or_ignored: bool,
    available_low: u3,
    physical_address_bits: u40,
    available_high: u11,
    no_execute: bool,

    pub fn empty() PagingStructureEntry;
    pub fn fromRaw(
        raw_entry: u64,
    ) PagingStructureEntry;
    pub fn raw(self: PagingStructureEntry) u64;
};
```

`PagingStructureEntry` is a packed structural representation of a raw 64-bit
PML5E, PML4E, PDPTE, PDE, or PTE. `fromRaw` preserves arbitrary reader bits.
The fields identify their architectural bit positions. Context determines
field meaning:

- `page_size_or_pat` is PS at PDPT and PD, PAT at PT, and reserved at PML5 and
  PML4;
- `global_or_ignored` is G for a mapped page and ignored for an entry that
  references a next-level table;
- `dirty` is defined for a mapped page and ignored for an entry that references
  a next-level table;
- `physical_address_bits` contains raw bits 12 through 51. Large-page PAT and
  large-page reserved bits occur within this field.

The type does not classify, validate, construct, or decode a level-dependent
present entry. The private walker knows the containing level and owns
contextual interpretation.

## Construction flags

```zig
pub const TableEntryFlags = struct {
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    cache_disable: bool = false,
    accessed: bool = false,
    no_execute: bool = false,
    available_low: u3 = 0,
    available_high: u11 = 0,
};

pub const PageFlags = struct {
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
```

`TableEntryFlags` applies to an entry that references the next paging
structure. `PageFlags` applies to an entry that maps a page.

All entry-construction operations set the present bit.

`PDPT.pageEntry` and `PD.pageEntry` set PS. `PT.pageEntry` treats bit 7 as PAT.
The large-page operations place PAT at bit 12.

Construction encodes the requested architectural bits. It does not probe the
current CPU or validate target capability state. The caller must not publish an
entry that the target cannot interpret. The walker validates raw entries against
its configured physical width and capability flags.

## `PageFrame`

```zig
pub const PageFrame = union(enum) {
    page4kib: Phys4K.Frame,
    page2mib: Phys2M.Frame,
    page1gib: Phys1G.Frame,

    pub fn level(self: PageFrame) Level;
    pub fn address(self: PageFrame) PhysAddr;
    pub fn addressInt(self: PageFrame) u64;
    pub fn sizeBytes(self: PageFrame) u64;
    pub fn offsetBits(self: PageFrame) u6;
    pub fn offsetMask(self: PageFrame) u64;
};
```

`PageFrame` is the runtime mapped-frame union returned by translation.
Producer page-entry operations accept exact frame types instead of `PageFrame`.

## Page attributes and effective permissions

```zig
pub const PageAttributes = struct {
    accessed: bool,
    dirty: bool,
    global: bool,
    write_through: bool,
    cache_disable: bool,
    pat: bool,
};
```

`PageAttributes` contains accessed, dirty, global, write-through, cache-disable,
and PAT values from the mapped-page entry. It does not contain permissions
accumulated from parent entries. Translation reports accessed and dirty state
without modifying either bit.

```zig
pub const EffectivePermissions = struct {
    writable: bool,
    user: bool,
    executable: bool,
};
```

`walk.EffectivePermissions` contains the R/W, U/S, and execute state accumulated
across all present entries in one translation path.

## `walk.Access`

```zig
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
```

The constructors set the selected operation and preserve the supplied
privilege.

## Walk steps, mapped pages, and faults

```zig
pub const Step = struct {
    level: Level,
    index: Index,
    entry_address: PhysAddr,
    entry: PagingStructureEntry,
};
```

A step identifies one successfully loaded raw entry.

```zig
pub const MappedPage = struct {
    linear: LinearAddress,
    physical: PhysAddr,
    frame: PageFrame,
    attributes: PageAttributes,
    permissions: EffectivePermissions,
    step: Step,
};
```

`physical` contains the mapped frame base plus the page offset from `linear`.
`step` is the mapped-page step.

`walk.MappedPage` is the public successful translation type.

```zig
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
    mapped: MappedPage,
    fault: Fault,
};
```

`Fault.Code` models these architectural page-fault error-code fields:

- `present` is clear for `.not_present` and set for other modeled faults;
- `write` is set for write accesses;
- `user` is set for user accesses;
- `reserved` is set only for `.reserved_bits`;
- `instruction_fetch` is set for execute accesses only when execute-disable is
  enabled;
- bits 5 through 15 are zero.

A fault is data. It does not imply that the library installed, raised, or
handled a CPU exception.

## Reader interface

`Walker(Reader)` stores a caller-owned `*Reader`. A conforming reader exposes an
`Error` set and this method:

```zig
pub fn readEntry(
    self: *Reader,
    address: paging.PhysAddr,
) Error!paging.PagingStructureEntry;
```

`address` is the physical byte address of the 8-byte entry to load. The reader
owns bounds checks, physical-memory availability, and little-endian conversion.

The reader can use a direct map, guest-memory backend, emulator, crash dump, or
test model. The reader must return the raw bits stored at `address`.

## `Walker(Reader)`

```zig
pub fn Walker(comptime Reader: type) type {
    return struct {
        root_table_base: Phys4K.Frame,
        mode: Mode,
        physical_address_width: PhysicalAddressWidth,
        flags: Flags,
        reader: *Reader,

        pub const Flags = packed struct(u3) {
            page_1gib_supported: bool = false,
            supervisor_write_protect: bool = false,
            execute_disable_enabled: bool = false,
        };

        pub const Input = struct {
            root_table_base: PhysAddr,
            mode: Mode,
            physical_address_width: PhysicalAddressWidth,
            flags: Flags = .{},
        };

        pub const InitError = error{
            Misaligned,
            PhysicalAddressTooWide,
        };

        pub const InitCurrentCPUError =
            InitError ||
            PhysicalAddressWidth.Error ||
            stdx.arch.x86_64.registers.cr3.CR3.LowError ||
            stdx.arch.x86_64.registers.cr4.PCIDError ||
            stdx.arch.x86_64.registers.cr4.Level5Error ||
            stdx.arch.x86_64.registers.efer.Error ||
            error{
                InvalidLinearWidth,
                InvalidNoFlush,
                InvalidPagingState,
                ReservedBits,
            };

        pub fn init(
            input: Input,
            reader: *Reader,
        ) InitError!@This();

        pub fn initCurrentCPU(
            reader: *Reader,
        ) InitCurrentCPUError!@This();

        pub fn updateRootTable(
            self: *@This(),
            root_table_base: PhysAddr,
        ) InitError!void;

        pub fn translate(
            self: *const @This(),
            linear_address: LinearAddress,
            access: walk.Access,
        ) Reader.Error!walk.Result;
    };
}
```

`Flags` belongs to the walker because the fields control entry validation and
access checks. `Input` only transports constructor values.

The all-zero `Flags` value has these semantics:

- 1 GiB pages are unsupported;
- supervisor writes ignore effective R/W;
- bit 63 is reserved instead of NX.

`init` converts `root_table_base` to a 4 KiB frame. It returns
`error.Misaligned` for an unaligned address. It returns
`error.PhysicalAddressTooWide` when the root does not fit the selected physical
width.

`updateRootTable` validates a complete replacement before mutation. It changes
only `root_table_base`. It does not write CR3 or invalidate a TLB entry.

## Current-CPU construction

`initCurrentCPU` reads CPUID, CR0, CR3, CR4, and EFER. It validates active
protected-mode, physical-address-extension, and IA-32e paging state. It derives:

- the root table base from CR3;
- the mode from CR4.LA57;
- the physical-address width from CPUID;
- 1 GiB-page support from CPUID;
- supervisor write-protect behavior from CR0.WP;
- execute-disable behavior from CPUID and EFER.NXE.

The method converts these values to the same semantic state accepted by `init`.
It does not retain raw register values.

`initCurrentCPU` requires CPL 0. The caller must prevent migration and
paging-state replacement during capture. The method does not disable interrupts
or preemption.

A privilege violation causes the architectural fault associated with a
privileged register or MSR read. It is not a Zig error.

The current-CPU constructor is a snapshot. Later CPU-state changes do not mutate
the walker.

## Translation boundary

`translate` requires `linear_address` to be canonical under `mode`. The caller
must apply segmentation, Intel LAM, AMD UAI, and other architectural address
preprocessing before the call.

The walker asserts canonicality under safety checks. It does not return
`error.NonCanonical`. x86 rejects a non-canonical address before an ordinary
page walk.

A crash-dump or mapping-inspection consumer can request
`walk.Access.read(.supervisor)`. Within this spec's non-goals, supervisor read
is not restricted by R/W, U/S, or NX. The successful result still reports all
effective permissions.

## Private resolution model

The walker uses one private runtime descriptor:

```zig
const WalkTable = struct {
    base: Phys4K.Frame,
    level: Level,

    fn nextTable(
        self: WalkTable,
        entry: PagingStructureEntry,
    ) ?WalkTable;
};
```

`WalkTable` keeps a typed 4 KiB table base and level together. `nextTable`
returns the referenced child table when a validated present entry references
one. It returns `null` when the entry maps a page. `WalkTable` does not contain
permissions or memory ownership state.

`translate` keeps the requested access and accumulated writable, user, and
executable state in local values. The walker configuration remains immutable
during translation.

The walk loop is bounded by the numeric root level. A 4-level walk performs at
most four iterations. A 5-level walk performs at most five iterations. Each
iteration:

1. computes the entry address;
2. calls `Reader.readEntry`;
3. returns a not-present fault when P is clear;
4. validates the present encoding;
5. intersects R/W, U/S, and execute state with
   `EffectivePermissions.intersect`;
6. calls `WalkTable.nextTable` or processes a mapped page.

Mapped-page processing checks permissions before it decodes the page frame and
attributes. It then returns a permission fault or constructs `MappedPage`.

Private operations exist only for non-trivial semantic boundaries:

- walker configuration determines whether a present entry has reserved bits;
- `EffectivePermissions` intersects path permissions with a present entry;
- `Flags` applies permission-fault precedence and constructs a permission
  `Fault`;
- `Fault` constructs a consistent reason, error code, and step;
- `ResolvedPage` converts a validated mapped-page entry into a `PageFrame` and
  `PageAttributes`;
- `MappedPage` combines the resolved page, linear address, permissions, and
  terminal step into the successful result.

The private implementation does not expose `decodeEntry`, `Decoded`,
`DecodeContext`, or a generic `Context` type. It does not use private
translation-state or intermediate target-result types.

## Reserved-bit validation

For a present entry, the walker validates:

- physical-address bits above `physical_address_width`;
- PS at PML5 or PML4;
- a PDPT page mapping when 1 GiB pages are unsupported;
- reserved address bits in 2 MiB and 1 GiB page entries;
- NX when execute-disable is not enabled.

Not-present detection occurs before reserved-bit validation. Other bits in a
non-present entry do not produce a reserved-bit fault.

A reserved encoding produces `walk.Fault.Reason.reserved_bits`. It is not a Zig
error.

## Permission accumulation and checks

Effective permissions start with `writable`, `user`, and `executable` set. For
every present entry, `EffectivePermissions.intersect` performs these explicit
intersections:

```zig
writable = writable and entry.writable();
user = user and entry.userAccessible();
executable = executable and entry.executable();
```

No permission state is stored in a producer type, exact `Entry`, `Memory`,
private `WalkTable`, or private resolved-page value.

Permission checks occur after the mapped-page entry updates the accumulated
state. Fault precedence is:

1. `.user_to_supervisor`;
2. `.write_to_read_only`;
3. `.execute_disabled`.

A user access faults when effective `user` is false.

A write access faults when effective `writable` is false and either the access
is user or `supervisor_write_protect` is true.

An execute access faults when effective `executable` is false.

## Allocation, waiting, capacity, and bounds

| Operation | Allocation | Waiting | Bound |
| --- | --- | --- | --- |
| Address and geometry operations | none | never | O(1) |
| Exact producer `init` | none | never | O(1) |
| `tableEntry` and `pageEntry` | none | never | O(1) |
| `Memory.init` | none | never | exactly 512 entries |
| `Memory.get`, `set`, and `clear` | none | never | O(1) |
| `Walker.init` | none | never | O(1) |
| `Walker.initCurrentCPU` | none | never by paging code | O(1) |
| `Walker.updateRootTable` | none | never | O(1) |
| 4-level `Walker.translate` | none | reader-defined | at most 4 reader calls |
| 5-level `Walker.translate` | none | reader-defined | at most 5 reader calls |

The paging implementation does not allocate, sleep, block, spin, call a
scheduler, or probe the current CPU except through `initCurrentCPU`. A reader
can have a stronger waiting or allocation behavior; that behavior belongs to
the reader contract.

## Mutation, concurrency, ordering, and invalidation

Exact entry construction is value-only. A construction error cannot mutate a
`Memory` value because construction does not receive a memory pointer.

`Memory.set` and `Memory.clear` use plain stores. The caller owns synchronization
for concurrent access.

Concurrent calls to `translate` are permitted only when the reader supports
concurrent reads and no caller mutates walker state. `updateRootTable` requires
exclusive mutation of the walker.

A caller that modifies a reachable paging structure owns:

- compiler and CPU ordering;
- synchronization with software walkers and hardware page walks;
- TLB invalidation;
- cross-CPU shootdown;
- reclamation of replaced memory and mapped frames.

The paging implementation does not issue fences, invalidation instructions, or
cache-maintenance instructions.

A translation never writes a paging-structure entry. It does not set accessed
or dirty bits.

## Error and fault distinction

Producer validation, walker initialization, and reader failures are Zig errors.

Raw page-walk failures after a successful reader call are `walk.Result.fault`
values.

A reader error propagates unchanged. The walker does not convert it to a page
fault.

A non-canonical input violates the `translate` precondition. It is not a page
fault because the processor rejects the address before the page walk.

## Target gating

Address, producer, memory-layout, and explicit-walker declarations compile on
every target. They contain no inline assembly.

`initCurrentCPU` references target-gated x86_64 CPUID and register operations.
Referencing it on an unsupported target is a compile error.

## Testing

Address-model tests MUST verify 4-level and 5-level geometry, canonical-address acceptance and rejection, sign extension, and complete index extraction. Producer-model tests MUST verify supported and unsupported physical widths; distinct exact producer, entry, and memory types; 4096-byte layouts with 512 entries; raw-entry round trips; exact table and page encodings; flag positions; physical-address overflow; transactional construction; and boundary entry addresses. Walker-model tests MUST use a controlled reader to verify initialization, root replacement without mutation on error, 4-level and 5-level walks, all mapped page sizes, the four- and five-reader-call bounds, permission accumulation and precedence, reserved encodings, reader-error propagation, and no entry mutation during translation. Compile tests MUST verify the explicit walker on non-x86_64 and target-gate `initCurrentCPU`; a CPL 0 integration test MUST verify `initCurrentCPU` when the environment provides that prerequisite. These tests prove geometry, ABI layouts, construction errors, translation state transitions, fault precedence, reader boundaries, and target gating.
