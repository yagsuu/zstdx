//! Address primitives. See `docs/specs/addr/address.md` and
//! `docs/specs/addr/pages.md`.

pub const address = @import("addr/address.zig");
pub const pages = @import("addr/pages.zig");

pub const Address = address.Address;
pub const PhysAddr = address.PhysAddr;
pub const VirtAddr = address.VirtAddr;
pub const DMAAddr = address.DMAAddr;
pub const Page = pages.Page;
