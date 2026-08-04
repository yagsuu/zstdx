//! Intrusive collections. See `docs/specs/intrusive/list.md`,
//! `docs/specs/intrusive/queue.md`, and `docs/specs/intrusive/stack.md`.

pub const list = @import("intrusive/list.zig");
pub const queue = @import("intrusive/queue.zig");
pub const stack = @import("intrusive/stack.zig");

pub const List = list.List;
pub const Queue = queue.Queue;
pub const Stack = stack.Stack;
