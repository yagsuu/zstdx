//! DMA buffer primitive. See `docs/specs/dma/buffer.md`.

const std = @import("std");

const address = @import("addr").address;

const DMAAddr = address.DMAAddr;

fn requireRuntimeValue(comptime T: type) void {
    if (@sizeOf(T) == 0) @compileError("Buffer element type must have nonzero size");
}

pub fn Buffer(comptime T: type) type {
    comptime requireRuntimeValue(T);

    return struct {
        virt: []T,
        dma: DMAAddr,

        const Self = @This();

        pub const Item = T;
        pub const Address = DMAAddr;

        pub const InitError = error{ Misaligned, Overflow };
        pub const OffsetError = error{OutOfBounds};
        pub const SubError = error{ Overflow, OutOfBounds };
        pub const Error = InitError || OffsetError || SubError;

        /// A subrange names an item window for `sub`. Both fields are item counts, not bytes.
        pub const SubRange = struct {
            offset_items: usize,
            count_items: usize,
        };

        /// Validates `dma` against `@alignOf(T)` and the buffer address range.
        pub fn init(virt: []T, dma: Address) InitError!Self {
            return initAlignedWith(virt, dma, @alignOf(T));
        }

        /// Validates `dma` against `max(alignment, @alignOf(T))` and the buffer address range.
        /// A zero or non-power-of-two alignment returns `error.Misaligned`.
        pub fn initAligned(virt: []T, dma: Address, alignment: Address.Int) InitError!Self {
            if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return error.Misaligned;
            return initAlignedWith(virt, dma, alignment);
        }

        fn initAlignedWith(virt: []T, dma: Address, alignment: Address.Int) InitError!Self {
            const type_alignment: Address.Int = @alignOf(T);
            const required = @max(alignment, type_alignment);
            if ((dma.raw() & (required - 1)) != 0) return error.Misaligned;

            const elem_size: Address.Int = @sizeOf(T);
            const virt_len: Address.Int = std.math.cast(Address.Int, virt.len) orelse return error.Overflow;
            const byte_len = std.math.mul(Address.Int, virt_len, elem_size) catch return error.Overflow;
            _ = std.math.add(Address.Int, dma.raw(), byte_len) catch return error.Overflow;

            return .{ .virt = virt, .dma = dma };
        }

        pub fn slice(self: Self) []T {
            self.assertValid();
            return self.virt;
        }

        pub fn constSlice(self: Self) []const T {
            self.assertValid();
            return self.virt;
        }

        pub fn bytes(self: Self) []u8 {
            self.assertValid();
            return std.mem.sliceAsBytes(self.virt);
        }

        pub fn constBytes(self: Self) []const u8 {
            self.assertValid();
            return std.mem.sliceAsBytes(self.virt);
        }

        pub fn len(self: Self) usize {
            self.assertValid();
            return self.virt.len;
        }

        /// Construction proves that the byte length does not overflow `Address.Int`.
        pub fn byteLen(self: Self) Address.Int {
            self.assertValid();
            const virt_len: Address.Int = @intCast(self.virt.len);
            return virt_len * @sizeOf(T);
        }

        pub fn isEmpty(self: Self) bool {
            self.assertValid();
            return self.virt.len == 0;
        }

        pub fn dmaAddr(self: Self) Address {
            self.assertValid();
            return self.dma;
        }

        /// `len()` is a valid one-past-the-end item offset.
        pub fn dmaAddrAt(self: Self, offset_items: usize) OffsetError!Address {
            self.assertValid();
            if (offset_items > self.virt.len) return error.OutOfBounds;
            const offset_raw: Address.Int = @intCast(offset_items);
            const byte_offset = offset_raw * @sizeOf(T);
            return self.dma.add(byte_offset) catch unreachable;
        }

        /// Returns a validated subrange that preserves the caller's contiguity claim.
        pub fn sub(self: Self, range: SubRange) SubError!Self {
            self.assertValid();
            const end = std.math.add(
                usize,
                range.offset_items,
                range.count_items,
            ) catch return error.Overflow;
            if (end > self.virt.len) return error.OutOfBounds;

            const offset_raw: Address.Int = @intCast(range.offset_items);
            const byte_offset = offset_raw * @sizeOf(T);
            return .{
                .virt = self.virt[range.offset_items..end],
                .dma = self.dma.add(byte_offset) catch unreachable,
            };
        }

        pub fn assertValid(self: Self) void {
            std.debug.assert((self.dma.raw() & (@as(Address.Int, @alignOf(T)) - 1)) == 0);
            const virt_len: Address.Int = std.math.cast(Address.Int, self.virt.len) orelse unreachable;
            const byte_len = std.math.mul(Address.Int, virt_len, @sizeOf(T)) catch unreachable;
            _ = std.math.add(Address.Int, self.dma.raw(), byte_len) catch unreachable;
        }
    };
}
