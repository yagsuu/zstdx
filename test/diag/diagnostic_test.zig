//! Scoped diagnostics contract tests. Spec: docs/specs/diag/diagnostic.md.

const std = @import("std");
const stdx = @import("stdx");

const Diagnostics = stdx.diag.Diagnostics;

const testing = std.testing;

fn source(comptime file: [:0]const u8, line: u32) std.builtin.SourceLocation {
    return .{
        .module = "stdx-test",
        .file = file,
        .fn_name = "unit",
        .line = line,
        .column = 1,
    };
}

const ExplodingFormatter = struct {
    pub fn format(_: @This(), _: *std.Io.Writer) std.Io.Writer.Error!void {
        unreachable;
    }
};

fn expectRender(expected: []const u8, diag: Diagnostics) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try diag.format(&writer);
    try testing.expectEqualStrings(expected, writer.buffered());
}

test "unit: empty diagnostics render nothing" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    try testing.expect(diag.isEmpty());
    try expectRender("", diag);
}

test "unit: push-pop success discards the frame" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{ .label = "prepare host resources" });
    scope.pop();

    try testing.expect(diag.isEmpty());
    try expectRender("", diag);
}

test "unit: push-fail-pop retains the frame and error tag" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{ .label = "open firmware" });
    scope.fail(error.FileNotFound);
    scope.pop();

    try testing.expect(!diag.isEmpty());
    try expectRender("  at open firmware -> FileNotFound", diag);
}

test "unit: nested failed scopes render as a chain" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var parent = diag.scoped(.{
        .label = "prepare host resources",
        .source = source("src/host/resources.zig", 73),
    });
    var child = diag.scoped(.{
        .label = "firmware code",
        .detail = "./zfw.fd (relative to /home/me/example)",
        .source = source("src/host/resources.zig", 198),
    });
    child.fail(error.FileNotFound);
    child.pop();
    parent.fail(error.FileNotFound);
    parent.pop();

    try expectRender(
        "  at prepare host resources (src/host/resources.zig:73) -> FileNotFound\n" ++
            "    at firmware code: ./zfw.fd (relative to /home/me/example) " ++
            "(src/host/resources.zig:198) -> FileNotFound",
        diag,
    );
}

test "unit: sibling failed scopes render under their retained parent" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var parent = diag.scoped(.{ .label = "parent op" });
    var child_a = diag.scoped(.{ .label = "child A" });
    child_a.fail(error.Foo);
    child_a.pop();
    var child_b = diag.scoped(.{ .label = "child B" });
    child_b.fail(error.Bar);
    child_b.pop();
    parent.fail(error.Foo);
    parent.pop();

    try expectRender(
        "  at parent op -> Foo\n" ++
            "    at child A -> Foo\n" ++
            "    at child B -> Bar",
        diag,
    );
}

test "unit: null diagnostics adapter is a no-op" {
    var scope = Diagnostics.open(null, .{
        .label = "ignored",
        .detail = stdx.diag.lazy("{d}", .{42}),
    });
    scope.detail("first");
    scope.detailf("{d}", .{42});
    scope.fail(error.Ignored);
    scope.pop();
}

test "unit: detail replacement renders only the latest detail" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{ .label = "read config", .detail = "initial" });
    scope.detail("first");
    scope.detail("second");
    scope.fail(error.BadConfig);
    scope.pop();

    try expectRender("  at read config: second -> BadConfig", diag);
}

test "unit: detailf formats detail text into the frame" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{ .label = "parse field" });
    scope.detailf("index {d}", .{42});
    scope.fail(error.InvalidField);
    scope.pop();

    try expectRender("  at parse field: index 42 -> InvalidField", diag);
}

test "unit: lazy option detail formats detail text into the frame" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{
        .label = "parse field",
        .detail = stdx.diag.lazy("index {d}", .{42}),
    });
    scope.fail(error.InvalidField);
    scope.pop();

    try expectRender("  at parse field: index 42 -> InvalidField", diag);
}

test "unit: lazy details are not formatted for discarded success scopes" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var option_scope = diag.scoped(.{
        .label = "option success",
        .detail = stdx.diag.lazy("{f}", .{ExplodingFormatter{}}),
    });
    option_scope.pop();

    var method_scope = diag.scoped(.{ .label = "method success" });
    method_scope.detailf("{f}", .{ExplodingFormatter{}});
    method_scope.pop();

    try testing.expect(diag.isEmpty());
    try expectRender("", diag);
}

test "unit: OOM during push degrades to no retained frame" {
    var failing_allocator = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var diag = Diagnostics.init(failing_allocator.allocator());
    defer diag.deinit();

    var scope = diag.scoped(.{ .label = "oom scope" });
    scope.detail("ignored");
    scope.fail(error.OutOfMemory);
    scope.pop();

    try testing.expect(diag.isEmpty());
    try expectRender("", diag);
}

test "unit: source location renders when present and omits when null" {
    var with_source = Diagnostics.init(testing.allocator);
    defer with_source.deinit();
    var scoped_with_source = with_source.scoped(.{
        .label = "with source",
        .source = source("test/source.zig", 9),
    });
    scoped_with_source.fail(error.Boom);
    scoped_with_source.pop();
    try expectRender("  at with source (test/source.zig:9) -> Boom", with_source);

    var without_source = Diagnostics.init(testing.allocator);
    defer without_source.deinit();
    var scoped_without_source = without_source.scoped(.{ .label = "without source" });
    scoped_without_source.fail(error.Boom);
    scoped_without_source.pop();
    try expectRender("  at without source -> Boom", without_source);
}

test "unit: label and detail bytes are escaped for logs" {
    var diag = Diagnostics.init(testing.allocator);
    defer diag.deinit();

    var scope = diag.scoped(.{
        .label = "load\\firmware\ncode",
        .detail = "path\twith\\slash",
    });
    scope.fail(error.Bad);
    scope.pop();

    try expectRender("  at load\\\\firmware\\ncode: path\\twith\\\\slash -> Bad", diag);
}
