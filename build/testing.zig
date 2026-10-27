const std = @import("std");

const Modules = @import("modules.zig").Modules;

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

pub fn addHostTests(
    b: *std.Build,
    modules: *const Modules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
) *std.Build.Step {
    const host_step = b.step("test-host", "Run host-side tests");
    const categories = [_][]const u8{
        "core",        "bits",      "addr", "ranges", "graph", "layout", "bytes", "mem",
        "collections", "intrusive", "algo", "tags",   "arch",  "diag",   "sync",  "concurrent",
        "io",          "barrier",   "time", "dma",    "cpu",   "func",
    };

    for (categories) |category| {
        const category_step = b.step(
            b.fmt("test-{s}", .{category}),
            b.fmt("Run {s} tests", .{category}),
        );

        host_step.dependOn(category_step);

        if (std.mem.eql(u8, category, "core")) {
            addSuite(b, category_step, check_step, modules.core);
            continue;
        }

        if (std.mem.eql(u8, category, "addr")) {
            addSuite(b, category_step, check_step, modules.addr);
            continue;
        }

        if (std.mem.eql(u8, category, "bytes")) {
            addSuite(b, category_step, check_step, modules.bytes);
            continue;
        }

        if (std.mem.eql(u8, category, "collections")) {
            addSuite(b, category_step, check_step, modules.collections);
            continue;
        }

        if (std.mem.eql(u8, category, "ranges")) {
            addSuite(b, category_step, check_step, modules.ranges);
            continue;
        }

        if (std.mem.eql(u8, category, "graph")) {
            addSuite(b, category_step, check_step, modules.graph);
            continue;
        }

        if (std.mem.eql(u8, category, "bits")) {
            addSuite(b, category_step, check_step, modules.bits);
            continue;
        }

        if (std.mem.eql(u8, category, "tags")) {
            addSuite(b, category_step, check_step, modules.tags);
            continue;
        }

        if (std.mem.eql(u8, category, "layout")) {
            addSuite(b, category_step, check_step, modules.layout);
            continue;
        }

        if (std.mem.eql(u8, category, "func")) {
            addSuite(b, category_step, check_step, modules.func);
            continue;
        }

        if (std.mem.eql(u8, category, "time") or std.mem.eql(u8, category, "sync")) {
            const module = if (std.mem.eql(u8, category, "time")) modules.time else modules.sync;
            addSuite(b, category_step, check_step, module);
        }

        if (std.mem.eql(u8, category, "mem")) {
            addSuite(b, category_step, check_step, modules.mem);
        }

        if (std.mem.eql(u8, category, "algo")) {
            addSuite(b, category_step, check_step, modules.algo);
            continue;
        }

        const root = b.createModule(.{
            .root_source_file = b.path(b.fmt("test/{s}/all.zig", .{category})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "stdx", .module = modules.stdx }},
        });

        addSuite(b, category_step, check_step, root);
    }

    return host_step;
}

pub fn addCompileFixtureTests(
    b: *std.Build,
    modules: *const Modules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step {
    const fixture_step = b.step("test-compile", "Run compile fixtures");

    var private_modules: [fixtures.len]Modules = undefined;
    var private_count: usize = 0;

    for (fixtures) |fixture| {
        const fixture_target = b.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = fixture.target }) catch unreachable,
        );

        const fixture_modules = matching: {
            if (target.query.eql(fixture_target.query) and modules.stdx.optimize == optimize) {
                break :matching modules;
            }

            for (private_modules[0..private_count]) |*candidate| {
                if (candidate.stdx.resolved_target.?.query.eql(fixture_target.query)) {
                    break :matching candidate;
                }
            }

            private_modules[private_count] = Modules.init(b, fixture_target, optimize, .private);

            const candidate = &private_modules[private_count];
            private_count += 1;
            break :matching candidate;
        };

        const compile = addCompileFixture(b, fixture, fixture_modules);
        fixture_step.dependOn(&compile.step);
    }

    return fixture_step;
}

fn addSuite(
    b: *std.Build,
    category_step: *std.Build.Step,
    check_step: *std.Build.Step,
    root_module: *std.Build.Module,
) void {
    const tests = b.addTest(.{ .root_module = root_module });
    const run_tests = b.addRunArtifact(tests);
    check_step.dependOn(&tests.step);
    category_step.dependOn(&run_tests.step);
}

fn addCompileFixture(
    b: *std.Build,
    fixture: CompileFixture,
    modules: *const Modules,
) *std.Build.Step.Compile {
    const root = b.createModule(.{
        .root_source_file = b.path(fixture.path),
        .target = modules.stdx.resolved_target.?,
        .optimize = modules.stdx.optimize.?,
        .imports = &.{.{ .name = "stdx", .module = modules.stdx }},
    });

    const compile = b.addObject(.{
        .name = std.fs.path.stem(fixture.path),
        .root_module = root,
    });

    compile.step.name = b.fmt("compile fixture {s}", .{fixture.name});

    switch (fixture.expected) {
        .success => {},
        .failure => |message| compile.expect_errors = .{ .contains = message },
    }

    return compile;
}

const fixtures = [_]CompileFixture{
    .{
        .name = "mem/alloc/page/static_extent",
        .path = "test/fixtures/mem/alloc/page/static_extent.zig",
        .target = "native",
        .expected = .{ .failure = "PageAllocator.Static extent overflows page address space" },
    },
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
