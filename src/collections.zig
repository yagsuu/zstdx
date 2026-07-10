//! Fixed-storage container primitives.
//! Specs: docs/specs/collections/list-static.md, docs/specs/collections/list-bounded.md,
//! docs/specs/collections/ring-static.md, and docs/specs/collections/ring-bounded.md.

pub const list = @import("collections/list.zig");
pub const ring = @import("collections/ring.zig");

pub const List = list.List;
pub const Ring = ring.Ring;
