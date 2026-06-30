//! Forward read cursor over caller-owned immutable bytes. Bounds-checks every
//! peek, read, and skip; advances only on success. Copying the value is the
//! checkpoint mechanism. See docs/specs/bytes/cursor.md.

const std = @import("std");

const loadUnaligned = @import("unaligned.zig").loadUnaligned;

/// Forward read cursor over `bytes`. Borrows the slice; never allocates and
/// never waits. Every read/skip leaves the cursor unchanged on
/// `error.EndOfStream`.
pub const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    /// `EndOfStream`: operation would read past `bytes.len`.
    pub const Error = error{EndOfStream};

    pub fn wrap(bytes: []const u8) Cursor {
        return .{ .bytes = bytes };
    }

    pub fn assertValid(self: Cursor) void {
        std.debug.assert(self.isValid());
    }

    pub fn isValid(self: Cursor) bool {
        return self.index <= self.bytes.len;
    }

    pub fn position(self: Cursor) usize {
        self.assertValid();
        return self.index;
    }

    pub fn remaining(self: Cursor) usize {
        self.assertValid();
        return self.bytes.len - self.index;
    }

    /// View of the un-read tail. Borrows the backing slice.
    pub fn remainingBytes(self: Cursor) []const u8 {
        self.assertValid();
        return self.bytes[self.index..];
    }

    pub fn isEmpty(self: Cursor) bool {
        return self.remaining() == 0;
    }

    /// Borrow the next `len` bytes without advancing.
    pub fn peekBytes(self: Cursor, len: usize) Error![]const u8 {
        self.assertValid();
        if (len > self.remaining()) return error.EndOfStream;
        return self.bytes[self.index..][0..len];
    }

    /// Borrow and consume the next `len` bytes.
    pub fn readBytes(self: *Cursor, len: usize) Error![]const u8 {
        const out = try self.peekBytes(len);
        self.index += len;
        return out;
    }

    pub fn skip(self: *Cursor, len: usize) Error!void {
        _ = try self.peekBytes(len);
        self.index += len;
    }

    /// Read `T` from the next `@sizeOf(T)` bytes without advancing. Routed
    /// through `bytes.loadUnaligned`; type restrictions are enforced there.
    pub fn peek(self: Cursor, comptime T: type) Error!T {
        const bytes = try self.peekBytes(@sizeOf(T));
        const window = bytes[0..@sizeOf(T)];
        return loadUnaligned(T, window);
    }

    /// Read `T` and advance by `@sizeOf(T)` bytes.
    pub fn read(self: *Cursor, comptime T: type) Error!T {
        const value = try self.peek(T);
        self.index += @sizeOf(T);
        return value;
    }
};
