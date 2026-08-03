const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const host_target = b.standardTargetOptions(.{});

    const stdx = b.addModule("stdx", .{
        .root_source_file = b.path("src/stdx.zig"),
        .target = host_target,
        .optimize = optimize,
    });

    const tests_root = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = host_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "stdx", .module = stdx }},
    });
    const tests = b.addTest(.{ .root_module = tests_root });
    const run_tests = b.addRunArtifact(tests);

    const paging_target_fixtures = b.addWriteFiles();
    const explicit_target_fixture = paging_target_fixtures.add("paging-explicit-target.zig",
        \\const paging = @import("stdx").arch.x86_64.paging;
        \\
        \\const Reader = struct {
        \\    pub const Error = error{};
        \\    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.PagingStructureEntry {
        \\        return paging.PagingStructureEntry.empty();
        \\    }
        \\};
        \\
        \\export fn instantiatePagingWalker() void {
        \\    var reader = Reader{};
        \\    const Walker = paging.Walker(Reader);
        \\    const walker = Walker.init(.{
        \\        .root_table_base = paging.PhysAddr.fromInt(0),
        \\        .mode = .level4,
        \\        .physical_address_width = .bits_48,
        \\    }, &reader) catch unreachable;
        \\    _ = walker.translate(
        \\        paging.LinearAddress.fromInt(0),
        \\        .read(.supervisor),
        \\    ) catch unreachable;
        \\}
    );
    const current_cpu_target_fixture = paging_target_fixtures.add("paging-current-cpu-target.zig",
        \\const paging = @import("stdx").arch.x86_64.paging;
        \\
        \\const Reader = struct {
        \\    pub const Error = error{};
        \\    pub fn readEntry(_: *Reader, _: paging.PhysAddr) Error!paging.PagingStructureEntry {
        \\        unreachable;
        \\    }
        \\};
        \\
        \\export fn instantiateCurrentCPUWalker() void {
        \\    var reader = Reader{};
        \\    _ = paging.Walker(Reader).initCurrentCPU(&reader) catch unreachable;
        \\}
    );

    const explicit_target_test = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build-obj",
        "-target",
        "aarch64-freestanding-none",
        "--dep",
        "stdx",
        "-fno-emit-bin",
    });
    explicit_target_test.addPrefixedFileArg("-Mroot=", explicit_target_fixture);
    explicit_target_test.addPrefixedFileArg("-Mstdx=", b.path("src/stdx.zig"));
    explicit_target_test.expectExitCode(0);

    const current_cpu_target_test = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build-obj",
        "-target",
        "aarch64-freestanding-none",
        "--dep",
        "stdx",
        "-fno-emit-bin",
    });
    current_cpu_target_test.addPrefixedFileArg(
        "-Mroot=",
        current_cpu_target_fixture,
    );
    current_cpu_target_test.addPrefixedFileArg(
        "-Mstdx=",
        b.path("src/stdx.zig"),
    );
    current_cpu_target_test.expectExitCode(1);
    current_cpu_target_test.expectStdErrMatch(
        "this operation requires an x86_64 target",
    );

    const test_step = b.step("test", "Run host-side tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&explicit_target_test.step);
    test_step.dependOn(&current_cpu_target_test.step);
}
