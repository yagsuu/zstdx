const std = @import("std");

const CompileFixture = struct {
    name: []const u8,
    path: []const u8,
    target: []const u8,
    expected: Expected,

    const Expected = union(enum) {
        success,
        failure: []const u8,
    };
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const stdx = b.addModule("stdx", .{
        .root_source_file = b.path("src/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all tests");
    addHostTests(b, test_step, stdx, target, optimize);
    addCompileFixtureTests(b, test_step);
}

fn addHostTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    stdx: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const root = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "stdx", .module = stdx }},
    });

    const tests = b.addTest(.{ .root_module = root });
    const run_tests = b.addRunArtifact(tests);

    const host_step = b.step("test-host", "Run host-side tests");
    host_step.dependOn(&run_tests.step);
    test_step.dependOn(host_step);
}

fn addCompileFixtureTests(b: *std.Build, test_step: *std.Build.Step) void {
    const fixtures = [_]CompileFixture{
        .{
            .name = "arch/x86_64/paging/explicit_target",
            .path = "test/fixtures/arch/x86_64/paging/explicit_target.zig",
            .target = "aarch64-freestanding-none",
            .expected = .success,
        },
        .{
            .name = "arch/x86_64/paging/current_cpu_target",
            .path = "test/fixtures/arch/x86_64/paging/current_cpu_target.zig",
            .target = "aarch64-freestanding-none",
            .expected = .{ .failure = "this operation requires an x86_64 target" },
        },
        .{
            .name = "arch/x86_64/registers/descriptor_wrappers",
            .path = "test/fixtures/arch/x86_64/registers/descriptor_wrappers.zig",
            .target = "x86_64-freestanding-none",
            .expected = .success,
        },
        .{
            .name = "core/range/inclusive_signed_type",
            .path = "test/fixtures/core/range/inclusive_signed_type.zig",
            .target = "native",
            .expected = .{ .failure = "InclusiveRange requires a non-zero-width unsigned integer type" },
        },
        .{
            .name = "core/range/inclusive_zero_width_type",
            .path = "test/fixtures/core/range/inclusive_zero_width_type.zig",
            .target = "native",
            .expected = .{ .failure = "InclusiveRange requires a non-zero-width unsigned integer type" },
        },
        .{
            .name = "core/range/inclusive_full_domain",
            .path = "test/fixtures/core/range/inclusive_full_domain.zig",
            .target = "native",
            .expected = .{ .failure = "InclusiveRange.of excludes [0, maxInt(T)]" },
        },
    };

    const fixture_step = b.step("test-compile", "Run compile fixtures");
    test_step.dependOn(fixture_step);

    for (fixtures) |fixture| {
        const compile = addCompileFixture(b, b.path(fixture.path), fixture.target);
        compile.setName(b.fmt("compile fixture {s}", .{fixture.name}));

        switch (fixture.expected) {
            .success => compile.expectExitCode(0),
            .failure => |stderr| {
                compile.expectExitCode(1);
                compile.expectStdErrMatch(stderr);
            },
        }

        fixture_step.dependOn(&compile.step);
    }
}

fn addCompileFixture(
    b: *std.Build,
    root: std.Build.LazyPath,
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
    compile.addPrefixedFileArg("-Mroot=", root);
    compile.addPrefixedFileArg("-Mstdx=", b.path("src/stdx.zig"));
    return compile;
}
