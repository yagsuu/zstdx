const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const stdx = b.addModule("stdx", .{
        .root_source_file = b.path("src/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests_root = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "stdx", .module = stdx }},
    });
    const tests = b.addTest(.{ .root_module = tests_root });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run host-side tests");
    test_step.dependOn(&run_tests.step);
    addTargetFixtureTests(b, test_step);
}

fn addTargetFixtureTests(b: *std.Build, test_step: *std.Build.Step) void {
    const fixtures = b.addWriteFiles();

    const explicit_target_test = addCompileFixture(
        b,
        fixtures.add("paging-explicit-target.zig", pagingExplicitTargetFixture()),
        "aarch64-freestanding-none",
    );
    explicit_target_test.expectExitCode(0);

    const current_cpu_target_test = addCompileFixture(
        b,
        fixtures.add("paging-current-cpu-target.zig", pagingCurrentCpuTargetFixture()),
        "aarch64-freestanding-none",
    );
    current_cpu_target_test.expectExitCode(1);
    current_cpu_target_test.expectStdErrMatch("this operation requires an x86_64 target");

    const descriptor_wrapper_test = addCompileFixture(
        b,
        fixtures.add("x86-descriptor-wrappers.zig", descriptorWrapperFixture()),
        "x86_64-freestanding-none",
    );
    descriptor_wrapper_test.expectExitCode(0);

    test_step.dependOn(&explicit_target_test.step);
    test_step.dependOn(&current_cpu_target_test.step);
    test_step.dependOn(&descriptor_wrapper_test.step);
}

fn pagingExplicitTargetFixture() []const u8 {
    return
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
    ;
}

fn pagingCurrentCpuTargetFixture() []const u8 {
    return
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
    ;
}

fn descriptorWrapperFixture() []const u8 {
    return
    \\const registers = @import("stdx").arch.x86_64.registers;
    \\
    \\export fn descriptorWrites(
    \\    gdtr: registers.gdtr.GDTR,
    \\    idtr: registers.idtr.IDTR,
    \\    tr: registers.tr.TR,
    \\    ldtr: registers.ldtr.LDTR,
    \\) void {
    \\    registers.gdtr.write(gdtr);
    \\    registers.idtr.write(idtr);
    \\    registers.tr.write(tr);
    \\    registers.ldtr.write(ldtr);
    \\}
    \\
    \\export fn descriptorReads() void {
    \\    _ = registers.gdtr.read();
    \\    _ = registers.idtr.read();
    \\    _ = registers.tr.read();
    \\    _ = registers.ldtr.read();
    \\}
    ;
}

fn addCompileFixture(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: []const u8,
) *std.Build.Step.Run {
    const compile = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build-obj",
        "-target",
        target,
        "--dep",
        "stdx",
        "-fno-emit-bin",
    });
    compile.addPrefixedFileArg("-Mroot=", root_source_file);
    compile.addPrefixedFileArg("-Mstdx=", b.path("src/stdx.zig"));
    return compile;
}
