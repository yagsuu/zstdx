# x86_64 CPUID decoders

Status: Approved.

`stdx.arch.x86_64.cpuid` owns raw CPUID accessors and decoders for vendor identification, family/model/stepping, typed feature masks, cache topology, brand strings, and address sizes.

## Owned scope

This spec owns:

- raw `cpuid.Result`, `cpuid.Leaf`, `cpuid.leaf`, `cpuid.subleaf`, `cpuid.maxBasicLeaf`, and `cpuid.maxExtendedLeaf`;
- `cpuid.Vendor` enum + `vendor()` and `vendorString()`;
- `cpuid.Version` family/model/stepping decoder built on leaf 1 EAX;
- typed feature masks as `packed struct(u32)` per register for:
  leaf 1 EDX (`BasicFeatureEdx`), leaf 1 ECX (`BasicFeatureEcx`),
  leaf 7 subleaf 0 EBX/ECX/EDX (`StructuredEbx`/`Ecx`/`Edx`),
  extended leaf `0x80000001` EDX/ECX (`ExtendedFeatureEdx`/`Ecx`);
- reserved-bit reporting via `hasReserved()` on every mask type;
- `cpuid.cache.Descriptor` and `cpuid.cache.Iterator` decoding leaf 4
  deterministic-cache subleaves;
- `cpuid.brandString()` on extended leaves `0x80000002`..`0x80000004`;
- `cpuid.Features` bundle for one-shot fetch of every feature mask;
- `cpuid.AddressSizes` and `cpuid.addressSizes()` on leaf `0x80000008`
  because hv/kernel paths hit it constantly;

## Deferred scope and non-goals

This spec does not own:

- global feature caching or a hidden `hasFeature(...)` shortcut;
- errata database or workaround selection;
- feature gating of other zstdx primitives beyond the existing
  `cache.lineSize` probe in base;
- SGX enumeration (leaf 0x12), SEV/SNP topology (AMD 0x8000001F),
  extended-state size enumeration (leaf 0xD subleaves);
- hypervisor-leaf recognition (leaf 0x40000000..`0x400000FF` range);
- CPUID emulation, spoofing, or fake-CPU test harness beyond raw
  `cpuid.leaf`/`subleaf` results;
- AVX / AMX state-size math (belongs with a future `xsave` extension);
- thermal/power leaves (leaf 6), perfmon leaf 0xA, or leaf 0x15
  TSC/core-crystal ratio;
- AMD-specific leaves 0x80000005 / 0x80000006 (legacy L1/L2 cache/TLB
  descriptors); leaf 4 covers modern topology on both vendors;
- legacy Intel leaf 2 TLB descriptor byte table.

## Public namespace

`stdx.arch.x86_64.cpuid` is the public CPUID namespace:

