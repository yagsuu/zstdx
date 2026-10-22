const std = @import("std");

const testing = @import("build/testing.zig");

const Modules = @import("build/modules.zig").Modules;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const modules = Modules.init(b, target, optimize, .public);

    const check_step = b.step("check", "Compile all host test suites");
    const host_step = testing.addHostTests(b, &modules, target, optimize, check_step);
    const fixture_step = testing.addCompileFixtureTests(b, &modules, target, optimize);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(host_step);
    test_step.dependOn(fixture_step);
}
