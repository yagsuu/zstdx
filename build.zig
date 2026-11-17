const std = @import("std");

const testing = @import("build/testing.zig");

const Modules = @import("build/modules.zig").Modules;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const modules = Modules.init(b, target, optimize, .public);
    const host_modules = if (target.query.eql(b.graph.host.query))
        modules
    else
        Modules.init(b, b.graph.host, optimize, .private);

    const unit_step = testing.addUnitTests(b, &host_modules);
    const integration_step = testing.addIntegrationTests(b, &host_modules);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(unit_step);
    test_step.dependOn(integration_step);
}
