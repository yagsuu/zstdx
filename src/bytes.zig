//! Bounds-checked random byte access. See `docs/specs/bytes/access.md`.

pub const access = @import("bytes/access.zig");
pub const Error = access.Error;

pub const loadSlice = access.loadSlice;
pub const storeSlice = access.storeSlice;
