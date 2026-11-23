# `x86_64.vmx`

[`stdx.arch.x86_64.vmx`](../../../../src/arch/x86_64/vmx.zig) provides Intel
VMX instruction wrappers and hardware region layouts. Here, `vmx` denotes
that namespace. Physical addresses use the shared `addr.PhysAddr` type.

Value types compile on any target. Instruction wrappers require an x86_64
target when referenced.

## Processor setup and ownership

Before `vmx.vmxon()`:

1. Detect VMX through `CPUID.1:ECX[5]` and satisfy the VMX capability MSRs.
2. Configure `IA32_FEATURE_CONTROL` for the applicable SMX mode, including its lock bit.
3. Satisfy CR0/CR4 fixed-bit requirements.
4. Set `CR4.VMXE`.

Use the memory type, physical-address width, and region requirements from
`IA32_VMX_BASIC`. All wrappers require CPL 0. Host-side operations after
`vmx.vmxon()` require VMX root operation.

VMX state belongs to the logical processor. Keep each operation sequence on
its owning processor. A VMCS must not be active on two logical processors
at once. Before migration, execute `vmx.vmclear()` on the old processor, then
load the VMCS on the new processor. Callers serialize access to each region.

Keep region storage physically stable and available while the processor
can use it. Keep the VMXON region until successful `vmx.vmxoff()`.
Clear a VMCS before reuse, release, or migration. Clear active VMCS regions
before leaving VMX operation when their state must remain usable.

## Region layouts

The [region declarations](../../../../src/arch/x86_64/vmx.zig) define
`Vmxon` and `VMCS` as 4096-byte `extern struct` types with 4096-byte
alignment. All fields default to zero.

Before use, set `header.revision_id` from `IA32_VMX_BASIC[30:0]`.
Keep `Vmxon.header._reserved_31` zero. Set `VMCS.header.shadow` only for
a shadow VMCS with the required hardware support and configuration.

The processor owns VMXON data during VMX operation. Callers MUST NOT modify
that data while it is in use. VMCS data has a processor-defined layout:
callers MUST NOT access it through ordinary loads or stores. Use `vmx.vmread()`
and `vmx.vmwrite()` for architectural VMCS fields. The CPU writes
`abort_indicator` on a VMX abort. Software can read it and clear it after
handling the abort under the architectural rules.

## Entering VMX operation and selecting a VMCS

`vmx.vmxon()`, `vmx.vmclear()`, and `vmx.vmptrld()` take a pointer to an
`addr.PhysAddr` value containing the region's physical address. Keep that
operand readable for the instruction. Region addresses must be 4-KiB
aligned and within the processor's supported VMX physical-address range.

| Operation | Successful effect |
| --- | --- |
| `vmx.vmxon()` | Enters VMX operation using the initialized `Vmxon` region |
| `vmx.vmxoff()` | Leaves VMX operation on the current logical processor |
| `vmx.vmclear()` | Writes back VMCS state as required, makes it inactive, and clears its launch state. Removes it as current if necessary. |
| `vmx.vmptrld()` | Makes the specified VMCS active and current on this logical processor |
| `vmx.vmptrst()` | Stores the current VMCS physical address through `*addr.PhysAddr`, or all 64 bits set when no VMCS is current |

Execute `vmx.vmclear()` before first use of a newly initialized VMCS.
`vmx.vmptrld()` preserves its launch state. `vmx.vmptrst()` returns `void`.
The other operations in this table return `Error!void`.

## VMCS fields and guest entry

`vmx.vmread()` and `vmx.vmwrite()` use raw `u32` VMCS field encodings.
The CPU zero-extends reads to `u64` and truncates `u64` writes of narrower
fields.

Configure the current VMCS controls, guest state, and host state before
entry. Control values must satisfy the applicable capability MSRs.
Configure `HOST_RIP` (`0x6C16`) and `HOST_RSP` (`0x6C14`) for a valid
host continuation. The caller supplies entry/exit assembly and preserves
register state needed by host code.

Use `vmx.vmlaunch()` for a VMCS in the clear launch state and
`vmx.vmresume()` for a VMCS in the launched state. Both functions return
`Error`. Only instruction-failure fallthrough returns to the Zig caller.
Successful entry transfers control to guest RIP. A subsequent VM exit
loads the configured host RIP/RSP, rather than returning through the
wrapper. VM-entry failures reported through the VM-exit path also use that
host continuation and must be decoded from VMCS exit information.

## Invalidation

`vmx.invept()` and `vmx.invvpid()` require support for the instruction and
selected scope in `IA32_VMX_EPT_VPID_CAP`. Both return `Error!void`.

[`Invept.Descriptor`](../../../../src/arch/x86_64/vmx.zig) is a 16-byte,
16-byte-aligned `extern struct`.
`Invept.Scope` is a closed `enum(u64)`:

| Scope | Value | Effect on the issuing logical processor |
| --- | --- | --- |
| `context` | 1 | Invalidates EPT-derived mappings associated with the EPT root identified by `eptp` |
| `all` | 2 | Invalidates EPT-derived mappings for all contexts |

For `context`, supply an architecturally valid EPTP. For `all`, EPTP is
ignored. Keep descriptor reserved bits zero in both cases.

[`Invvpid.Descriptor`](../../../../src/arch/x86_64/vmx.zig) is a 16-byte,
16-byte-aligned `extern struct`. Its address defaults to zero.
Keep reserved fields zero.
`Invvpid.Scope` is a closed `enum(u64)`:

| Scope | Value | Effect on the issuing logical processor |
| --- | --- | --- |
| `address` | 0 | Invalidates translations for `address` and `vpid`, including global translations |
| `context` | 1 | Invalidates translations for `vpid`, including global translations |
| `all` | 2 | Invalidates translations for all nonzero VPIDs, including global translations |
| `context_non_global` | 3 | Invalidates non-global translations for `vpid` |

`address` requires a canonical linear address. All scopes except `all`
require a nonzero VPID. Non-address scopes ignore `address`.
The `all` scope also ignores `vpid`. The architecture can invalidate more
translations than the minimum required by a scope.

Descriptors must remain readable for the instruction. Callers order
translation-table changes before invalidation and perform invalidation on
every affected logical processor before using changed mappings or reusing
translation resources or identifiers.

## Errors, faults, and ordering

Status-reporting wrappers map `RFLAGS` as follows:

| CF | ZF | Result |
| --- | --- | --- |
| 0 | 0 | Success |
| 1 | either | `error.VMfailInvalid` |
| 0 | 1 | `error.VMfailValid` |

`VMfailInvalid` reports instruction failure without a valid current-VMCS
error report. `VMfailValid` reports a VM-instruction error in the current
VMCS. Callers can read field `0x4400` with `vmx.vmread()`.

Callers handle architectural faults, including `#UD` for unavailable
instructions or invalid execution modes, `#GP` for privilege or setup
violations, and memory-operand faults. Unsupported invalidation scopes and
malformed descriptors follow the instruction's VMfail rules.

All wrappers have compiler memory clobbers and add no hardware fence.
Callers satisfy architectural ordering and cross-processor synchronization
requirements.

## References

- [x86_64 base contract](../x86_64.md)
- [CPUID contract](cpuid.md)
- Intel SDM, Volume 3: VMCS management, VMX operation, VM entry/exit,
  VMX instruction reference, and Appendix B VMCS field encodings.
