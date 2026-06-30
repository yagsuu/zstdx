//! Spec: docs/specs/diag/diagnostic.md.

const std = @import("std");
const graph = @import("../graph.zig");

const Allocator = std.mem.Allocator;
const SourceLocation = std.builtin.SourceLocation;
const Writer = std.Io.Writer;

const PendingDetail = struct {
    context: *const anyopaque,
    materialize: *const fn (context: *const anyopaque, allocator: Allocator) ?[]const u8,
};

pub fn LazyDetail(comptime Args: type, comptime fmt: []const u8) type {
    return struct {
        args: Args,

        const Self = @This();

        pub const is_diagnostic_lazy_detail = true;

        fn capture(self: Self, allocator: Allocator) ?PendingDetail {
            const stored = allocator.create(Self) catch return null;
            stored.* = self;
            return .{
                .context = stored,
                .materialize = materialize,
            };
        }

        fn materialize(context: *const anyopaque, allocator: Allocator) ?[]const u8 {
            const self: *const Self = @ptrCast(@alignCast(context));
            return std.fmt.allocPrint(allocator, fmt, self.args) catch null;
        }
    };
}

pub fn lazy(comptime fmt: []const u8, args: anytype) LazyDetail(@TypeOf(args), fmt) {
    return .{ .args = args };
}

