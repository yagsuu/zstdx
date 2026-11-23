# `arch.x86_64.cpuid`

`cpuid` queries CPU identification leaves and decodes vendor, signature,
features, deterministic caches, brand bytes, and address widths.

## Queries and availability

`cpuid.query(leaf, subleaf)` passes the leaf to EAX and the subleaf to ECX and
returns raw EAX, EBX, ECX, and EDX values. `cpuid.Leaf` accepts arbitrary
`u32` leaf numbers.
Unavailable leaves and subleaves retain the CPU's raw query behavior.

`cpuid.queryAs(T, leaf, subleaf)` applies `T.from()` to the result. The caller MUST
select a decoder that matches the requested leaf and subleaf.
`cpuid.maxBasicLeaf()` and `cpuid.maxExtendedLeaf()` return EAX from leaves 0
and `0x80000000`, respectively.

Instruction operations require an x86_64 target at compile time. Value types
and pure decoders can be used on other targets. CPUID is available at any CPL
on x86_64, subject to execution-environment restrictions such as CPUID faulting
or virtualization interception. Callers MUST ensure that execution is permitted.

CPUID supplies architectural instruction serialization. The wrapper has no
compiler memory barrier, and decoders add none. Queries read the current logical
processor without caching. Callers control CPU affinity when combining results.
Operations allocate no memory.

## Identification

`cpuid.vendorString()` returns 12 raw bytes in little-endian EBX, EDX, ECX order
from leaf 0. `cpuid.vendor()` applies `cpuid.Vendor.decode()` to these bytes.
Recognized strings are `GenuineIntel`, `AuthenticAMD`, `VIA VIA VIA `, `CentaurHauls`,
`CyrixInstead`, `GenuineTMx86`, and `TransmetaCPU`. Both Transmeta strings map
to `.transmeta`. Other strings map to `.unknown`.

`cpuid.Version.decode(signature)` retains raw EAX and stepping bits 3:0. It adds
extended family to base family only when the base family is `0xF`. It combines
extended model bits with base model only for base family `0x6` or `0xF`.
`cpuid.version()` decodes the leaf-1 signature.

`cpuid.brandString()` returns `null` when extended leaf `0x80000004` is unavailable.
Otherwise it returns the 48 raw bytes from leaves `0x80000002` through
`0x80000004`, in little-endian EAX, EBX, ECX, EDX order for each leaf.
Padding and null bytes remain unchanged.

The hypervisor-present indication is `cpuid.BasicEcx.hypervisor` (leaf 1 ECX bit 31).
Callers can query `cpuid.Leaf.from(0x40000000)` for a hypervisor's maximum leaf and
vendor signature when the execution environment defines that interface.
The conventional hypervisor signature order is EBX, ECX, EDX, unlike the CPU
vendor order. `cpuid.Vendor.decode()` recognizes CPU vendors only.

## Feature values

`cpuid.Basic.from()`, `cpuid.Structured.from()`, and `cpuid.Extended.from()`
preserve all four registers from leaves 1, 7 subleaf 0, and `0x80000001`.
CLFLUSH units represent 8 bytes. `cpuid.Structured.eax` retains the maximum
structured-feature subleaf.

Feature-register types are packed 32-bit values. Bit casts preserve every bit.
Named fields retain CPU-provided encodings. For each feature-register type `F`,
`F.unknown_mask` and `F.unknownBits()` identify unmodeled bits in their original
positions. Unknown bits are not necessarily architecturally reserved.

Callers MUST satisfy feature-enable, privilege, and state requirements before
using reported capabilities.

| Fetch | Result when available | Unavailable behavior |
| --- | --- | --- |
| `cpuid.basicFeatures()` | `Basic` from leaf 1 | Leaf 1 is required on x86_64. |
| `cpuid.structuredFeatures()` | `Structured` from leaf 7, subleaf 0 | All-zero bundle when maximum basic leaf is below 7. |
| `cpuid.extendedFeatures()` | `Extended` from `0x80000001` | All-zero bundle when the extended leaf is absent. |

`cpuid.features()` combines these three fetches without a persistent cache.

## Deterministic caches

`cpuid.caches()` starts a `cpuid.Cache.Iterator` at leaf 4, subleaf 0.
If the maximum basic leaf is below 4, the iterator is already exhausted.
`cpuid.Cache.Iterator.next()` returns successive decoded descriptors until EAX bits
4:0 are zero. It then remains exhausted.

`cpuid.Cache.Descriptor.decode(raw)` returns `null` for that same terminator.
Other cache-kind encodings, including unknown values 4 through 31, are retained.
Descriptors preserve all four raw registers. Line size, partitions, ways,
and sets decode the hardware's zero-based values by adding one. Sets use
`u64` and can reach `2^32`. See the [cache descriptor
declarations](../../../../src/arch/x86_64/cpuid.zig) for field encodings.

The iterator uses leaf 4 without vendor-specific substitution. Callers use raw
queries when a CPU requires a different cache-enumeration interface.

## Address widths

`cpuid.addressSizes()` returns physical, linear, and guest-physical widths from
leaf `0x80000008`. Values are in bits and retain the CPU's encoding, including
a zero guest-physical width.
When the leaf is absent, the result is 32 physical bits, 32 linear bits,
and zero guest-physical bits.

## References

- [CPUID queries and decoders](../../../../src/arch/x86_64/cpuid.zig)
