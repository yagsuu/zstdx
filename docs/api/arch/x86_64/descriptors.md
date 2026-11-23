# `arch.x86_64.descriptors`

`stdx.arch.x86_64.descriptors` provides value types for IA-32e segment,
system, and interrupt-descriptor-table entries.

## Representation

The [descriptor types](../../../../src/arch/x86_64/descriptors.zig)
use exact-width packed layouts:

| Type | Size | Use |
| --- | ---: | --- |
| `Segment` | 8 bytes | Code or data descriptor in a GDT or LDT |
| `System` | 16 bytes | LDT or 64-bit TSS descriptor in two consecutive GDT slots |
| `Gate` | 16 bytes | Interrupt or trap gate in an IDT |

The caller supplies architectural table alignment.

## Construction and raw values

In the shared rules below, `D` denotes `Segment`, `System`, or `Gate`.
`D.init()` validates the constructed descriptor before returning it.

| Constructor | Address input | Other input |
| --- | --- | --- |
| `Segment.init()` | 32-bit base | 20-bit raw limit |
| `System.init()` | 64-bit base | 20-bit raw limit |
| `Gate.init()` | 64-bit handler offset | 16-bit selector |

All options default to ring 0 and present. Other flags default to clear.

`Segment.Kind` represents all 16 architectural code/data type nibbles,
including accessed, expand-down, and conforming variants.
`System.Kind` and `Gate.Kind` preserve unnamed raw type values.

`D.from()` preserves every input bit. `D.raw()` returns those bits unchanged.
Use `D.validate()` to check raw or directly constructed values.

## Limits and targets

`Segment.rawLimit()` and `System.rawLimit()` return the encoded 20-bit limit.
`Segment.limit()` and `System.limit()` return the inclusive byte limit:
the raw limit when granularity is clear, or
`(raw_limit << 12) | 0xfff` when granularity is set. The maximum result is
`0xffff_ffff`.

`Gate.Options.ist` accepts 0–7. Zero disables IST selection. Values 1–7 select
the corresponding TSS IST entry.

The caller must supply canonical system bases and handler offsets where
the architecture requires them. The caller also supplies valid referenced
memory, selectors, TSS state, handler conventions, and privilege policy.

## Validation errors

The following checks apply in the listed order:

| Type | First check | Subsequent check |
| --- | --- | --- |
| `Segment` | Clear class bit → `ReservedBits` | Long mode on data, or long mode with default operand size → `InvalidSegmentMode` |
| `System` | Set class bit or nonzero reserved field → `ReservedBits` | Kind other than `.ldt`, `.tss_available`, or `.tss_busy` → `InvalidSystemKind` |
| `Gate` | Set class bit or nonzero reserved field → `ReservedBits` | Kind other than `.interrupt` or `.trap` → `InvalidGateKind` |

Presence may be clear in validated descriptors. Operations leave caller storage
unchanged and perform no allocation.

The caller owns table storage, publication, synchronization with descriptor
consumers, and the lifetime of referenced storage and handlers.
Loading descriptor-table and selector registers follows the
[register contract](registers.md).

## References

- [Descriptor formats](../../../../src/arch/x86_64/descriptors.zig)
