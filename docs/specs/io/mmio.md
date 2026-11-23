# `stdx.io.Mmio`

`Mmio` provides volatile register access through inline register overlays,
standalone references, and borrowed byte windows.

## Values and access width

`Mmio.Register(T)`, `Mmio.Ref(T)`, and `Mmio.RefMut(T)` accept `u8`, `u16`,
`u32`, `u64`, [endian wrappers](../layout/endian.md) over those integers, and
packed structs backed by those integers. Other types fail at compile time.

Each load/store is one Zig volatile access of the backing integer's width and
alignment. Device-bus transaction behavior depends on the target.

Loads return `T` and stores accept `T`. Endian wrappers retain their device-byte
representation; use their conversion methods for native values. Packed values
use Zig's packed representation.

`Mmio.Register(T)` is an extern struct containing the backing integer as `value`.
Its size and alignment equal those of that integer. `Register.Value` is `T`,
`Register.Int` is the backing integer, and `Register.size` is its byte size.
`Register.load()` accepts a const volatile pointer; `Register.store()` requires
a mutable volatile pointer.

## References and windows

`Mmio.Ref(T).from(address)` and `Mmio.RefMut(T).from(address)` borrow a
`VirtAddr`, returning `error.Misaligned` unless it satisfies backing-integer
alignment. `Ref.load()` is read-only; `RefMut.load()` and `RefMut.store()` permit
both operations. Construction does not access the device.

`Mmio.Window.from(bytes)` borrows `[]volatile u8` without accessing it. Copies of
windows and references alias the same mapping.

| Window operation | Result |
| --- | --- |
| `Window.reg(T, offset)` | Read-only `Ref(T)` at the byte offset. |
| `Window.regMut(T, offset)` | Mutable `RefMut(T)` at the byte offset. |
| `Window.field(Layout, name)` | Read-only reference at the named field's overlay offset. |
| `Window.fieldMut(Layout, name)` | Mutable reference at the same offset. |

Register selection returns `error.OutOfBounds` if the lane does not fit entirely
inside the window, including extreme offsets. Bounds errors precede alignment
errors. An in-bounds lane returns `error.Misaligned` unless its actual address
satisfies backing-integer alignment. The window base need not itself have that
alignment.

Field selection requires an extern struct `Layout` with a named
`Mmio.Register(T)` field. The overlay starts at the window base; only the selected
field must fit in the window. Field selection applies the same bounds and
alignment rules as register selection. Selection failures leave the window and
mapped memory unchanged.

## Device requirements and ordering

The caller MUST keep the mapping valid and accessible for each full-width access,
with suitable device-memory attributes and read or write permission. Standalone
references also require a mapped extent large enough for the lane. The caller
MUST choose a width, representation, and operation allowed by the device.

Callers MUST handle device read/write side effects, reserved bits, and update rules,
serialize conflicting accesses, and supply required [MMIO barriers](../barrier/dma.md).
Reference construction and selection perform no register access, allocation, or waiting.

## References

- [MMIO declarations](../../../src/io/mmio.zig)
