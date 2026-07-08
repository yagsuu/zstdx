//! Spec: docs/specs/diag/diagnostic.md.

const std = @import("std");

const mem = @import("../mem.zig");

const Allocator = std.mem.Allocator;
const FrameIndex = usize;
const SourceLocation = std.builtin.SourceLocation;
const Writer = std.Io.Writer;

pub fn FormattedDetail(comptime Args: type, comptime format: []const u8) type {
    return struct {
        args: Args,

        const Self = @This();

        fn materialize(self: Self, allocator: Allocator) ?[]const u8 {
            return std.fmt.allocPrint(allocator, format, self.args) catch null;
        }
    };
}

pub fn fmt(comptime format: []const u8, args: anytype) FormattedDetail(@TypeOf(args), format) {
    return .{ .args = args };
}

pub fn scope(diag: anytype, options: anytype) Scope(ScopeDiag(@TypeOf(diag)), @TypeOf(options)) {
    return makeScope(scopeDiagValue(diag), options);
}

pub const Diagnostics = struct {
    pub const StaticConfig = struct {
        frames: usize,
        arena_bytes: usize = 0,
    };

    pub fn Static(comptime config: StaticConfig) type {
        comptime if (config.frames == 0) {
            @compileError("Diagnostics.Static requires at least one frame");
        };
        const Arena = mem.Arena.Static(config.arena_bytes);

        return struct {
            frames: [config.frames]Frame = undefined,
            arena: Arena = Arena.init(),
            frame_len: usize = 0,
            first_root: ?FrameIndex = null,
            last_root: ?FrameIndex = null,
            current: ?FrameIndex = null,

            const Self = @This();

            pub fn init() Self {
                return .{
                    .arena = Arena.init(),
                };
            }

            pub fn deinit(self: *Self) void {
                self.clear();
                self.* = undefined;
            }

            pub fn clear(self: *Self) void {
                std.debug.assert(self.current == null);
                self.frame_len = 0;
                self.first_root = null;
                self.last_root = null;
                self.current = null;
                self.arena.reset();
            }

            pub fn isEmpty(self: *const Self) bool {
                return self.first_root == null;
            }

            pub fn scope(self: *Self, options: anytype) Scope(*Self, @TypeOf(options)) {
                return makeScope(self, options);
            }

            /// Render retained frames to `w`. Empty diagnostics render nothing.
            pub fn format(self: *const Self, w: *Writer) Writer.Error!void {
                var first = true;
                var frame = self.first_root;
                while (frame) |index| : (frame = self.frames[index].next_sibling) {
                    try self.renderFrame(index, w, 1, &first);
                }
            }

            fn pushFrame(self: *Self, options: anytype) ?FrameIndex {
                const Options = @TypeOf(options);
                const label: []const u8 = options.label;
                const source: ?SourceLocation = if (@hasField(Options, "source")) options.source else null;

                std.debug.assert(label.len != 0);

                if (self.frame_len == self.frames.len) return null;
                const index = self.frame_len;
                self.frame_len += 1;
                self.frames[index] = .{
                    .parent = self.current,
                    .first_child = null,
                    .last_child = null,
                    .next_sibling = null,
                    .label = label,
                    .detail = null,
                    .source = source,
                    .err = null,
                };

                self.appendFrame(index, self.current);
                self.current = index;
                return index;
            }

            fn appendFrame(self: *Self, frame: FrameIndex, parent: ?FrameIndex) void {
                if (parent) |p| {
                    if (self.frames[p].last_child) |last| {
                        self.frames[last].next_sibling = frame;
                    } else {
                        self.frames[p].first_child = frame;
                    }
                    self.frames[p].last_child = frame;
                } else {
                    if (self.last_root) |last| {
                        self.frames[last].next_sibling = frame;
                    } else {
                        self.first_root = frame;
                    }
                    self.last_root = frame;
                }
            }

            fn popFrame(self: *Self, frame: FrameIndex) void {
                std.debug.assert(self.current == frame);
                self.current = self.frames[frame].parent;

                if (self.frames[frame].err == null) {
                    self.discardFrame(frame);
                }
            }

            fn unwindFrame(self: *Self, frame: FrameIndex, err: anyerror) void {
                self.frames[frame].err = err;
            }

            fn clearFrameDetail(self: *Self, frame: FrameIndex) void {
                self.frames[frame].detail = null;
            }

            fn setBorrowedFrameDetail(self: *Self, frame: FrameIndex, value: ?[]const u8) void {
                self.frames[frame].detail = value;
            }

            fn setFormattedFrameDetail(self: *Self, frame: FrameIndex, value: anytype) void {
                comptime {
                    if (!@hasDecl(@TypeOf(value), "materialize")) {
                        @compileError("formatted diagnostic details must be produced by stdx.diag.fmt(...)");
                    }
                }

                const alloc = self.allocator() orelse return;
                const text = value.materialize(alloc) orelse return;
                self.frames[frame].detail = text;
            }

            fn allocator(self: *Self) ?Allocator {
                if (config.arena_bytes == 0) return null;
                return self.arena.allocator();
            }

            fn discardFrame(self: *Self, frame: FrameIndex) void {
                self.unlinkFrame(frame);
                self.frame_len = frame;
            }

            fn unlinkFrame(self: *Self, frame: FrameIndex) void {
                const parent = self.frames[frame].parent;
                var previous: ?FrameIndex = null;
                var link: *?FrameIndex = if (parent) |p| &self.frames[p].first_child else &self.first_root;

                while (link.*) |cursor| {
                    if (cursor == frame) {
                        link.* = self.frames[frame].next_sibling;
                        if (parent) |p| {
                            if (self.frames[p].last_child == frame) self.frames[p].last_child = previous;
                        } else {
                            if (self.last_root == frame) self.last_root = previous;
                        }
                        return;
                    }
                    previous = cursor;
                    link = &self.frames[cursor].next_sibling;
                }
            }

            fn renderFrame(
                self: *const Self,
                frame: FrameIndex,
                w: *Writer,
                depth: usize,
                first: *bool,
            ) Writer.Error!void {
                const item = self.frames[frame];

                if (first.*) {
                    first.* = false;
                } else {
                    try w.writeByte('\n');
                }

                try writeIndent(w, depth);
                try w.print("at {f}", .{std.zig.fmtString(item.label)});
                if (item.detail) |detail| {
                    try w.print(": {f}", .{std.zig.fmtString(detail)});
                }
                if (item.source) |source| {
                    try w.print(" ({s}:{d})", .{ source.file, source.line });
                }
                if (item.err) |err| {
                    try w.print(" -> {t}", .{err});
                }

                var child = item.first_child;
                while (child) |c| : (child = self.frames[c].next_sibling) {
                    try self.renderFrame(c, w, depth + 1, first);
                }
            }
        };
    }
};