/// Scoped failure-context carrier. Pass `?*Diagnostics` through fallible call
/// chains; each function opens a frame describing what it is doing.
pub const Diagnostics = struct {
    const FrameForest = graph.Forest.Linked(Frame, "node");

    arena: std.heap.ArenaAllocator,
    frames: FrameForest = .init(),
    current: ?*Frame = null,

    pub fn init(gpa: Allocator) Diagnostics {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn isEmpty(self: *const Diagnostics) bool {
        return self.frames.isEmpty();
    }

    /// Push a scope. Caller must pair the returned scope with `defer s.pop()`.
    /// To retain it on an error path, add `errdefer |err| s.fail(err)`.
    pub fn scoped(self: *Diagnostics, options: anytype) Scope {
        const label: []const u8 = options.label;
        const source: ?SourceLocation = if (@hasField(@TypeOf(options), "source")) options.source else null;

        std.debug.assert(label.len != 0);

        const arena_allocator = self.arena.allocator();
        const frame = arena_allocator.create(Frame) catch return .noop;
        const label_copy = arena_allocator.dupe(u8, label) catch return .noop;

        frame.* = .{
            .node = .{},
            .label = label_copy,
            .detail = null,
            .pending_detail = null,
            .source = source,
            .err = null,
        };

        if (@hasField(@TypeOf(options), "detail")) {
            if (!self.setInitialDetail(frame, options.detail)) return .noop;
        }

        if (self.current) |parent| {
            FrameForest.appendChild(parent, frame);
        } else {
            self.frames.appendRoot(frame);
        }
        self.current = frame;

        return .{ .inner = .{ .diag = self, .frame = frame } };
    }

    /// Null-adapter for branch-free call sites.
    pub fn open(diag: ?*Diagnostics, options: anytype) Scope {
        if (diag) |d| return d.scoped(options);
        return .noop;
    }

    /// Render retained frames to `w`. Empty diagnostics render nothing.
    pub fn format(self: Diagnostics, w: *Writer) Writer.Error!void {
        var first = true;
        var frame = self.frames.constFirstRoot();
        while (frame) |f| : (frame = FrameForest.constNextSibling(f)) {
            try renderFrame(f, w, 1, &first);
        }
    }

    fn setInitialDetail(self: *Diagnostics, frame: *Frame, detail: anytype) bool {
        if (comptime isLazyDetail(@TypeOf(detail))) {
            frame.pending_detail = detail.capture(self.arena.allocator()) orelse return false;
            return true;
        }

        const maybe_text: ?[]const u8 = detail;
        if (maybe_text) |text| {
            frame.detail = self.arena.allocator().dupe(u8, text) catch return false;
        }
        return true;
    }

    fn setLazyDetail(self: *Diagnostics, frame: *Frame, detail: anytype) void {
        if (detail.capture(self.arena.allocator())) |pending| {
            frame.pending_detail = pending;
        }
    }

    fn materializePendingDetail(self: *Diagnostics, frame: *Frame) void {
        const pending = frame.pending_detail orelse return;
        frame.pending_detail = null;
        if (pending.materialize(pending.context, self.arena.allocator())) |detail| {
            frame.detail = detail;
        }
    }

    fn renderFrame(frame: *const Frame, w: *Writer, depth: usize, first: *bool) Writer.Error!void {
        if (first.*) {
            first.* = false;
        } else {
            try w.writeByte('\n');
        }

        try writeIndent(w, depth);
        try w.print("at {f}", .{std.zig.fmtString(frame.label)});
        if (frame.detail) |detail| {
            try w.print(": {f}", .{std.zig.fmtString(detail)});
        }
        if (frame.source) |source| {
            try w.print(" ({s}:{d})", .{ source.file, source.line });
        }
        if (frame.err) |err| {
            try w.print(" -> {t}", .{err});
        }

        var child = FrameForest.constFirstChild(frame);
        while (child) |c| : (child = FrameForest.constNextSibling(c)) {
            try renderFrame(c, w, depth + 1, first);
        }
    }

    fn writeIndent(w: *Writer, depth: usize) Writer.Error!void {
        var i: usize = 0;
        while (i < depth * 2) : (i += 1) {
            try w.writeByte(' ');
        }
    }

    pub const Frame = struct {
        node: graph.Forest.LinkedNode = .{},
        label: []const u8,
        detail: ?[]const u8,
        pending_detail: ?PendingDetail,
        source: ?SourceLocation,
        err: ?anyerror,
    };
};

pub const ScopeOptions = struct {
    /// Short noun phrase describing the operation. Copied into the diagnostics
    /// arena on push.
    label: []const u8,
    /// Optional secondary line of context. Copied into the diagnostics arena on
    /// push, and replaced by `Scope.detail*` calls.
    detail: ?[]const u8 = null,
    /// Call-site source location. Pass `@src()` to render `(file:line)`.
    source: ?SourceLocation = null,
};

pub const Scope = struct {
    inner: ?Inner = null,

    pub const noop: Scope = .{};

    const Inner = struct {
        diag: *Diagnostics,
        frame: *Diagnostics.Frame,
    };

    /// Replace the frame detail. No-op for `Scope.noop` or arena OOM.
    pub fn detail(self: Scope, text: []const u8) void {
        const inner = self.inner orelse return;
        const detail_copy = inner.diag.arena.allocator().dupe(u8, text) catch return;
        inner.frame.detail = detail_copy;
        inner.frame.pending_detail = null;
    }

    /// Lazily format and replace the frame detail if the frame is retained.
    pub fn detailf(self: Scope, comptime fmt: []const u8, args: anytype) void {
        const inner = self.inner orelse return;
        inner.diag.setLazyDetail(inner.frame, lazy(fmt, args));
    }

    /// Mark this frame failed. Retained by the following `pop`.
    pub fn fail(self: Scope, err: anyerror) void {
        const inner = self.inner orelse return;
        inner.frame.err = err;
    }

    /// Pop this frame. Successful leaf frames are unlinked; failed frames and
    /// ancestors of retained children remain in the diagnostics tree.
    pub fn pop(self: Scope) void {
        const inner = self.inner orelse return;
        const diag = inner.diag;
        const frame = inner.frame;

        std.debug.assert(diag.current == frame);
        diag.current = Diagnostics.FrameForest.parent(frame);

        if (frame.err == null and Diagnostics.FrameForest.firstChild(frame) == null) {
            diag.frames.remove(frame);
            return;
        }

        diag.materializePendingDetail(frame);
    }
};

fn isLazyDetail(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "is_diagnostic_lazy_detail") and
            T.is_diagnostic_lazy_detail,
        else => false,
    };
}
