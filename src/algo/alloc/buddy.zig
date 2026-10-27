const std = @import("std");

pub const Error = error{
    InvalidRequest,
    Overflow,
};

pub const Block = struct {
    start: usize,
    order: u8,

    pub fn size(self: Block) Error!usize {
        return blockSize(self.order);
    }

    pub fn contains(self: Block, index: usize) Error!bool {
        const len = try self.size();
        const end = std.math.add(usize, self.start, len) catch return error.Overflow;
        return index >= self.start and index < end;
    }

    pub fn buddy(self: Block) Error!Block {
        const len = try self.size();
        return .{ .start = self.start ^ len, .order = self.order };
    }

    pub fn parent(self: Block) Error!Block {
        if (self.order == std.math.maxInt(u8)) {
            return error.Overflow;
        }

        const parent_order: u8 = self.order + 1;
        const parent_size = try blockSize(parent_order);
        const parent_start = self.start & ~(parent_size - 1);

        if (std.math.maxInt(usize) - parent_start < parent_size) {
            return error.Overflow;
        }

        return .{ .start = parent_start, .order = parent_order };
    }

    pub fn split(self: Block) Error![2]Block {
        if (self.order == 0) {
            return error.InvalidRequest;
        }

        const child_order: u8 = self.order - 1;
        const child_size = try blockSize(child_order);
        const right_start = std.math.add(usize, self.start, child_size) catch return error.Overflow;

        return .{
            .{ .start = self.start, .order = child_order },
            .{ .start = right_start, .order = child_order },
        };
    }

    pub fn canCoalesce(self: Block, other: Block) bool {
        if (self.order != other.order) {
            return false;
        }
        const len = self.size() catch return false;
        return (self.start ^ len) == other.start;
    }
};

pub fn blockSize(order: u8) Error!usize {
    if (order >= @bitSizeOf(usize)) {
        return error.Overflow;
    }
    return @as(usize, 1) << @intCast(order);
}

pub fn orderForLen(len: usize) Error!u8 {
    if (len == 0) {
        return error.InvalidRequest;
    }

    if (len == 1) {
        return 0;
    }

    const bits = @bitSizeOf(usize);
    const raw = bits - @clz(len - 1);

    if (raw >= bits) {
        return error.Overflow;
    }

    return @intCast(raw);
}

pub const unit = struct {
    const testing = std.testing;

    test "block geometry preserves siblings and half-open extents" {
        const block: Block = .{ .start = 16, .order = 3 };
        const children = try block.split();
        const sibling = try block.buddy();

        try testing.expectEqual(@as(usize, 8), try block.size());
        try testing.expect(try block.contains(16));
        try testing.expect(try block.contains(23));
        try testing.expect(!try block.contains(15));
        try testing.expect(!try block.contains(24));
        try testing.expectEqual(Block{ .start = 16, .order = 2 }, children[0]);
        try testing.expectEqual(Block{ .start = 20, .order = 2 }, children[1]);
        try testing.expectEqual(children[1], try children[0].buddy());
        try testing.expectEqual(block, try children[0].parent());
        try testing.expectEqual(block, try children[1].parent());
        try testing.expectEqual(Block{ .start = 24, .order = 3 }, sibling);
        try testing.expectEqual(block, try sibling.buddy());
        try testing.expectEqual(try block.parent(), try sibling.parent());
        try testing.expect(children[0].canCoalesce(children[1]));
        try testing.expect(children[1].canCoalesce(children[0]));
        try testing.expect(!children[1].canCoalesce(.{ .start = 24, .order = 2 }));
        try testing.expect(!children[0].canCoalesce(block));
    }

    test "orders round lengths upward within representable sizes" {
        const highest: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);
        const top: u8 = @bitSizeOf(usize) - 1;

        try testing.expectEqual(@as(usize, 1), try blockSize(0));
        try testing.expectEqual(@as(usize, 2), try blockSize(1));
        try testing.expectEqual(@as(usize, 1024), try blockSize(10));
        try testing.expectEqual(highest, try blockSize(top));
        try testing.expectEqual(@as(u8, 0), try orderForLen(1));
        try testing.expectEqual(@as(u8, 1), try orderForLen(2));
        try testing.expectEqual(@as(u8, 2), try orderForLen(3));
        try testing.expectEqual(@as(u8, 10), try orderForLen(1024));
        try testing.expectEqual(@as(u8, 11), try orderForLen(1025));
        try testing.expectEqual(top, try orderForLen(highest));
        try testing.expectError(error.InvalidRequest, orderForLen(0));
        try testing.expectError(error.Overflow, orderForLen(highest + 1));
        try testing.expectError(error.Overflow, blockSize(@bitSizeOf(usize)));
    }

    test "invalid orders and overflowing geometry preserve errors" {
        const invalid: Block = .{ .start = 0, .order = @bitSizeOf(usize) };
        const last: Block = .{ .start = std.math.maxInt(usize), .order = 1 };
        const singleton: Block = .{ .start = 0, .order = 0 };
        const top: Block = .{ .start = 0, .order = @bitSizeOf(usize) - 1 };
        const max_order: Block = .{ .start = 0, .order = std.math.maxInt(u8) };
        const overflowing_parent: Block = .{ .start = std.math.maxInt(usize) - 1, .order = 0 };

        try testing.expectError(error.InvalidRequest, singleton.split());
        try testing.expectError(error.Overflow, invalid.size());
        try testing.expectError(error.Overflow, invalid.contains(0));
        try testing.expectError(error.Overflow, invalid.buddy());
        try testing.expectError(error.Overflow, max_order.split());
        try testing.expectError(error.Overflow, max_order.parent());
        try testing.expectError(error.Overflow, top.parent());
        try testing.expectError(error.Overflow, overflowing_parent.parent());
        try testing.expectError(error.Overflow, last.contains(last.start));
        try testing.expectError(error.Overflow, last.split());
        try testing.expect(!invalid.canCoalesce(invalid));
    }
};
