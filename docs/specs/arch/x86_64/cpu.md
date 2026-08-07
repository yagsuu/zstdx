# x86_64 CPU instructions

Status: Approved.

`stdx.arch.x86_64.cpu` owns small x86_64 CPU instruction wrappers that are not raw register access and not VMX/SVM/paging formats. The namespace covers CPU one-shots, timestamp-counter reads, and local TLB invalidation instructions.

The wrappers expose ISA behavior only. They do not calibrate clocks, schedule, handle traps, allocate ASIDs/PCIDs, broadcast shootdowns, or recover from exceptions.

## Owned scope

This spec owns:

- `stdx.arch.x86_64.cpu`;
- `cpu.halt`, `cpu.pause`, and `cpu.breakpoint`;
- `cpu.tsc.read`, `cpu.tsc.readSerializing`, and `cpu.tsc.Reading`;
- `cpu.tlb.invalidatePage`;
- `cpu.tlb.invalidatePcid`, `cpu.tlb.InvpcidKind`, and `cpu.tlb.InvpcidDescriptor`;
- target gating, ordering, trap behavior, and required tests.

## Deferred scope and non-goals

This spec does not own:

- CPUID feature detection for `rdtscp` or `invpcid`;
- TSC frequency calibration, deadline timers, monotonic clocks, or cross-core synchronization;
- trap handlers for `#BP`, `#GP`, `#UD`, or page faults;
- TLB shootdown across CPUs;
- PCID allocation or lifetime;
- page-table mutation or paging structure formats;
- VMX/SVM invalidation instructions such as `invept`, `invvpid`, or `invlpga`;

## Public namespace

```zig
stdx.arch.x86_64.cpu
stdx.arch.x86_64.cpu.halt
stdx.arch.x86_64.cpu.pause
stdx.arch.x86_64.cpu.breakpoint
stdx.arch.x86_64.cpu.tsc
stdx.arch.x86_64.cpu.tsc.Reading
stdx.arch.x86_64.cpu.tsc.read
stdx.arch.x86_64.cpu.tsc.readSerializing
stdx.arch.x86_64.cpu.tlb
stdx.arch.x86_64.cpu.tlb.InvpcidKind
stdx.arch.x86_64.cpu.tlb.InvpcidDescriptor
stdx.arch.x86_64.cpu.tlb.invalidatePage
stdx.arch.x86_64.cpu.tlb.invalidatePcid
```

## Source ownership

```text
src/arch/x86_64.zig
src/arch/x86_64/cpu.zig
test/arch/x86_64_cpu_test.zig
```

`src/arch/x86_64.zig` re-exports:

```zig
pub const cpu = @import("x86_64/cpu.zig");
```

## Target gating

The module may be imported on any target. Operations that emit x86_64 inline assembly produce a compile error when referenced on non-x86_64 targets. Layout-only declarations such as `tlb.InvpcidDescriptor`, `tlb.InvpcidKind`, and `tsc.Reading` compile on every target.

## API

```zig
pub fn halt() void;
pub fn pause() void;
pub fn breakpoint() void;

pub const tsc = struct {
    pub const Reading = struct {
        tsc: u64,
        aux: u32,
    };

    pub fn read() u64;
    pub fn readSerializing() Reading;
};

pub const tlb = struct {
    pub const InvpcidKind = enum(u2) {
        individual_address = 0,
        single_context = 1,
        all_including_globals = 2,
        all_excluding_globals = 3,
    };

    pub const InvpcidDescriptor = extern struct {
        pcid: u16 align(16),
        _reserved_pcid_high: u16 = 0,
        _reserved: u32 = 0,
        linear_address: u64,

        pub const alignment: usize = 16;
    };

    pub fn invalidatePage(addr: usize) void;
    pub fn invalidatePcid(kind: InvpcidKind, descriptor: *const InvpcidDescriptor) void;
};
```

## Semantics

`halt` executes `hlt`. It is privileged; the CPU halts until the next enabled external interrupt, NMI, SMI, INIT, or other architecturally defined wake event.

`pause` executes `pause`. It is unprivileged and is intended for spin-wait loops.

