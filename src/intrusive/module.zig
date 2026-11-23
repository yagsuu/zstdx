//! Intrusive collections.

pub const heap = @import("heap.zig");
pub const list = @import("list.zig");
pub const queue = @import("queue.zig");
pub const stack = @import("stack.zig");

pub const List = list.List;
pub const Queue = queue.Queue;
pub const Stack = stack.Stack;

test {
    _ = heap.unit;
    _ = list.unit;
    _ = queue.unit;
    _ = stack.unit;
}
