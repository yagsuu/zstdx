//! cache maintenance operates on whole cache lines.
//! callers own ordering and completion; maintenance alone does not establish
//! persistence or device completion.

const std = @import("std");

const cpuid = @import("cpuid.zig");
const target = @import("target.zig");

/// requires CLFLUSH support and a nonzero power-of-two advertised line size.
pub fn lineSize() usize {
    const result = cpuid.basicFeatures();
    std.debug.assert(result.edx.clflush);

    const line = @as(usize, result.ebx.clflush_units) * 8;
    std.debug.assert(line != 0);
    std.debug.assert(std.math.isPowerOfTwo(line));
    return line;
}

/// requires:
/// - CLFLUSH support
/// - an address accessible at the current privilege level
pub fn flush(address: usize) void {
    comptime target.require();
    asm volatile ("clflush (%[address])"
        :
        : [address] "r" (address),
        : .{ .memory = true });
}

/// requires:
/// - CLFLUSHOPT support
/// - an address accessible at the current privilege level
pub fn flushOptimized(address: usize) void {
    comptime target.require();
    asm volatile ("clflushopt (%[address])"
        :
        : [address] "r" (address),
        : .{ .memory = true });
}

/// requires:
/// - CLWB support
/// - an address accessible at the current privilege level
pub fn writeBack(address: usize) void {
    comptime target.require();
    asm volatile ("clwb (%[address])"
        :
        : [address] "r" (address),
        : .{ .memory = true });
}

/// flushes every cache line intersecting `[ptr, ptr + len)`.
/// an empty range performs no cache operation.
///
/// requires:
/// - CLFLUSH support for nonempty ranges
/// - accessible memory
/// - nonwrapping `ptr + len`
pub fn flushRange(ptr: [*]const u8, len: usize) void {
    comptime target.require();
    if (len == 0) {
        return;
    }

    Impl.forEachLine(@intFromPtr(ptr), len, lineSize(), flush);
}

/// writes back every cache line intersecting `[ptr, ptr + len)`.
/// an empty range performs no cache operation.
///
/// requires:
/// - CLWB and CLFLUSH support for nonempty ranges
/// - accessible memory
/// - nonwrapping `ptr + len`
pub fn writeBackRange(ptr: [*]const u8, len: usize) void {
    comptime target.require();
    if (len == 0) {
        return;
    }

    Impl.forEachLine(@intFromPtr(ptr), len, lineSize(), writeBack);
}

/// requires privilege level 0.
pub fn writeBackInvalidate() void {
    comptime target.require();
    asm volatile ("wbinvd" ::: .{ .memory = true });
}

/// requires privilege level 0.
///
/// warning: discards dirty cache data without writing it back.
pub fn invalidate() void {
    comptime target.require();
    asm volatile ("invd" ::: .{ .memory = true });
}

const Impl = struct {
    fn forEachLine(start: usize, len: usize, line: usize, comptime operation: fn (usize) void) void {
        std.debug.assert(line != 0);
        std.debug.assert(std.math.isPowerOfTwo(line));
        std.debug.assert(len <= std.math.maxInt(usize) - start);

        if (len == 0) {
            return;
        }

        const last = (start + len - 1) & ~(line - 1);
        var cursor = start & ~(line - 1);

        while (true) {
            operation(cursor);

            if (cursor == last) {
                break;
            }

            cursor += line;
        }
    }
};

pub const unit = struct {
    var addresses: [4]usize = undefined;
    var count: usize = 0;

    test "range traversal visits exact intersecting lines without a final increment" {
        const max = std.math.maxInt(usize);
        const cases = [_]struct { start: usize, len: usize, line: usize, expected: []const usize }{
            .{ .start = 63, .len = 66, .line = 64, .expected = &.{ 0, 64, 128 } },
            .{ .start = 65, .len = 1, .line = 64, .expected = &.{64} },
            .{ .start = 64, .len = 64, .line = 64, .expected = &.{64} },
            .{ .start = 63, .len = 1, .line = 64, .expected = &.{0} },
            .{ .start = 63, .len = 2, .line = 64, .expected = &.{ 0, 64 } },
            .{ .start = max, .len = 0, .line = 64, .expected = &.{} },
            .{ .start = max - 64, .len = 64, .line = 64, .expected = &.{ max - 127, max - 63 } },
            .{ .start = max - 1, .len = 1, .line = 64, .expected = &.{max - 63} },
            .{ .start = max - 1, .len = 1, .line = 1, .expected = &.{max - 1} },
        };

        for (cases) |case| {
            count = 0;
            Impl.forEachLine(case.start, case.len, case.line, collect);

            try std.testing.expectEqualSlices(usize, case.expected, addresses[0..count]);
        }
    }

    fn collect(address: usize) void {
        std.debug.assert(count < addresses.len);
        addresses[count] = address;
        count += 1;
    }
};