```zig
stdx.arch.x86_64.cpuid.Vendor
stdx.arch.x86_64.cpuid.Version
stdx.arch.x86_64.cpuid.BasicFeatureEdx
stdx.arch.x86_64.cpuid.BasicFeatureEcx
stdx.arch.x86_64.cpuid.BasicFeatures
stdx.arch.x86_64.cpuid.StructuredEbx
stdx.arch.x86_64.cpuid.StructuredEcx
stdx.arch.x86_64.cpuid.StructuredEdx
stdx.arch.x86_64.cpuid.StructuredFeatures
stdx.arch.x86_64.cpuid.ExtendedFeatureEdx
stdx.arch.x86_64.cpuid.ExtendedFeatureEcx
stdx.arch.x86_64.cpuid.ExtendedFeatures
stdx.arch.x86_64.cpuid.Features
stdx.arch.x86_64.cpuid.cache
stdx.arch.x86_64.cpuid.cache.Kind
stdx.arch.x86_64.cpuid.cache.Descriptor
stdx.arch.x86_64.cpuid.cache.Iterator
stdx.arch.x86_64.cpuid.AddressSizes
stdx.arch.x86_64.cpuid.vendor
stdx.arch.x86_64.cpuid.vendorString
stdx.arch.x86_64.cpuid.version
stdx.arch.x86_64.cpuid.brandString
stdx.arch.x86_64.cpuid.basicFeatures
stdx.arch.x86_64.cpuid.structuredFeatures
stdx.arch.x86_64.cpuid.extendedFeatures
stdx.arch.x86_64.cpuid.features
stdx.arch.x86_64.cpuid.caches
stdx.arch.x86_64.cpuid.addressSizes
```

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/cpuid.zig
test/arch/x86_64/cpuid/all.zig
test/arch/x86_64/cpuid/cpuid_test.zig
```

`src/arch/x86_64.zig` re-exports `pub const cpuid = @import("x86_64/cpuid.zig");`.

## Target gating

The module compiles on any target.
Every accessor that emits `cpuid` produces `@compileError` when
referenced on a non-x86_64 target.

Operations whose semantics do not depend on the instruction set
(`Vendor` enum, `Features` bundle construction from raw values, `cache.Descriptor`
type layout) compile on any target.

## API

### Vendor and version

```zig
pub const cpuid = struct {
    pub const Result = struct {
        eax: u32,
        ebx: u32,
        ecx: u32,
        edx: u32,
    };

    pub const Leaf = enum(u32) {
        feature_info = 0x0000_0001,
        _,
    };

    pub fn leaf(leaf_id: Leaf) Result;
    pub fn subleaf(leaf_id: Leaf, subleaf_id: u32) Result;
    pub fn maxBasicLeaf() u32;
    pub fn maxExtendedLeaf() u32;

    pub const Vendor = enum {
        intel,
        amd,
        via,
        cyrix,
        transmeta,
        centaur,
        unknown,
    };

    pub const Version = struct {
        family: u12,
        model: u8,
        stepping: u4,
        eax: u32,
    };

    pub fn vendor() Vendor;
    pub fn vendorString() [12]u8;
    pub fn version() Version;
    pub fn brandString() ?[48]u8;
};
```

### Feature masks

Every feature mask is a `packed struct(u32)`. Named bits use the
lowercase-underscore form of the canonical Intel SDM / AMD APM mnemonic.
Reserved positions use `_reservedN: uK = 0` fields at their exact bit
offsets so `@bitCast(u32, mask)` round-trips every bit.

```zig
pub const BasicFeatureEdx = packed struct(u32) {
    fpu: bool,
    vme: bool,
    de: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    _reserved_10: u1 = 0,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    clflush: bool,
    _reserved_20: u1 = 0,
    ds: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm: bool,
    _reserved_30: u1 = 0,
    pbe: bool,

    pub fn hasReserved(self: BasicFeatureEdx) bool;
};

pub const BasicFeatureEcx = packed struct(u32) {
    sse3: bool,
    pclmulqdq: bool,
    dtes64: bool,
    monitor: bool,
    ds_cpl: bool,
    vmx: bool,
    smx: bool,
    eist: bool,
    tm2: bool,
    ssse3: bool,
    cnxt_id: bool,
    sdbg: bool,
    fma: bool,
    cmpxchg16b: bool,
    xtpr: bool,
    pdcm: bool,
    _reserved_16: u1 = 0,
    pcid: bool,
    dca: bool,
    sse4_1: bool,
    sse4_2: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tsc_deadline: bool,
    aesni: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdrand: bool,
    hypervisor: bool,

    pub fn hasReserved(self: BasicFeatureEcx) bool;
};

pub const StructuredEbx = packed struct(u32) {
    fsgsbase: bool,
    tsc_adjust: bool,
    sgx: bool,
    bmi1: bool,
    hle: bool,
    avx2: bool,
    fdp_excptn_only: bool,
    smep: bool,
    bmi2: bool,
    erms: bool,
    invpcid: bool,
    rtm: bool,
    rdt_m: bool,
    fpu_cs_ds_deprecated: bool,
    mpx: bool,
    rdt_a: bool,
    avx512f: bool,
    avx512dq: bool,
    rdseed: bool,
    adx: bool,
    smap: bool,
    avx512_ifma: bool,
    _reserved_22: u1 = 0,
    clflushopt: bool,
    clwb: bool,
    intel_pt: bool,
    avx512pf: bool,
    avx512er: bool,
    avx512cd: bool,
    sha: bool,
    avx512bw: bool,
    avx512vl: bool,

    pub fn hasReserved(self: StructuredEbx) bool;
};

