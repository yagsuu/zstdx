//! Intrusive collections. See `docs/specs/intrusive/list.md`,
//! `docs/specs/intrusive/queue.md`, `docs/specs/intrusive/stack.md`,
//! and `docs/specs/intrusive/heap.md`.

pub const heap = @import("heap.zig");
pub const list = @import("list.zig");
pub const queue = @import("queue.zig");
pub const stack = @import("stack.zig");

pub const List = list.List;
pub const Queue = queue.Queue;
pub const Stack = stack.Stack;

test {
    _ = @import("heap_test.zig");
    _ = @import("list_test.zig");
    _ = @import("queue_test.zig");
    _ = @import("stack_test.zig");
}
