# `x86_64.svm`

[`stdx.arch.x86_64.svm`](../../../../src/arch/x86_64/svm.zig) provides AMD
SVM instruction wrappers and the VMCB region layout. Here, `svm` denotes
that namespace. Addresses use shared `addr.PhysAddr` and `addr.VirtAddr` types.

Value types compile on any target. Instruction wrappers require an x86_64
target when referenced.

## Processor setup and storage

Callers must detect SVM support through `CPUID.8000_0001:ECX[2]`,
satisfy firmware and `VM_CR` restrictions, and set `EFER.SVME` before
`svm.vmrun()`, `svm.vmload()`, `svm.vmsave()`, `svm.stgi()`, `svm.clgi()`,
or `svm.invlpga()`. All wrappers require CPL 0. Check separate SKINIT support
through `CPUID.8000_0001:ECX[12]` before `svm.skinit()`.

Before `svm.vmrun()`, program `VM_HSAVE_PA` (`0xC001_0117`) on the executing
logical processor with the physical address of a caller-owned, 4-KiB-aligned
host save page. Keep that page physically stable and available while the
processor uses it. Its contents are processor-defined.

`VMCB` is a 4096-byte, 4096-byte-aligned `extern struct`:

| Offset | Field | Size |
| --- | --- | --- |
| `0x000` | `control` | 1024 bytes |
| `0x400` | `save` | 3072 bytes |

Neither field has a default initializer. Callers initialize the control
and state-save fields according to the processor's supported SVM features.
Typed overlays must preserve the architectural offsets and reserved bits.
VMCB addresses passed to `svm.vmrun()`, `svm.vmload()`, or `svm.vmsave()`
must be 4-KiB aligned with bits 63:MAXPHYADDR clear. These operations take
`addr.PhysAddr` by value in RAX.

Keep each VMCB physically stable and available while an instruction or guest
execution can use it. Callers serialize access to a VMCB and its associated
guest state. Processor-local host save state, GIF, ASIDs, and cached VMCB
state require a caller-controlled processor-affinity and migration protocol.
Before migration or ASID reuse, establish valid destination host state and
perform the required TLB invalidation and VMCB clean-bit management.

## Guest execution and state transfer

`svm.vmrun(vmcb)` enters the guest described by the VMCB. Callers configure
valid intercepts, guest state, ASID, and optional nested paging before entry.
On VMEXIT, the CPU records exit information and guest state in the VMCB,
restores the architectural host-state subset from the host save area,
and resumes after `VMRUN`. Guest execution has no bounded duration.

Callers MUST provide entry/exit assembly that preserves compiler-live
registers. Callers manage guest GPR/SIMD state.

`svm.vmload(vmcb)` loads additional state from the VMCB save area.
`svm.vmsave(vmcb)` saves the same subset:

- FS, GS, TR, and LDTR segment state
- KernelGSBase
- STAR, LSTAR, CSTAR, and SFMASK
- SYSENTER_CS, SYSENTER_ESP, and SYSENTER_EIP

Callers preserve and restore the host's additional state when switching this
subset for guest execution.

Invalid guest control or state combinations can produce an invalid-state
VMEXIT. After `svm.vmrun()`, callers inspect VMCB exit information.

## Interrupt state

`svm.clgi()` clears the executing processor's global interrupt flag (GIF).
`svm.stgi()` sets it. GIF controls interrupt delivery separately from
`RFLAGS.IF`. Callers manage GIF around host/guest state transitions and
restore the required host interrupt state. VMRUN and VMEXIT also change GIF
according to SVM rules.

## Translation invalidation

`svm.invlpga(address, asid)` takes an `addr.VirtAddr` and a `u32` ASID.
It invalidates the architecturally specified translations for that linear
address and ASID on the issuing logical processor.
Callers use ASIDs within the processor's supported range and manage
allocation and reuse.

Order page-table changes before invalidation. Perform the required
invalidation on every affected logical processor before using changed
mappings or reusing translation resources. Use the VMCB's architectural
TLB-control mechanism when the required invalidation scope exceeds
`svm.invlpga()`, including applicable nested-paging changes.

## Secure launch

`svm.skinit(address)` takes a `u32` physical address. The secure loader image
must start at a 64-KiB-aligned physical address below 4 GiB and satisfy
the architectural secure-launch image and platform requirements.
Callers establish the required processor, interrupt, memory, and platform
state before launch.

SKINIT measures the secure loader and transfers control to its architectural
entry point within the loader block. The wrapper returns `noreturn`.

## Faults and ordering

Callers handle CPU exceptions, including `#UD` for unavailable instructions
or disabled SVM where required and `#GP` for privilege or operand violations.

Every wrapper has a compiler memory clobber and adds no hardware fence.
CPU-written VMCB state is available to subsequent host loads after VMEXIT.
Callers provide architectural ordering, DMA synchronization, and
cross-processor synchronization.

## References

- [x86_64 base contract](../x86_64.md)
- [CPUID contract](cpuid.md)
- AMD64 Architecture Programmer's Manual, Volume 2: SVM instruction
  reference, VMCB layout, host and guest state transitions, TLB control,
  and secure initialization.
