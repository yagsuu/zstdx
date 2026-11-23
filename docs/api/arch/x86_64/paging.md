# `arch.x86_64.paging`

`stdx.arch.x86_64.paging` provides IA-32e paging layouts, typed entry
construction, and a read-only walker through caller-supplied physical memory.
Names below are relative to `stdx.arch.x86_64.paging`.

## Choose addresses and paging mode

[Paging modes](../../../../src/arch/x86_64/paging/address.zig) select
a PML4 root and 48 linear-address bits for `.level4`, or a PML5 root
and 57 linear-address bits for `.level5`.

`LinearAddr.from()` preserves all 64 bits. `LinearAddr.fromCanonical()`
returns `NonCanonical` unless the address is sign-extended from bit 47 or 56,
according to the mode. `LinearAddr.signExtend()` discards the high bits and
sign-extends the implemented low bits. `LinearAddr.index(level)` extracts
nine bits without checking canonicality or mode.

[Paging geometry](../../../../src/arch/x86_64/paging/table.zig) uses:

| Level | Index shift | Leaf size |
| --- | ---: | ---: |
| `.pt` | 12 | 4 KiB |
| `.pd` | 21 | 2 MiB |
| `.pdpt` | 30 | 1 GiB |
| `.pml4` | 39 | none |
| `.pml5` | 48 | none |

`Index.from()` accepts 0–511. Each table has 512 entries.

`PhysAddr` is the physical-address domain interpreted by the reader.
`Phys4K.Base`, `Phys2M.Base`, and `Phys1G.Base` carry page-aligned bases.
Callers must preserve the validity of these base values.

`PhysWidth.from()` accepts every integer width from 32 through 52, inclusive.
Other values return `UnsupportedPhysicalAddressWidth`.
`PhysWidth.checkAddress()` returns `PhysicalAddressTooWide` if any bit at or
above the selected width is set. Callers must use a valid width in walker
configuration. Construction does not mask an oversized physical address.

## Construct and publish tables

`PML5`, `PML4`, `PDPT`, `PD`, and `PT` identify physical 4 KiB table bases.
In the shared construction rules, `T` denotes one of these table types.
`T.init()` returns `PhysicalAddressTooWide` for addresses with bit 52 or
higher set. `T.entryAddress(index)` returns `base + index * 8`.

Each table type owns distinct `Entry` and `Storage` types.
Construction follows these level and alignment constraints:

| Constructor | Target |
| --- | --- |
| `PML5.tableEntry()` | `PML4` |
| `PML4.tableEntry()` | `PDPT` |
| `PDPT.tableEntry()` | `PD` |
| `PD.tableEntry()` | `PT` |
| `PDPT.pageEntry()` | `Phys1G.Base` |
| `PD.pageEntry()` | `Phys2M.Base` |
| `PT.pageEntry()` | `Phys4K.Base` |

Page constructors return `PhysicalAddressTooWide` for frame addresses with
bit 52 or higher set. Construction returns a value without changing storage.
The caller MUST choose flags and addresses supported by the target CPU and
its active controls, including the target's physical-address width.

`TableFlags` and `PageFlags` default to all bits clear. Constructors set
presence and encode the supplied flags. Table constructors clear bits 6–8.
Huge-page constructors set PS at bit 7, put PAT at bit 12, and clear reserved
address bits. The 4 KiB constructor puts PAT at bit 7.

Each typed `T.Entry.empty()` is zero. `T.Entry.nonPresent(raw)` preserves
arbitrary metadata when bit 0 is clear, or returns `Present` otherwise.
`T.Entry.raw()` preserves the complete encoding.

Each `T.Storage` is an extern layout of 512 eight-byte entries, with size
and alignment both 4096 bytes. `T.Storage.init()` clears every entry.
`T.Storage.get()`, `T.Storage.set()`, and `T.Storage.clear()` access only
the selected index. `T.Storage.clear()` stores zero.
These are ordinary memory accesses, with no atomicity or publication guarantee.
Copying storage copies the entire 4096-byte table.

## Decode an entry

[`Entry`](../../../../src/arch/x86_64/paging/table.zig) is a packed 64-bit raw
entry. `Entry.from()` and `Entry.raw()` preserve all bits without validation.
`Entry.decode(level, config)` classifies the entry without accessing memory.

| Decode configuration | Requirement or default |
| --- | --- |
| `physical_width` | Required. Valid widths are 32–52 inclusive. |
| `allow_1gib` | Defaults to false. Enables 1 GiB leaves. |
| `nxe` | Defaults to false. Permits NX encodings. |

| Classification | Condition and result |
| --- | --- |
| `.absent` | Presence is clear. All other bits and configuration are ignored. |
| `.reserved` | Present entry fails a rule below. |
| `.table` | Valid non-leaf. Returns its 4 KiB child base and next level. |
| `.page` | Valid leaf. Returns its frame and attributes. Every present PT entry is a leaf. |

A present entry is reserved for any of these conditions:

| Condition | Rule |
| --- | --- |
| Invalid physical width | Width must be 32–52 inclusive. |
| NX set | Requires `nxe`. |
| Address above physical width | Address bits at or above the width must be clear. |
| PS at PML4 or PML5 | PS must be clear. |
| 1 GiB leaf | Requires `allow_1gib`. Bits 13–29 must be clear. |
| 2 MiB leaf | Bits 13–20 must be clear. |