pub fn Scope(comptime Diag: type, comptime Options: type) type {
    return struct {
        diag: Diag,
        frame: ?FrameIndex = null,
        options: Options,
        detail_overridden: bool = false,

        const Self = @This();

        pub fn pop(self: *Self) void {
            if (comptime DiagnosticChild(Diag) == NoopDiagnostics) return;
            const frame = self.frame orelse return;
            const diag = diagnosticPointer(self.diag) orelse return;
            diag.popFrame(frame);
            self.frame = null;
        }

        pub fn unwind(self: *Self, err: anyerror) void {
            if (comptime DiagnosticChild(Diag) == NoopDiagnostics) return;
            const frame = self.frame orelse return;
            const diag = diagnosticPointer(self.diag) orelse return;
            if (!self.detail_overridden and comptime @hasField(Options, "detail")) {
                Detail.apply(diag, frame, self.options.detail);
            }
            diag.unwindFrame(frame, err);
        }

        pub fn detail(self: *Self, value: anytype) void {
            if (comptime DiagnosticChild(Diag) == NoopDiagnostics) return;
            const frame = self.frame orelse return;
            const diag = diagnosticPointer(self.diag) orelse return;
            Detail.apply(diag, frame, value);
            self.detail_overridden = true;
        }
    };
}

fn makeScope(diag: anytype, options: anytype) Scope(@TypeOf(diag), @TypeOf(options)) {
    var out: Scope(@TypeOf(diag), @TypeOf(options)) = .{
        .diag = diag,
        .options = options,
    };
    if (comptime DiagnosticChild(@TypeOf(diag)) == NoopDiagnostics) return out;

    const d = diagnosticPointer(diag) orelse return out;
    out.frame = d.pushFrame(options);
    return out;
}

fn ScopeDiag(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .null => ?*NoopDiagnostics,
        else => T,
    };
}

fn scopeDiagValue(value: anytype) ScopeDiag(@TypeOf(value)) {
    return switch (@typeInfo(@TypeOf(value))) {
        .null => null,
        else => value,
    };
}

fn DiagnosticChild(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .null => NoopDiagnostics,
        .pointer => |pointer| pointer.child,
        .optional => |optional| DiagnosticChild(optional.child),
        else => @compileError(
            "diagnostics value must be null, a diagnostics pointer, or an optional diagnostics pointer",
        ),
    };
}

fn DiagnosticPointer(comptime T: type) type {
    return *DiagnosticChild(T);
}

fn diagnosticPointer(value: anytype) ?DiagnosticPointer(@TypeOf(value)) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .null => null,
        .pointer => value,
        .optional => if (value) |child| diagnosticPointer(child) else null,
        else => @compileError(
            "diagnostics value must be null, a diagnostics pointer, or an optional diagnostics pointer",
        ),
    };
}

const Detail = struct {
    const Kind = enum {
        none,
        borrowed,
        formatted,
    };

    fn apply(diag: anytype, frame: FrameIndex, value: anytype) void {
        switch (comptime kind(@TypeOf(value))) {
            .none => diag.clearFrameDetail(frame),
            .borrowed => diag.setBorrowedFrameDetail(frame, borrowed(value)),
            .formatted => diag.setFormattedFrameDetail(frame, value),
        }
    }

    fn kind(comptime T: type) Kind {
        return switch (@typeInfo(T)) {
            .null => .none,
            .optional, .pointer => .borrowed,
            .@"struct" => .formatted,
            else => @compileError("diagnostic detail must be null, bytes, optional bytes, or stdx.diag.fmt(...)"),
        };
    }

    fn borrowed(value: anytype) ?[]const u8 {
        const text: ?[]const u8 = value;
        return text;
    }
};

fn writeIndent(w: *Writer, depth: usize) Writer.Error!void {
    var i: usize = 0;
    while (i < depth * 2) : (i += 1) {
        try w.writeByte(' ');
    }
}

const Frame = struct {
    parent: ?FrameIndex,
    first_child: ?FrameIndex,
    last_child: ?FrameIndex,
    next_sibling: ?FrameIndex,
    label: []const u8,
    detail: ?[]const u8,
    source: ?SourceLocation,
    err: ?anyerror,
};

const NoopDiagnostics = struct {};
