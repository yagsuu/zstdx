const std = @import("std");

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

        modules.stdx.addImport("addr", modules.addr);
        modules.stdx.addImport("algo", modules.algo);
        modules.stdx.addImport("arch", modules.arch);
        modules.stdx.addImport("barrier", modules.barrier);
        modules.stdx.addImport("bits", modules.bits);
        modules.stdx.addImport("bytes", modules.bytes);
        modules.stdx.addImport("collections", modules.collections);
        modules.stdx.addImport("concurrent", modules.concurrent);
        modules.stdx.addImport("core", modules.core);
        modules.stdx.addImport("cpu", modules.cpu);
        modules.stdx.addImport("diag", modules.diag);
        modules.stdx.addImport("dma", modules.dma);
        modules.stdx.addImport("func", modules.func);
        modules.stdx.addImport("graph", modules.graph);
        modules.stdx.addImport("intrusive", modules.intrusive);
        modules.stdx.addImport("io", modules.io);
        modules.stdx.addImport("layout", modules.layout);
        modules.stdx.addImport("mem", modules.mem);
        modules.stdx.addImport("ranges", modules.ranges);
        modules.stdx.addImport("sync", modules.sync);
        modules.stdx.addImport("tags", modules.tags);
        modules.stdx.addImport("time", modules.time);

        modules.addr.addImport("layout", modules.layout);
        modules.algo.addImport("ranges", modules.ranges);
        modules.arch.addImport("addr", modules.addr);
        modules.arch.addImport("bits", modules.bits);
        modules.arch.addImport("core", modules.core);
        modules.barrier.addImport("arch", modules.arch);
        modules.bits.addImport("core", modules.core);
        modules.concurrent.addImport("layout", modules.layout);
        modules.cpu.addImport("core", modules.core);
        modules.cpu.addImport("layout", modules.layout);
        modules.diag.addImport("core", modules.core);
        modules.diag.addImport("layout", modules.layout);
        modules.diag.addImport("mem", modules.mem);
        modules.dma.addImport("addr", modules.addr);
        modules.func.addImport("layout", modules.layout);
        modules.intrusive.addImport("core", modules.core);
        modules.io.addImport("core", modules.core);
        modules.io.addImport("layout", modules.layout);
        modules.io.addImport("time", modules.time);
        modules.mem.addImport("addr", modules.addr);
        modules.mem.addImport("algo", modules.algo);
        modules.mem.addImport("bits", modules.bits);
        modules.mem.addImport("core", modules.core);
        modules.mem.addImport("cpu", modules.cpu);
        modules.mem.addImport("layout", modules.layout);
        modules.mem.addImport("sync", modules.sync);
        modules.mem.addImport("ranges", modules.ranges);
        modules.ranges.addImport("core", modules.core);
        modules.sync.addImport("core", modules.core);
        modules.tags.addImport("bits", modules.bits);
        modules.time.addImport("core", modules.core);

        return modules;
    }
};

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