pub const StructuredEcx = packed struct(u32) {
    prefetchwt1: bool,
    avx512_vbmi: bool,
    umip: bool,
    pku: bool,
    ospke: bool,
    waitpkg: bool,
    avx512_vbmi2: bool,
    cet_ss: bool,
    gfni: bool,
    vaes: bool,
    vpclmulqdq: bool,
    avx512_vnni: bool,
    avx512_bitalg: bool,
    tme_en: bool,
    avx512_vpopcntdq: bool,
    _reserved_15: u1 = 0,
    la57: bool,
    mawau: u5,
    rdpid: bool,
    kl: bool,
    bus_lock_detect: bool,
    cldemote: bool,
    _reserved_26: u1 = 0,
    movdiri: bool,
    movdir64b: bool,
    enqcmd: bool,
    sgx_lc: bool,
    pks: bool,

    pub fn hasReserved(self: StructuredEcx) bool;
};

pub const StructuredEdx = packed struct(u32) {
    _reserved_0: u2 = 0,
    avx512_4vnniw: bool,
    avx512_4fmaps: bool,
    fast_short_rep_mov: bool,
    uintr: bool,
    _reserved_6: u2 = 0,
    avx512_vp2intersect: bool,
    srbds_ctrl: bool,
    md_clear: bool,
    rtm_always_abort: bool,
    _reserved_12: u1 = 0,
    rtm_force_abort: bool,
    serialize: bool,
    hybrid: bool,
    tsxldtrk: bool,
    _reserved_17: u1 = 0,
    pconfig: bool,
    architectural_lbrs: bool,
    cet_ibt: bool,
    _reserved_21: u1 = 0,
    amx_bf16: bool,
    avx512_fp16: bool,
    amx_tile: bool,
    amx_int8: bool,
    ibrs_ibpb: bool,
    stibp: bool,
    l1d_flush: bool,
    ia32_arch_capabilities: bool,
    ia32_core_capabilities: bool,
    ssbd: bool,

    pub fn hasReserved(self: StructuredEdx) bool;
};

pub const ExtendedFeatureEdx = packed struct(u32) {
    _reserved_0: u11 = 0,
    syscall: bool,
    _reserved_12: u8 = 0,
    nx: bool,
    _reserved_21: u5 = 0,
    pdpe1gb: bool,
    rdtscp: bool,
    _reserved_28: u1 = 0,
    lm: bool,
    _reserved_30: u2 = 0,

    pub fn hasReserved(self: ExtendedFeatureEdx) bool;
};

pub const ExtendedFeatureEcx = packed struct(u32) {
    lahf_lm: bool,
    cmp_legacy: bool,
    svm: bool,
    extapic: bool,
    cr8_legacy: bool,
    abm: bool,
    sse4a: bool,
    misalignsse: bool,
    three_dnow_prefetch: bool,
    osvw: bool,
    ibs: bool,
    xop: bool,
    skinit: bool,
    wdt: bool,
    _reserved_14: u1 = 0,
    lwp: bool,
    fma4: bool,
    tce: bool,
    _reserved_18: u4 = 0,
    topoext: bool,
    perfctr_core: bool,
    perfctr_nb: bool,
    _reserved_25: u7 = 0,

    pub fn hasReserved(self: ExtendedFeatureEcx) bool;
};
```

### Feature bundles

```zig
pub const BasicFeatures = struct {
    edx: BasicFeatureEdx,
    ecx: BasicFeatureEcx,
};

pub const StructuredFeatures = struct {
    ebx: StructuredEbx,
    ecx: StructuredEcx,
    edx: StructuredEdx,
};

pub const ExtendedFeatures = struct {
    edx: ExtendedFeatureEdx,
    ecx: ExtendedFeatureEcx,
};

pub const Features = struct {
    basic: BasicFeatures,
    structured: StructuredFeatures,
    extended: ExtendedFeatures,
};

pub fn basicFeatures() BasicFeatures;
pub fn structuredFeatures() StructuredFeatures;
pub fn extendedFeatures() ExtendedFeatures;
pub fn features() Features;
```

### Cache topology

```zig
pub const cache = struct {
    pub const Kind = enum(u5) {
        null = 0,
        data = 1,
        instruction = 2,
        unified = 3,
        _,
    };

    pub const Descriptor = struct {
        level: u3,
        kind: Kind,
        line_size: u32,
        partitions: u32,
        ways: u32,
        sets: u32,
        fully_associative: bool,
        self_initializing: bool,
        eax: u32,
        ebx: u32,
        ecx: u32,
        edx: u32,
    };

    pub const Iterator = struct {
        index: u32,

        pub fn next(self: *Iterator) ?Descriptor;
    };
};

pub fn caches() cache.Iterator;
```

### Address sizes

```zig
pub const AddressSizes = struct {
    physical_bits: u8,
    linear_bits: u8,
    guest_physical_bits: u8,
};

