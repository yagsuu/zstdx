//! x86_64 paging data formats and read-only walker.
//! Spec: docs/specs/arch/x86_64/paging.md.

const address = @import("paging/address.zig");
const table = @import("paging/table.zig");

pub const walk = @import("paging/walk.zig");

pub const Mode = address.Mode;
pub const Level = table.Level;
pub const Index = table.Index;
pub const Indices = table.Indices;
pub const LinearAddress = address.LinearAddress;
pub const PhysicalAddressWidth = table.PhysicalAddressWidth;

pub const PhysAddr = address.PhysAddr;
pub const Phys4K = address.Phys4K;
pub const Phys2M = address.Phys2M;
pub const Phys1G = address.Phys1G;

pub const PML5 = table.PML5;
pub const PML4 = table.PML4;
pub const PDPT = table.PDPT;
pub const PD = table.PD;
pub const PT = table.PT;

pub const PagingStructureEntry = table.PagingStructureEntry;
pub const TableEntryFlags = table.TableEntryFlags;
pub const PageFlags = table.PageFlags;
pub const PageFrame = table.PageFrame;
pub const PageAttributes = table.PageAttributes;

pub const Walker = walk.Walker;
