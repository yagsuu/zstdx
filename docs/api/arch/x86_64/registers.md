# `arch.x86_64.registers`

`registers` provides typed register values, direct hardware access, and decoding
of paging controls.

## Values and field updates

Bit-field namespaces, including `registers.CR0`, `registers.CR3`,
`registers.RFLAGS`, and selector namespaces, operate on generated packed `Word`
values. Operations use namespace syntax, for example
`registers.CR3.base(word, width)`.

Field layouts:
[control](../../../../src/arch/x86_64/register/control.zig),
[flags](../../../../src/arch/x86_64/register/rflags.zig),
[EFER](../../../../src/arch/x86_64/register/efer.zig),
[segment](../../../../src/arch/x86_64/register/segment.zig),
[descriptor](../../../../src/arch/x86_64/register/descriptor.zig),
[debug](../../../../src/arch/x86_64/register/debug.zig).

For a bit-field namespace `R`:

| Operation | Contract |
| --- | --- |
| `R.from()` / `R.raw()` | Preserve every bit. |
| `R.default()` / `R.init()` / `R.encode()` | Use schema defaults for omitted inputs. Reserved fields are excluded from construction inputs. |
| `R.replace()` | Changes selected assignable fields. Preserves read-only, reserved, unnamed, and unselected bits. |
| `R.mask()` / `R.masks` | Select named ranges or classify access and write policies, including unnamed positions. |

Defaults are zero except `registers.CR0.extension_type`, `registers.XCR0.x87`,
`registers.RFLAGS.fixed_one`, and `registers.DR7.fixed_one`, which default to one.

Raw address registers use distinct open 64-bit enum values. Their value
operations preserve raw bits and their initial values are zero.

Hardware writes use the full supplied raw operand. Callers MUST satisfy reserved-bit,
feature-enable, address, and cross-register transition requirements.

## Paging controls

`registers.CR3.base(word, width)` returns the 4 KiB-aligned physical address
`page_index << 12`. Errors have this precedence:

1. `InvalidPhysicalAddressWidth` when `width` is outside 32 through 52 inclusive.
2. `ReservedBits` when bits 60:52 are nonzero.
3. `PhysicalAddressTooWide` when the address uses a bit at or above `width`.

`registers.CR3.low(word, pcide)` returns the 12-bit `.pcid` when PCIDE is enabled.
Otherwise only bits 3 (write-through) and 4 (cache-disable) may be set.
Other low bits return `ReservedLowBits`. Valid cache controls return `.cache`.

`registers.CR3.userLam(word, supported)` returns `.u57` when `lam_u57` is set,
including when both LAM fields are set. Otherwise it returns `.u48` when
`lam_u48` is set, or `.disabled`. An enabled mode without support returns
`UnsupportedLAM`.

`no_flush` is a CR3 write-operand qualifier. Callers interpreting stored CR3
state MUST reject a set `no_flush`. Before `registers.CR3.write()`, callers MUST
enforce PCID and paging-transition requirements. A write can invalidate TLB
entries.

`registers.CR4.pcidEnabled()` and `registers.CR4.level5Enabled()` return the
decoded control, or `UnsupportedPCID` and `UnsupportedFiveLevelPaging`,
respectively, when an enabled control lacks caller-supplied support.
`registers.CR4.supervisorLam()` returns `.disabled` when `lam_supervisor` is clear.
Otherwise it requires LAM support and returns `.u57` with LA57 enabled or `.u48`
with LA57 clear. Absent support returns `UnsupportedLAM`.

`registers.EFER.executeDisableEnabled()` returns the NXE control, or
`UnsupportedExecuteDisable` when NXE is enabled without caller-supplied support.

## Hardware access and ordering

Value operations are available on every target. Hardware access requires
x86_64 at compile time. Callers MUST provide required CPU capabilities and
execution privilege. Hardware exceptions propagate to the caller's handlers.

All writes and `registers.GsBase.swap()` have compiler memory barriers.
`registers.GDTR.read()` and `registers.IDTR.read()` also have compiler memory
barriers. Other reads do not. Architectural ordering remains instruction-specific.
`registers.RFLAGS.write()` additionally clobbers condition codes.

| Access | Requirements and effects |
| --- | --- |
| CR0, CR2, CR3, CR4, CR8 reads and writes | CPL 0. Invalid privilege or operands can raise `#GP`. |
| `registers.XCR0.read()` / `registers.XCR0.write()` | XSAVE and `CR4.OSXSAVE`. Writes require CPL 0 and supported state-bit combinations. Missing enablement can raise `#UD`. Invalid writes can raise `#GP`. |
| `registers.EFER.read()` / `registers.EFER.write()` | CPL 0. Invalid access or operands can raise `#GP`. |
| `registers.RFLAGS.write()` | Bits that the current CPL cannot modify remain unchanged. Architectural restrictions apply. |
| Segment-selector writes | Valid selectors and descriptors for the segment and privilege level. Faults include `#GP`, `#NP`, and `#SS`. |
| `registers.FsBase` / `registers.GsBase` reads and writes | FSGSBASE and `CR4.FSGSBASE` or `#UD`. Non-canonical writes can raise `#GP`. |
| `registers.GsBase.swap()` | CPL 0. Exchanges GS base with `IA32_KERNEL_GS_BASE`. |
| GDTR, IDTR, TR, LDTR reads | CPL 0 when `CR4.UMIP` is set or `#GP`. |
| GDTR, IDTR, TR, LDTR writes | CPL 0 and valid table or descriptor operands. Descriptor loads can fault. |
| Debug-register reads and writes | CPL 0. Invalid privilege or operands can raise `#GP`. General-detect state can raise `#DB`. |

`registers.CS.writeFarReturn()` reloads CS through a far return to the wrapper's
continuation. The caller MUST supply a valid code selector for that return and
a usable stack. Other segment-selector writes use `MOV`.

## Descriptor registers

Selectors use 16-bit packed words.
Each selector register has a distinct `Word` type.
`registers.TR` and `registers.LDTR` use `STR` / `LTR` and `SLDT` / `LLDT`.

`registers.GDTR` and `registers.IDTR` are distinct 10-byte extern structs with
alignment 2, a 16-bit `limit` at offset 0, and a 64-bit `base` at offset 2.
Their initial values are zero. Writes borrow a pointer to the matching type.
The operand is needed only during the instruction. The caller MUST keep the
referenced descriptor table valid while the CPU can use that table.

## Debug values

`registers.DR4` aliases DR6 and `registers.DR5` aliases DR7 when `CR4.DE` is
clear. Access raises `#UD` when `CR4.DE` is set.

`registers.DR6.read()` returns `registers.DebugStatus.Word`.
Status bits retain raw polarity, including `bus_lock_not_detected`
and `outside_rtm`. Multiple cause bits can be set together.
Use a raw status operand for `registers.DR6.write()`. Field replacement treats
named status bits as read-only.

`registers.DR7.Word` contains four `registers.Breakpoint.Word` values.
Breakpoint lengths retain their raw architectural encoding. Callers MUST select
supported condition and length combinations and correctly aligned breakpoint
addresses before writing DR7.

## References

- [Register exports](../../../../src/arch/x86_64/registers.zig)
- [x86_64 requirements](../x86_64.md)
