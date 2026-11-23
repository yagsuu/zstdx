# `arch.x86_64.cpu`

`cpu` provides instruction wrappers for CPU control, timestamp reads, and local
TLB invalidation.

## Execution requirements

The module and value types can be used on any target. Instruction operations
require an x86_64 target at compile time. Callers MUST satisfy the instruction's
CPU feature, privilege, and operand requirements and handle CPU exceptions.

These operations have compiler memory barriers:

| Operation | Execution |
| --- | --- |
| `cpu.halt()` | CPL 0. Executes `HLT` and waits for an architectural wake event. Invalid privilege raises `#GP`. |
| `cpu.pause()` | Unprivileged spin-wait hint. |
| `cpu.breakpoint()` | Executes `INT3` and raises `#BP`. |

## Timestamp counter

Neither timestamp wrapper has a compiler memory barrier.

| Operation | Result and hardware ordering |
| --- | --- |
| `cpu.Tsc.read()` | Requires RDTSC support. Returns the `u64` counter from `EDX:EAX` without serialization. |
| `cpu.Tsc.readAux()` | Requires RDTSCP support. Returns the counter and `IA32_TSC_AUX` from ECX. Waits for prior instruction completion and prior-load visibility. |

For `cpu.Tsc.readAux()`, provide fences for prior-store visibility or
subsequent-instruction ordering.
Both reads require CPL 0 when `CR4.TSD` is set. Violation raises `#GP`.
An unsupported RDTSCP raises `#UD`. Callers control any additional ordering,
TSC calibration, and interpretation across logical processors.

## Local TLB invalidation

Both `cpu.Tlb` operations require CPL 0 and have compiler memory barriers.
They affect the current logical processor. Callers coordinate page-table
updates and remote TLB shootdowns.

`cpu.Tlb.invalidatePage(address)` executes `INVLPG` for the supplied `addr.VirtAddr`.
An invalid privilege level raises `#GP`.

`cpu.Tlb.invalidate(scope, descriptor)` executes `INVPCID` and requires INVPCID
support. The caller MUST provide a readable descriptor with zero reserved bits.
For `.address` and `.context`, the PCID MUST be zero when `CR4.PCIDE` is clear.
For `.address`, the linear address MUST be canonical.
Unsupported execution raises `#UD`. Privilege and operand violations can raise
`#GP`.

| `cpu.Tlb.Scope` | Encoding | Invalidation |
| --- | ---: | --- |
| `.address` | 0 | One address for one PCID, excluding global translations. |
| `.context` | 1 | One PCID context, excluding global translations. |
| `.all` | 2 | All PCIDs, including global translations. |
| `.all_non_global` | 3 | All PCIDs, excluding global translations. |

[`cpu.Tlb.Descriptor`](../../../../src/arch/x86_64/cpu.zig) is a 16-byte
extern struct with alignment 8. Its context defaults to zero.
The descriptor is borrowed only for the instruction.

## References

- [CPU operations](../../../../src/arch/x86_64/cpu.zig)
- [x86_64 requirements](../x86_64.md)
