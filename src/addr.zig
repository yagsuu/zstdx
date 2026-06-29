//! Address primitives. See docs/specs/addr/address.md.

pub const address = @import("addr/address.zig");

pub const Address = address.Address;
pub const PhysAddr = address.PhysAddr;
pub const VirtAddr = address.VirtAddr;
