const std = @import("std");

const Modules = @import("modules.zig").Modules;

const Suite = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub fn addUnitTests(b: *std.Build, modules: *const Modules) *std.Build.Step {
    const suites = [_]Suite{
        .{ .name = "addr", .module = modules.addr },
        .{ .name = "algo", .module = modules.algo },
        .{ .name = "arch", .module = modules.arch },
        .{ .name = "barrier", .module = modules.barrier },
        .{ .name = "bits", .module = modules.bits },
        .{ .name = "bytes", .module = modules.bytes },
        .{ .name = "collections", .module = modules.collections },
        .{ .name = "concurrent", .module = modules.concurrent },
        .{ .name = "core", .module = modules.core },
        .{ .name = "cpu", .module = modules.cpu },
        .{ .name = "diag", .module = modules.diag },
        .{ .name = "dispatch", .module = modules.dispatch },
        .{ .name = "dma", .module = modules.dma },
        .{ .name = "graph", .module = modules.graph },
        .{ .name = "intrusive", .module = modules.intrusive },
        .{ .name = "io", .module = modules.io },
        .{ .name = "layout", .module = modules.layout },
        .{ .name = "mem", .module = modules.mem },
        .{ .name = "ranges", .module = modules.ranges },
        .{ .name = "sync", .module = modules.sync },
        .{ .name = "tags", .module = modules.tags },
        .{ .name = "time", .module = modules.time },
    };

    const unit_step = b.step("test-unit", "Run all unit tests");

    for (suites) |suite| {
        const category_step = b.step(
            b.fmt("test-{s}", .{suite.name}),
            b.fmt("Run {s} unit tests", .{suite.name}),
        );

        const tests = b.addTest(.{
            .name = b.fmt("unit-{s}", .{suite.name}),
            .root_module = suite.module,
        });

        const run_tests = b.addRunArtifact(tests);
        category_step.dependOn(&run_tests.step);
        unit_step.dependOn(category_step);
    }

    return unit_step;
}

pub fn addIntegrationTests(b: *std.Build, modules: *const Modules) *std.Build.Step {
    const root = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = b.graph.host,
        .optimize = modules.stdx.optimize.?,
        .imports = &.{.{ .name = "stdx", .module = modules.stdx }},
    });

    const tests = b.addTest(.{
        .name = "integration",
        .root_module = root,
    });

    const run_tests = b.addRunArtifact(tests);
    const integration_step = b.step("test-integration", "Run cross-module integration tests");
    integration_step.dependOn(&run_tests.step);

    return integration_step;
}