`breakpoint` executes `int3`. It is unprivileged and raises `#BP`; installed exception handling is caller policy.

`tsc.read` executes `rdtsc` and returns `EDX:EAX` as `u64`. It is not serializing.

`tsc.readSerializing` executes `rdtscp`, returns `EDX:EAX` as `Reading.tsc`, and returns `ECX` as `Reading.aux`. `rdtscp` is partially serializing according to the CPU architecture; the wrapper adds no extra fences.

`tlb.invalidatePage(addr)` executes `invlpg [addr]`. The address names a linear address whose translation should be invalidated on the current logical processor. Cross-CPU invalidation is caller policy.

`tlb.invalidatePcid(kind, descriptor)` executes `invpcid`. The descriptor is the 16-byte memory operand required by the instruction. `kind` values match the architectural type field:

| Kind | Value | Meaning |
| --- | ---: | --- |
| `.individual_address` | 0 | Invalidate one linear address for one PCID. |
| `.single_context` | 1 | Invalidate one PCID context, excluding globals. |
| `.all_including_globals` | 2 | Invalidate all PCIDs, including globals. |
| `.all_excluding_globals` | 3 | Invalidate all PCIDs, excluding globals. |

`InvpcidDescriptor` is exactly 16 bytes, aligned to 16, with `pcid` at offset 0 and `linear_address` at offset 8. Reserved fields default to zero.

## Behavior contract

| Operation | Allocation | Waiting | Bounds | Concurrency | Ordering | Errors |
| --- | --- | --- | --- | --- | --- | --- |
| `halt` | never | halts CPU until wake event | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `pause` | never | CPU pause hint only | O(1) | reentrant | memory clobber | infallible |
| `breakpoint` | never | never | O(1) | reentrant | memory clobber | infallible; raises `#BP` |
| `tsc.read` | never | never | O(1) | reentrant | register clobbers only | infallible; may `#GP` |
| `tsc.readSerializing` | never | never | O(1) | reentrant | partial serialization | infallible; may `#GP`/`#UD` |
| `tlb.invalidatePage` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP` |
| `tlb.invalidatePcid` | never | never | O(1) | reentrant | full memory clobber | infallible; may `#GP`/`#UD` |

## Ordering contract

`pause`, `breakpoint`, and `halt` use a memory clobber to prevent compiler reordering around the inline assembly.

`tsc.read` uses register clobbers on `eax` and `edx`; it is not serializing and has no memory clobber.

`tsc.readSerializing` uses register clobbers on `eax`, `ecx`, and `edx`; architectural partial serialization belongs to `rdtscp`, not the wrapper.

`tlb.invalidatePage` and `tlb.invalidatePcid` use memory clobbers so the compiler does not reorder adjacent paging-structure writes across invalidation.

## Trap and privilege behavior

- `halt`: `#GP` when called outside the privilege conditions required by the CPU.
- `breakpoint`: raises `#BP` by design.
- `tsc.read`: `#GP` at CPL > 0 when `registers.cr4.CR4.time_stamp_disable` is set.
- `tsc.readSerializing`: `#GP` at CPL > 0 when TSD is set; `#UD` when `RDTSCP` is unsupported.
- `tlb.invalidatePage`: `#GP` at CPL > 0.
- `tlb.invalidatePcid`: `#GP` at CPL > 0; `#UD` when `INVPCID` is unsupported.

Trap recovery is caller policy.

## Testing

Compile-time tests MUST instantiate every assembly wrapper on x86_64 and verify that importing the module on a non-x86_64 target does not emit inline assembly until a gated operation is referenced. Layout tests MUST verify the 16-byte size, 16-byte alignment, and documented field offsets of `tlb.InvpcidDescriptor`; enum tests MUST verify the four `InvpcidKind` values; and type tests MUST verify the `tsc.Reading` field types. Host-safe runtime tests on supported hosts MUST execute `pause` and, where TSD permits userspace reads, verify that `tsc.read` returns a value. These tests prove the portable ABI, target-gating boundary, and unprivileged executable subset without executing privileged invalidation instructions.
