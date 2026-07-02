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

fn expectRender(expected: []const u8, diag: anytype) !void {
    var buffer: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try diag.format(&writer);
    try testing.expectEqualStrings(expected, writer.buffered());
}

fn failOne(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{
        .label = "open firmware",
        .detail = "/boot/fw.bin",
    });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    return error.FileNotFound;
}

fn failOneWithFormattedDetail(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{
        .label = "open firmware",
        .detail = stdx.diag.fmt("{s}", .{"/boot/fw.bin"}),
    });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    return error.FileNotFound;
}

fn parseHeader(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{ .label = "parse header" });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    return error.InvalidFirmware;
}

fn parseFirmware(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{ .label = "parse firmware" });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    try parseHeader(diag);
}

fn loadFirmware(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{
        .label = "load firmware",
        .detail = "/boot/fw.bin",
    });
    defer frame.pop();
    errdefer |err| frame.unwind(err);

    try parseFirmware(diag);
}

fn successfulWithFormattedDetail(diag: anytype) !void {
    var frame = stdx.diag.scope(diag, .{
        .label = "successful operation",
        .detail = stdx.diag.fmt("{f}", .{ExplodingFormatter{}}),
    });
    defer frame.pop();
}

test "unit: empty diagnostics render nothing" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expect(diag.isEmpty());
    try expectRender("", &diag);
}

test "unit: scope null adapter is a safe no-op" {
    var frame = stdx.diag.scope(null, .{
        .label = "ignored",
        .detail = stdx.diag.fmt("{f}", .{ExplodingFormatter{}}),
    });
    frame.detail(stdx.diag.fmt("{f}", .{ExplodingFormatter{}}));
    frame.unwind(error.Ignored);
    frame.pop();
}

test "unit: single errdefer scoped unwind renders one frame" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expectError(error.FileNotFound, failOne(&diag));

    try testing.expect(!diag.isEmpty());
    try expectRender("  at open firmware: /boot/fw.bin -> FileNotFound", &diag);
}

test "unit: nested scoped unwinds render outer-to-inner chain" {
    const Diag = Diagnostics.Static(.{ .frames = 3 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expectError(error.InvalidFirmware, loadFirmware(&diag));

    try expectRender(
        "  at load firmware: /boot/fw.bin -> InvalidFirmware\n" ++
            "    at parse firmware -> InvalidFirmware\n" ++
            "      at parse header -> InvalidFirmware",
        &diag,
    );
}

test "unit: successful scoped call does not evaluate formatted detail" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    try successfulWithFormattedDetail(&diag);

    try testing.expect(diag.isEmpty());
    try expectRender("", &diag);
}

test "unit: successful scoped call does not consume arena bytes" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    try successfulWithFormattedDetail(&diag);

    try testing.expectEqual(@as(usize, 0), diag.arena.used());
    try testing.expect(diag.isEmpty());
}

test "unit: frame capacity exhaustion preserves originating error and omits excess frames" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expectError(error.InvalidFirmware, loadFirmware(&diag));

    try expectRender("  at load firmware: /boot/fw.bin -> InvalidFirmware", &diag);
}

test "unit: formatted detail arena exhaustion preserves error and omits detail" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expectError(error.FileNotFound, failOneWithFormattedDetail(&diag));

    try expectRender("  at open firmware -> FileNotFound", &diag);
}

test "unit: successful scoped leaf is discarded" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{ .label = "probe cache" });
    frame.pop();

    try testing.expect(diag.isEmpty());
    try expectRender("", &diag);
}

test "unit: detail replacement latest wins" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{ .label = "read config" });
    frame.detail("first");
    frame.detail("second");
    frame.unwind(error.BadConfig);
    frame.pop();

    try expectRender("  at read config: second -> BadConfig", &diag);
}

test "unit: fmt option detail renders on retained frame" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{
        .label = "parse field",
        .detail = stdx.diag.fmt("index {d}", .{42}),
    });
    frame.unwind(error.InvalidField);
    frame.pop();

    try expectRender("  at parse field: index 42 -> InvalidField", &diag);
}

test "unit: explicit formatted detail renders on retained frame" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{ .label = "parse field" });
    frame.detail(stdx.diag.fmt("index {d}", .{42}));
    frame.unwind(error.InvalidField);
    frame.pop();

    try expectRender("  at parse field: index 42 -> InvalidField", &diag);
}

test "unit: explicit detail overrides scope option detail" {
    const Diag = Diagnostics.Static(.{ .frames = 1, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{
        .label = "parse field",
        .detail = stdx.diag.fmt("{f}", .{ExplodingFormatter{}}),
    });
    frame.detail("manual detail");
    frame.unwind(error.InvalidField);
    frame.pop();

    try expectRender("  at parse field: manual detail -> InvalidField", &diag);
}

test "unit: clear removes retained frames and resets arena usage" {
    const Diag = Diagnostics.Static(.{ .frames = 3, .arena_bytes = 64 });
    var diag = Diag.init();
    defer diag.deinit();

    try testing.expectError(error.FileNotFound, failOneWithFormattedDetail(&diag));
    try testing.expect(!diag.isEmpty());
    try testing.expect(diag.arena.used() > 0);

    diag.clear();
    try testing.expect(diag.isEmpty());
    try testing.expectEqual(@as(usize, 0), diag.arena.used());
    try expectRender("", &diag);

    try testing.expectError(error.FileNotFound, failOne(&diag));
    try expectRender("  at open firmware: /boot/fw.bin -> FileNotFound", &diag);
}

test "unit: source location renders when present and is omitted when absent" {
    const Diag = Diagnostics.Static(.{ .frames = 2 });
    var diag = Diag.init();
    defer diag.deinit();

    var with_source = stdx.diag.scope(&diag, .{
        .label = "with source",
        .source = source("test/source.zig", 9),
    });
    with_source.unwind(error.Boom);
    with_source.pop();

    var without_source = stdx.diag.scope(&diag, .{ .label = "without source" });
    without_source.unwind(error.Boom);
    without_source.pop();

    try expectRender(
        "  at with source (test/source.zig:9) -> Boom\n" ++
            "  at without source -> Boom",
        &diag,
    );
}

test "unit: label and detail bytes are escaped for logs" {
    const Diag = Diagnostics.Static(.{ .frames = 1 });
    var diag = Diag.init();
    defer diag.deinit();

    var frame = stdx.diag.scope(&diag, .{
        .label = "load\\firmware\ncode",
        .detail = "path\twith\\slash",
    });
    frame.unwind(error.Bad);
    frame.pop();

    try expectRender("  at load\\\\firmware\\ncode: path\\twith\\\\slash -> Bad", &diag);
}