pub fn addressSizes() AddressSizes;
```

## Semantics

### Vendor identification

`vendor()` executes `cpuid` with leaf 0, packs
`EBX:EDX:ECX` into 12 bytes, matches the ASCII against the canonical
strings from Intel SDM Vol.2 Appendix A and AMD APM Vol.3 Appendix E,
and returns the corresponding `Vendor` enum. Unrecognized strings map
to `.unknown`.

`vendorString()` returns those same 12 bytes without matching, so
callers who need to distinguish beyond the enum have the raw string.
Byte layout is EBX (bytes 0..3), EDX (4..7), ECX (8..11). Missing bytes
(if the CPU somehow returns fewer than 12 usable bytes) are `0`.

### Version decoding

`version()` executes `cpuid` with leaf 1 and returns:

- `family` = displayed family per Intel SDM: `base_family + extended_family`
  when `base_family == 0xF`, otherwise `base_family`;
- `model` = displayed model: `(extended_model << 4) | base_model` when
  `base_family == 0x6` or `base_family == 0xF`, otherwise `base_model`;
- `stepping` = `EAX[3:0]`;
- `eax` = the raw `EAX` value returned by `cpuid`, for callers who need
  the type bits (`EAX[13:12]`) or processor-signature reconstruction.

`family`, `model`, `stepping` follow AMD APM Vol.3 §CPUID Fn0000_0001_EAX
when `vendor() == .amd`.

### Feature masks

Every feature mask is a `packed struct(u32)`. Named bits use the
lowercase-underscore transformation of the canonical mnemonic from
Intel SDM Vol.2 Chapter 3 or AMD APM Vol.3 Appendix E; where the two
vendors document different names for the same bit, the Intel SDM name
is used and the AMD name is called out in code comments in the
implementation.

Field naming rules:

- SSE variants use their exact mnemonic: `sse`, `sse2`, `ssse3`,
  `sse4_1`, `sse4_2`, `sse4a`;
- Multi-character prefixes (`avx512_`, `amx_`, `ia32_`) preserve the
  underscore separator;
- Bit ranges wider than one bit that carry integer semantics (e.g.,
  `StructuredEcx.mawau`) use `uK` field types;
- Reserved single-bit positions become `_reserved_N: u1 = 0`;
- Consecutive reserved bit ranges collapse into one `_reserved_N: uK = 0`;
- Position-index in every reserved-field name matches the low bit of
  the reserved range (so `_reserved_18: u4` occupies bits 18..21).

`@bitCast(u32, mask)` round-trips every bit including reserved
positions. `@bitCast(BasicFeatureEdx, u32_value)` reconstructs the mask.

`hasReserved()` returns `true` if any reserved bit in the mask is set
to `1`. Implementation is a comptime-generated OR over every reserved
field.

Bits that are reserved when this specification is published remain reserved fields. `hasReserved()` reports any set reserved bit. A later specification revision that names such a bit changes `hasReserved()` for that bit.

### Feature fetch

`basicFeatures()` executes `cpuid` with leaf 1, `@bitCast`s
`ECX`/`EDX` into the typed structs, and returns them in a `BasicFeatures`
bundle. It performs no leaf-1 support check; leaf 1 is present on every
x86_64 CPU by construction.

`structuredFeatures()` first executes `cpuid` with leaf 0 to fetch
`maxBasicLeaf()`. If `maxBasicLeaf() < 7`, it returns a
`StructuredFeatures` with all fields zeroed. Otherwise it executes
`cpuid` with leaf 7 subleaf 0 and `@bitCast`s `EBX`/`ECX`/`EDX` into the
typed structs.

`extendedFeatures()` first checks `maxExtendedLeaf() >= 0x80000001`. If
false, returns an `ExtendedFeatures` with all fields zeroed. Otherwise
executes `cpuid` with leaf `0x80000001` and `@bitCast`s `EDX`/`ECX`.

`features()` calls all three above and returns the `Features` bundle.
It executes at most one `cpuid` for `maxBasicLeaf`, one for
`maxExtendedLeaf`, one for leaf 1, one for leaf 7 subleaf 0, and one
for leaf `0x80000001`.

### Cache topology

`caches()` returns an iterator that walks leaf 4 (Intel deterministic-
cache) subleaves starting at subleaf 0. Each `Iterator.next()` executes
`cpuid` with leaf 4 and the current subleaf index, then:

- if the low 5 bits of `EAX` (the cache type field) equal `0` → returns
  `null`, sequence complete;
- otherwise decodes and returns a `Descriptor`, then increments the
  subleaf index.

`Descriptor` fields:

- `level` = `EAX[7:5]`;
- `kind` = `EAX[4:0]` cast to `cache.Kind` (open enum, so values 4..31
  reserved by Intel are preserved via `_`);
- `line_size` = `(EBX[11:0]) + 1`;
- `partitions` = `(EBX[21:12]) + 1`;
- `ways` = `(EBX[31:22]) + 1`;
- `sets` = `ECX + 1`;
- `fully_associative` = `(EAX[9]) == 1`;
- `self_initializing` = `(EAX[8]) == 1`;
- `eax`, `ebx`, `ecx`, `edx` = raw register values returned by `cpuid`.

`caches()` returns populated leaf-4 descriptors without vendor-specific interpretation. Callers that require vendor-specific fields use `cpuid.leaf` or `cpuid.subleaf`.

On a CPU where `maxBasicLeaf() < 4`, the iterator's first `next()`
returns `null`.

### Brand string

`brandString()` first checks `maxExtendedLeaf() >= 0x80000004`. If
false, returns `null`. Otherwise executes `cpuid` with leaves
`0x80000002`, `0x80000003`, `0x80000004` and concatenates the twelve
returned 32-bit registers into a 48-byte array. The Intel-standard
byte layout is EAX/EBX/ECX/EDX in that order per leaf.

The returned bytes are the raw string; padding is `0`.

### Address sizes

`addressSizes()` first checks `maxExtendedLeaf() >= 0x80000008`. If
false, returns `AddressSizes{ .physical_bits = 32, .linear_bits = 32,
.guest_physical_bits = 0 }` as a documented fallback that matches the
default 32-bit x86 assumption.

Otherwise executes `cpuid` with leaf `0x80000008` and returns:

- `physical_bits` = `EAX[7:0]`;
- `linear_bits` = `EAX[15:8]`;
- `guest_physical_bits` = `EAX[23:16]`, which is `0` on Intel CPUs and
  the guest-physical width on AMD SVM-capable CPUs.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `vendor` | never | never | O(1) | reentrant | none | infallible |
| `vendorString` | never | never | O(1) | reentrant | none | infallible |
| `version` | never | never | O(1) | reentrant | none | infallible |
| `brandString` | never | never | O(1) | reentrant | none | returns null when leaves absent |
| `basicFeatures` | never | never | O(1) | reentrant | none | infallible |
| `structuredFeatures` | never | never | O(1) | reentrant | none | infallible; zero when leaf 7 absent |
| `extendedFeatures` | never | never | O(1) | reentrant | none | infallible; zero when leaf 0x80000001 absent |
| `features` | never | never | O(1) | reentrant | none | infallible |
| `caches` + `Iterator.next` | never | never | O(subleaves) total, O(1) per step | reentrant | none | infallible |
| `addressSizes` | never | never | O(1) | reentrant | none | infallible; falls back when leaf 0x80000008 absent |
| `hasReserved` on any mask | never | never | O(1) | value type | none | infallible |

Every operation is a fixed sequence of `cpuid` instructions plus bit
math. No allocation, no lock, no syscall, no target probing beyond
`maxBasicLeaf`/`maxExtendedLeaf`.

`cpuid` is unprivileged and available at any CPL. Every operation is
safe from any execution context including NMI.

## Ordering contract

`cpuid.leaf` and `cpuid.subleaf` execute the instruction with register clobbers only. Decoders inherit that contract. No CPUID operation uses a `memory` clobber; the operations are pure reads of CPU-provided immediate values.

## Testing

Compile-time representation tests MUST verify that every feature mask is a 4-byte `packed struct(u32)`, that zero bit-casts round trip, that feature-bundle sizes match their declared layouts, that every mask has `hasReserved`, and that the documented enum layouts remain exact. Model tests MUST inject raw `Result` values to verify feature-bit decoding and that a set reserved bit causes `hasReserved()` to return `true`. Host-safe runtime tests on x86_64 MUST verify vendor and version decoding, consistency between `features()` and individual accessors, cache-descriptor presence and line size, printable non-null brand strings when provided, and physical-address widths in the documented range. Non-x86_64 compile tests MUST verify use-site target gating. These tests prove raw-register decoding, fallback behavior, ABI layout, and instruction gating without relying on a particular consumer or privileged context.
