const std = @import("std");

const ModuleImport = struct { []const u8, *std.Build.Module };

pub const Modules = struct {
    stdx: *std.Build.Module,
    addr: *std.Build.Module,
    algo: *std.Build.Module,
    arch: *std.Build.Module,
    barrier: *std.Build.Module,
    bits: *std.Build.Module,
    bytes: *std.Build.Module,
    collections: *std.Build.Module,
    concurrent: *std.Build.Module,
    core: *std.Build.Module,
    cpu: *std.Build.Module,
    diag: *std.Build.Module,
    dma: *std.Build.Module,
    func: *std.Build.Module,
    graph: *std.Build.Module,
    intrusive: *std.Build.Module,
    io: *std.Build.Module,
    layout: *std.Build.Module,
    mem: *std.Build.Module,
    ranges: *std.Build.Module,
    sync: *std.Build.Module,
    tags: *std.Build.Module,
    time: *std.Build.Module,

    pub const Visibility = enum {
        public,
        private,
    };

    pub fn init(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        visibility: Visibility,
    ) Modules {
        const opts: std.Build.Module.CreateOptions = .{
            .root_source_file = b.path("src/stdx.zig"),
            .target = target,
            .optimize = optimize,
        };

        const modules: Modules = .{
            .stdx = switch (visibility) {
                .public => b.addModule("stdx", opts),
                .private => b.createModule(opts),
            },
            .addr = addCategory(b, "addr", target, optimize, visibility),
            .algo = addCategory(b, "algo", target, optimize, visibility),
            .arch = addCategory(b, "arch", target, optimize, visibility),
            .barrier = addCategory(b, "barrier", target, optimize, visibility),
            .bits = addCategory(b, "bits", target, optimize, visibility),
            .bytes = addCategory(b, "bytes", target, optimize, visibility),
            .collections = addCategory(b, "collections", target, optimize, visibility),
            .concurrent = addCategory(b, "concurrent", target, optimize, visibility),
            .core = addCategory(b, "core", target, optimize, visibility),
            .cpu = addCategory(b, "cpu", target, optimize, visibility),
            .diag = addCategory(b, "diag", target, optimize, visibility),
            .dma = addCategory(b, "dma", target, optimize, visibility),
            .func = addCategory(b, "func", target, optimize, visibility),
            .graph = addCategory(b, "graph", target, optimize, visibility),
            .intrusive = addCategory(b, "intrusive", target, optimize, visibility),
            .io = addCategory(b, "io", target, optimize, visibility),
            .layout = addCategory(b, "layout", target, optimize, visibility),
            .mem = addCategory(b, "mem", target, optimize, visibility),
            .ranges = addCategory(b, "ranges", target, optimize, visibility),
            .sync = addCategory(b, "sync", target, optimize, visibility),
            .tags = addCategory(b, "tags", target, optimize, visibility),
            .time = addCategory(b, "time", target, optimize, visibility),
        };

        addImports(modules.stdx, &.{
            .{ "addr", modules.addr },
            .{ "algo", modules.algo },
            .{ "arch", modules.arch },
            .{ "barrier", modules.barrier },
            .{ "bits", modules.bits },
            .{ "bytes", modules.bytes },
            .{ "collections", modules.collections },
            .{ "concurrent", modules.concurrent },
            .{ "core", modules.core },
            .{ "cpu", modules.cpu },
            .{ "diag", modules.diag },
            .{ "dma", modules.dma },
            .{ "func", modules.func },
            .{ "graph", modules.graph },
            .{ "intrusive", modules.intrusive },
            .{ "io", modules.io },
            .{ "layout", modules.layout },
            .{ "mem", modules.mem },
            .{ "ranges", modules.ranges },
            .{ "sync", modules.sync },
            .{ "tags", modules.tags },
            .{ "time", modules.time },
        });

        addImports(modules.addr, &.{
            .{ "layout", modules.layout },
            .{ "ranges", modules.ranges },
        });

        addImports(modules.algo, &.{
            .{ "ranges", modules.ranges },
        });

        addImports(modules.arch, &.{
            .{ "addr", modules.addr },
            .{ "bits", modules.bits },
            .{ "core", modules.core },
        });

        addImports(modules.barrier, &.{
            .{ "arch", modules.arch },
        });

        addImports(modules.bits, &.{
            .{ "core", modules.core },
        });

        addImports(modules.concurrent, &.{
            .{ "layout", modules.layout },
        });

        addImports(modules.cpu, &.{
            .{ "core", modules.core },
            .{ "layout", modules.layout },
        });

        addImports(modules.diag, &.{
            .{ "core", modules.core },
            .{ "layout", modules.layout },
            .{ "mem", modules.mem },
        });

        addImports(modules.dma, &.{
            .{ "addr", modules.addr },
        });

        addImports(modules.func, &.{
            .{ "layout", modules.layout },
        });

        addImports(modules.intrusive, &.{
            .{ "core", modules.core },
        });

        addImports(modules.io, &.{
            .{ "core", modules.core },
            .{ "layout", modules.layout },
            .{ "time", modules.time },
        });

        addImports(modules.mem, &.{
            .{ "addr", modules.addr },
            .{ "algo", modules.algo },
            .{ "bits", modules.bits },
            .{ "core", modules.core },
            .{ "cpu", modules.cpu },
            .{ "layout", modules.layout },
            .{ "ranges", modules.ranges },
            .{ "sync", modules.sync },
        });

        addImports(modules.ranges, &.{
            .{ "core", modules.core },
        });

        addImports(modules.sync, &.{
            .{ "core", modules.core },
        });

        addImports(modules.tags, &.{
            .{ "bits", modules.bits },
        });

        addImports(modules.time, &.{
            .{ "core", modules.core },
        });

        return modules;
    }
};

fn addImports(module: *std.Build.Module, imports: []const ModuleImport) void {
    for (imports) |entry| {
        module.addImport(entry[0], entry[1]);
    }
}

fn addCategory(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    visibility: Modules.Visibility,
) *std.Build.Module {
    const opts: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path(b.fmt("src/{s}/module.zig", .{name})),
        .target = target,
        .optimize = optimize,
    };
    return switch (visibility) {
        .public => b.addModule(name, opts),
        .private => b.createModule(opts),
    };
}
