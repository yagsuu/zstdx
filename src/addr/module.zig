//! Address primitives. See `docs/specs/addr/address.md` and
//! `docs/specs/addr/pages.md`.

pub const address = @import("address.zig");
pub const pages = @import("pages.zig");

pub const Address = address.Address;
pub const PhysAddr = address.PhysAddr;
pub const VirtAddr = address.VirtAddr;
pub const DmaAddr = address.DmaAddr;
pub const Page = pages.Page;
pub const cast = address.cast;
pub const castAligned = address.castAligned;

test {
    _ = address.unit;
    _ = pages.unit;
}
