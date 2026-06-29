//! Byte stream primitives. See docs/specs/bytes/unaligned.md,
//! docs/specs/bytes/access.md, and docs/specs/bytes/cursor.md.

pub const unaligned = @import("bytes/unaligned.zig");
pub const access = @import("bytes/access.zig");
pub const cursor = @import("bytes/cursor.zig");

pub const loadUnaligned = unaligned.loadUnaligned;
pub const storeUnaligned = unaligned.storeUnaligned;
pub const load = access.load;
pub const store = access.store;
pub const loadSlice = access.loadSlice;
pub const storeSlice = access.storeSlice;
pub const loadTail = access.loadTail;
pub const Cursor = cursor.Cursor;
