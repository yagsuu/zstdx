//! Address primitive contract tests. Spec: docs/specs/addr/address.md.

const std = @import("std");

const zstdx = @import("zstdx");

const addr = zstdx.addr;

const TagA = opaque {};
const TagB = opaque {};
const A = addr.Address(TagA, u8);
const B = addr.Address(TagB, u8);
const PhysAddr = addr.PhysAddr;
const VirtAddr = addr.VirtAddr;

const testing = std.testing;

test "unit: Address tags distinguish types with the same Int width" {
    const a = A.fromInt(10);
    const b = B.fromInt(10);
    try testing.expect(@TypeOf(a) != @TypeOf(b));
}

test "unit: Address round-trips fromInt/raw and zero/max constants" {
    const a = A.fromInt(10);
    try testing.expectEqual(@as(u8, 10), a.raw());
    try testing.expectEqual(@as(u8, 0), A.zero().raw());
    try testing.expectEqual(std.math.maxInt(u8), A.max().raw());
}

test "unit: Address arithmetic detects overflow and underflow" {
    const a = A.fromInt(10);
    try testing.expectEqual(@as(u8, 12), (try a.add(2)).raw());
    try testing.expectEqual(@as(u8, 8), (try a.sub(2)).raw());
    try testing.expectEqual(@as(u8, 2), try a.diff(A.fromInt(8)));
    try testing.expectError(error.Overflow, A.max().add(1));
    try testing.expectError(error.Overflow, A.zero().sub(1));
    try testing.expectError(error.Overflow, A.zero().diff(A.fromInt(1)));
}

test "unit: Address alignment helpers reject invalid alignment" {
    const a = A.fromInt(10);
    try testing.expectError(error.InvalidAlignment, a.alignUp(3));
    try testing.expectError(error.InvalidAlignment, a.alignDown(0));
}

test "unit: Address alignUp/alignDown round and isAligned reports the result" {
    const a = A.fromInt(10);
    try testing.expectEqual(@as(u8, 16), (try a.alignUp(8)).raw());
    try testing.expectEqual(@as(u8, 8), (try a.alignDown(8)).raw());
    try testing.expect(!a.isAligned(8));
    try testing.expect(A.fromInt(16).isAligned(8));
}

test "unit: built-in PhysAddr and VirtAddr aliases have expected raw widths" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(PhysAddr.Raw));
    try testing.expectEqual(@sizeOf(usize), @sizeOf(VirtAddr.Raw));
}