For huge pages, bit 12 is PAT and is removed from the frame address.
At PT, bit 7 is PAT. Available fields and ignored table-entry bits do not
cause reserved classifications.

`PageFrame` identifies a 4 KiB, 2 MiB, or 1 GiB aligned frame.
`PageAttributes` reports accessed, dirty, global, cache, and PAT state from
the leaf only. Final PAT/MTRR memory-type resolution remains the caller's
responsibility.

## Configure a walker

[`Walker(Reader)`](../../../../src/arch/x86_64/paging/walk.zig) uses a reader
that supplies `Reader.Error` and
`readEntry(self: *Reader, address: PhysAddr) Reader.Error!Entry`.
The address is the physical byte address of one eight-byte entry.
The reader owns bounds, availability, and little-endian conversion.

`Walker(Reader).init()` takes the following `Config`:

| Configuration | Requirement or default |
| --- | --- |
| `root` | 4 KiB aligned and within `physical_width`. |
| `mode` | `.level4` or `.level5`. |
| `physical_width` | Valid `PhysWidth` from 32–52 inclusive. |
| `allow_1gib` | Defaults to false. |
| `write_protect` | Defaults to false. Applies read-only restrictions to supervisor writes. |
| `nxe` | Defaults to false. |

Root validation returns `Misaligned` before `PhysicalAddressTooWide`.
`Walker(Reader).setRoot()` uses the same validation. Failure leaves the root
unchanged. Success changes only the software walker's root.

`Walker(Reader).initCurrent()` requires CPL 0 and reads CPUID, CR0, CR3, CR4, and EFER.
The caller MUST prevent migration and paging-state replacement during capture
and handle privilege faults.

Capture requires active protected-mode, PAE, and IA-32e paging. It validates
physical width, sufficient linear width, LA57 and PCID capability state,
CR3 low bits and base, no-flush use, and NX capability state.
It rejects active SMEP, SMAP, PKE, PKS, and LAM with the corresponding
`UnsupportedSMEP`, `UnsupportedSMAP`, `UnsupportedPKE`, `UnsupportedPKS`,
or `UnsupportedLAM` error. Other capture errors retain their register or
width validation meaning, including `InvalidPagingState`,
`InvalidLinearWidth`, `InvalidNoFlush`, and `ReservedBits`.
Success records the current root, mode, 1 GiB support, CR0.WP, and NXE
behavior. Later CPU-state changes do not update the walker.

Explicit construction and layout operations are target-independent.
`Walker(Reader).initCurrent()` uses target-gated x86_64 register and CPUID operations.

## Translate and interpret faults

`Walker(Reader).translate()` takes a `LinearAddr` and `walk.Access` for read,
write, or execute at supervisor or user privilege. Before calling it, apply
segmentation and architectural address preprocessing.

Translation follows this order:

1. Reject non-canonical input with `NonCanonical`, without a reader call.
2. Read one entry per level from root to leaf. Propagate reader errors unchanged.
3. Stop at the first absent or reserved entry and return `walk.Result.fault`.
4. At a valid leaf, apply permission checks in the table order below.

Four-level walks make at most four reader calls. Five-level walks make at
most five. Effective `walk.Permissions` intersect writable and user bits
across the path. Execution requires NX clear in every entry.

| Priority at a valid leaf | Fault reason | Condition |
| --- | --- | --- |
| 1 | `.user_to_supervisor` | User access with effective user permission clear. |
| 2 | `.write_to_read_only` | Write with effective writable permission clear and either user access or `write_protect` set. |
| 3 | `.execute_disabled` | Execute access with effective executable permission clear. |

Permission faults identify the leaf step even when an ancestor restricts
access. An absent or reserved descendant takes precedence over an ancestor's
permission restriction. Supervisor reads through valid leaves succeed and
still report effective permissions.
This model does not apply protection keys, SMEP, SMAP, CET, SGX,
shadow-stack checks, or second-level translation.

`walk.Mapping` contains the input linear address, frame, leaf attributes,
effective permissions, and terminal `walk.Step`. The physical address is
`frame_base | (linear & frame.offsetMask())`.
`walk.Step.address` identifies the loaded entry.
`walk.Step.entry` preserves its raw bits.

Faults are returned as data with a reason, code, and stopping step.

| `walk.Fault.Code` bits | Meaning |
| --- | --- |
| `present` | Clear only for `.not_present`. |
| `reserved` | Set only for `.reserved_bits`. |
| `write`, `user` | Reflect the requested access. |
| `instruction_fetch` | Set only for execute access with NXE enabled. |
| 5–15 | Always zero. |

## Ownership, lifetime, and invalidation

The caller owns physical memory, table storage, and their address relationships.
Keep the borrowed reader and memory available throughout translation.
The walker reads entries without modifying them. Reader allocation, waiting,
and side effects follow the reader's contract.

Concurrent translation requires a reader that supports concurrent calls and
unchanged walker configuration. Root replacement requires exclusive access.
The caller must synchronize table changes with software and hardware walkers.
The caller also owns publication ordering, TLB invalidation, cross-CPU
shootdown, and safe reclamation of replaced tables and frames.

## References

- [Paging exports](../../../../src/arch/x86_64/paging.zig)
- [Address geometry](../../../../src/arch/x86_64/paging/address.zig)
- [Table formats](../../../../src/arch/x86_64/paging/table.zig)
- [Read-only walker](../../../../src/arch/x86_64/paging/walk.zig)
